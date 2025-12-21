//// A 'service provider' service:
//// A generic service that performs a task specified by a resolver function
//// that is injected at service initialization
//// (the module providing this function is called the 'service provider')
//// Most service provider actors are expected to be long-running
//// such as a call to a long-running cloud service
//// This actor must not be linked to the caller (the dispatcher service)

import app/types/recipe.{type Argument, type Arguments, type ComposableStep}
import app/types/service_call.{type DispatcherReturn}
import app/types/service_provider.{
  type ServiceProviderMessage, RegisterListener, RunNextJob, Shutdown,
  SubmitStep,
}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

// For now:
// Store a jobs dictionary by recipe instance ID
// and a results dictionary by recipe instance ID
// and a pretend queue of recipe IDs
// TODO consider using a job manager such as Oban
pub type State {
  State(
    self: Subject(ServiceProviderMessage),
    listener: Option(Subject(DispatcherReturn)),
    resolver_fn: fn(String, Option(Argument), Arguments) -> DispatcherReturn,
    jobs: Dict(String, RunQueueData),
    queue: List(String),
  )
}

pub type RunQueueData {
  RunQueueData(step: ComposableStep, maybe_update: Option(Argument))
}

pub type JobState {
  Pending
  NotKnown
}

pub fn supervised(
  name: Name(ServiceProviderMessage),
  resolver_fn: fn(String, Option(Argument), Arguments) -> DispatcherReturn,
) -> ChildSpecification(Subject(ServiceProviderMessage)) {
  supervision.worker(fn() { start(name, resolver_fn) })
}

pub fn start(
  name: Name(ServiceProviderMessage),
  resolver_fn: fn(String, Option(Argument), Arguments) -> DispatcherReturn,
) -> Result(actor.Started(Subject(ServiceProviderMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) {
    // echo #("PS Provider Service start(): ", name, resolver_fn)
    let state =
      State(self:, listener: None, resolver_fn:, jobs: dict.new(), queue: [])
    state
    |> actor.initialised()
    |> actor.returning(self)
    |> Ok
  })
  // register the name for this service
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn handle_message(
  state: State,
  message: ServiceProviderMessage,
) -> actor.Next(State, ServiceProviderMessage) {
  case message {
    Shutdown -> actor.stop()

    SubmitStep(sender, recipe_instance_id, step, maybe_update) -> {
      case dict.has_key(state.jobs, recipe_instance_id) {
        False -> {
          let new_state = add_job(state, recipe_instance_id, step, maybe_update)

          process.send(sender, Ok(recipe_instance_id))
          process.send(state.self, RunNextJob)
          actor.continue(new_state)
        }
        True -> {
          process.send(
            sender,
            Error(
              "A step for this recipe is already running: "
              <> recipe_instance_id,
            ),
          )
          actor.continue(state)
        }
      }
    }

    RunNextJob -> {
      let #(new_state, job) = pop_job(state)

      case job {
        None -> Nil
        Some(#(recipe_instance_id, RunQueueData(step:, maybe_update:))) -> {
          // run the step
          let arguments = step.arguments |> option.unwrap([])
          let service_response =
            state.resolver_fn(recipe_instance_id, maybe_update, arguments)

          // send result to the registered listener
          case state.listener {
            Some(listener) -> process.send(listener, service_response)
            None -> Nil
          }
        }
      }

      actor.continue(new_state)
    }

    RegisterListener(sender) -> {
      // echo #("PS RegisterListener: ", sender)
      actor.continue(State(..state, listener: Some(sender)))
    }
  }
}

fn add_job(
  state: State,
  recipe_instance_id: String,
  step: ComposableStep,
  maybe_update: Option(Argument),
) -> State {
  State(
    ..state,
    jobs: dict.insert(
      state.jobs,
      recipe_instance_id,
      RunQueueData(step, maybe_update),
    ),
    queue: [recipe_instance_id, ..state.queue],
  )
}

fn pop_job(state: State) -> #(State, Option(#(String, RunQueueData))) {
  case state.queue {
    [] -> #(state, None)
    [_, ..] -> pop_selected_job(state)
  }
}

fn pop_selected_job(state: State) -> #(State, Option(#(String, RunQueueData))) {
  // call only on a non-empty queue
  let assert Ok(next_key) = list.last(state.queue)
  let assert Ok(data) = dict.get(state.jobs, next_key)
  let updated_jobs = dict.delete(state.jobs, next_key)
  let updated_queue = {
    let assert [_, ..rest] = list.reverse(state.queue)
    list.reverse(rest)
  }

  #(
    State(..state, jobs: updated_jobs, queue: updated_queue),
    Some(#(next_key, data)),
  )
}
