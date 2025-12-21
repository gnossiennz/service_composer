//// A service for testing services with long-running calls to APIs

import app/service_provider/provider_service.{type JobState}
import app/types/recipe
import app/types/service_call.{type DispatcherReturn}
import app/types/service_provider.{
  type ServiceProviderMessage, RegisterListener, SubmitStep,
}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import serde/recipe/step/decoder as recipe_step_decoder

pub type TestResult {
  SubmitStepReceived(Result(String, String))
  ServiceResponseReceived(DispatcherReturn)
  QueryReceived(JobState)
  TimedOut
}

pub type SubjectKey {
  SelfKey
  SubmitStepKey
  ServiceCallKey
  QueryKey
}

pub type SubjectMapper {
  Self(
    subject: Subject(TestingServiceMessage),
    mapper: fn(TestingServiceMessage) -> TestingServiceMessage,
  )
  SubjectSubmitStep(
    subject: Subject(Result(String, String)),
    mapper: fn(Result(String, String)) -> TestingServiceMessage,
  )
  SubjectServiceCall(
    subject: Subject(DispatcherReturn),
    mapper: fn(DispatcherReturn) -> TestingServiceMessage,
  )
  SubjectQuery(
    subject: Subject(JobState),
    mapper: fn(JobState) -> TestingServiceMessage,
  )
}

pub type State {
  State(
    self: Subject(TestingServiceMessage),
    provider_service_name: Name(ServiceProviderMessage),
    known_subjects: Dict(SubjectKey, SubjectMapper),
    results: List(TestResult),
    seen_results: Int,
  )
}

pub type TestingServiceMessage {
  Shutdown

  StartTest(recipe_instance_id: String, recipe_step: String)

  ReceiveTestResult(result: TestResult)

  GetNextResult(sender: Subject(Option(TestResult)))
}

/// Start the testing service
/// The service wraps an actor whose identity and function
/// are determined by the start function arguments
pub fn start(
  name,
  resolver_fn,
) -> Result(
  actor.Started(
    #(Dict(SubjectKey, SubjectMapper), Name(ServiceProviderMessage)),
  ),
  actor.StartError,
) {
  // returns a dictionary of known subjects (that the testing service can respond to)
  // and the wrapped service that is being tested
  actor.new_with_initialiser(100, fn(self) {
    let known_subjects = get_subjects(self)

    let selector = create_selector(dict.values(known_subjects))
    let state =
      State(
        self:,
        provider_service_name: start_wrapped_service(
          name,
          resolver_fn,
          known_subjects,
        ),
        known_subjects:,
        results: [],
        seen_results: 0,
      )

    state
    |> actor.initialised()
    |> actor.selecting(selector)
    |> actor.returning(#(known_subjects, state.provider_service_name))
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn make_receiver(
  service: Subject(_),
) -> fn(Option(TestResult)) -> Option(TestResult) {
  fn(last_received) { receive_result(service, last_received) }
}

pub fn make_submitter(
  service: Subject(TestingServiceMessage),
) -> fn(TestingServiceMessage) -> Option(TestResult) {
  fn(submit_message: TestingServiceMessage) {
    process.send(service, submit_message)

    None
  }
}

fn start_wrapped_service(
  name: Name(ServiceProviderMessage),
  resolver_fn: fn(String, Option(recipe.Argument), recipe.Arguments) ->
    DispatcherReturn,
  subjects: Dict(SubjectKey, SubjectMapper),
) -> Name(ServiceProviderMessage) {
  // start an instance of 'provider_service' that is referenced by 'name'
  // the services provided by this instance are determined by 'resolver_fn'
  let assert Ok(actor.Started(_pid, service_provider_actor)) =
    provider_service.start(name, resolver_fn)

  // register a subject with the new instance for receiving results
  let assert SubjectServiceCall(service_call_result_subject, _) =
    lookup_subject(subjects, ServiceCallKey)

  process.send(
    service_provider_actor,
    RegisterListener(service_call_result_subject),
  )

  name
}

fn handle_message(
  state: State,
  message: TestingServiceMessage,
) -> actor.Next(State, TestingServiceMessage) {
  case message {
    Shutdown -> {
      state.provider_service_name
      |> process.named_subject()
      |> process.send(service_provider.Shutdown)
      actor.stop()
    }

    StartTest(recipe_instance_id, recipe_step) -> {
      // echo #("STS Received StartTest: ", state.results)
      let assert SubjectSubmitStep(submit_step_result_subject, _) =
        lookup_subject(state.known_subjects, SubmitStepKey)

      submit_step(
        state.provider_service_name,
        submit_step_result_subject,
        recipe_instance_id,
        recipe_step,
      )

      actor.continue(state)
    }

    ReceiveTestResult(result) -> {
      // echo #("STS ReceiveTestResult: ", result)
      let new_results = [result, ..state.results]

      actor.continue(State(..state, results: new_results))
    }

    GetNextResult(sender) -> {
      // get the next result or None if there is no new result
      let last_result = state.results |> get_next_result(state.seen_results)

      // echo #("STS Within GetLastResult: ", last_result)

      process.send(sender, last_result)
      case last_result {
        None -> actor.continue(state)
        Some(_) ->
          actor.continue(State(..state, seen_results: state.seen_results + 1))
      }
    }
  }
}

fn get_next_result(current: List(TestResult), seen: Int) {
  // assume that 'seen' is in the range 0..len(current)
  current
  |> list.reverse()
  |> list.drop(seen)
  |> list.first()
  |> option.from_result()
}

fn lookup_subject(
  subjects: Dict(SubjectKey, SubjectMapper),
  key: SubjectKey,
) -> SubjectMapper {
  let assert Ok(subject) = dict.get(subjects, key)

  subject
}

fn submit_step(
  service_name: Name(ServiceProviderMessage),
  sender: Subject(Result(String, String)),
  recipe_instance_id: String,
  recipe_step: String,
) {
  let services =
    dict.from_list([#("calc", "com.examples.service_composer:calc")])
  let assert Ok(step) = recipe_step_decoder.decode(recipe_step, services)
  // echo #("STS Submitting step to named: ", step, service_name)

  service_name
  |> process.named_subject()
  |> process.send(SubmitStep(sender, recipe_instance_id, step, None))
}

fn get_subjects(
  self: Subject(TestingServiceMessage),
) -> Dict(SubjectKey, SubjectMapper) {
  let subject_submit_step: Subject(Result(String, String)) =
    process.new_subject()

  let subject_service_call: Subject(DispatcherReturn) = process.new_subject()

  let subject_query: Subject(JobState) = process.new_subject()

  dict.from_list([
    #(SelfKey, Self(self, fn(message) { message })),
    #(
      SubmitStepKey,
      SubjectSubmitStep(subject_submit_step, fn(message) {
        ReceiveTestResult(SubmitStepReceived(message))
      }),
    ),
    #(
      ServiceCallKey,
      SubjectServiceCall(subject_service_call, fn(message) {
        ReceiveTestResult(ServiceResponseReceived(message))
      }),
    ),
    #(
      QueryKey,
      SubjectQuery(subject: subject_query, mapper: fn(message) {
        ReceiveTestResult(QueryReceived(message))
      }),
    ),
  ])
}

fn create_selector(
  subjects: List(SubjectMapper),
) -> process.Selector(TestingServiceMessage) {
  subjects
  |> list.fold(process.new_selector(), fn(selector, sub) {
    case sub {
      Self(subject:, mapper:) -> process.select_map(selector, subject, mapper)
      SubjectSubmitStep(subject:, mapper:) ->
        process.select_map(selector, subject, mapper)
      SubjectServiceCall(subject:, mapper:) ->
        process.select_map(selector, subject, mapper)
      SubjectQuery(subject:, mapper:) ->
        process.select_map(selector, subject, mapper)
    }
  })
}

fn receive_result(
  testing_service: Subject(TestingServiceMessage),
  last_received: Option(TestResult),
) -> Option(TestResult) {
  // try this number of times and then time out
  let intervals = list.repeat(100, times: 20)

  // poll until the result changes from the last_received value
  intervals
  |> list.fold_until(last_received, fn(acc, interval) {
    process.sleep(interval)
    let result = testing_service |> process.call(50, GetNextResult)
    case result {
      None -> list.Continue(acc)
      result if result == acc -> list.Continue(acc)
      result -> list.Stop(result)
    }
  })
  |> fn(result) {
    // echo #("receive_result: ", result)
    case result == last_received {
      True -> Some(TimedOut)
      False -> result
    }
  }
}
