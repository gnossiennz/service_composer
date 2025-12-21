//// The dispatcher: a genserver actor that dispatches recipes

import app/engine/dispatch_step/dispatch as dispatch_executor
import app/engine/dispatch_step/update.{MaybeSubstitutedRecipe} as updater
import app/engine/dispatcher_store.{
  type DispatcherStoreMessage, AddOrUpdateRecipe, GetRecipe,
  IncrementClientRequest, IncrementClientResponse,
  IncrementDispatchAcknowledgement, IncrementServiceResult,
} as store
import app/types/client_response.{type ArgumentSubmission}
import app/types/dispatch.{type DispatchInfo}
import app/types/recipe.{type Recipe, type RecipeInstanceID, Recipe}
import app/types/service_call.{
  type DispatcherReturn, type ServiceCallResponse, DispatcherReturnServiceCall,
  ServiceCallResponse, ServiceReturnRequest, ServiceReturnResult,
}
import app/types/service_provider
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import serde/recipe/step/encoder as recipe_step_encoder

pub type KnownSubjectKey {
  SubmitStepAcknowledgeKey
  ReceiveServiceCallResponseKey
}

pub type KnownSubject {
  SubmitStepAcknowledge(subject: Subject(Result(String, String)))
  ReceiveServiceCallResponse(subject: Subject(DispatcherReturn))
}

pub type State {
  State(
    self: Subject(DispatcherServiceMessage),
    store: Subject(DispatcherStoreMessage),
    service_dictionary: Dict(String, DispatchInfo),
    subject_dictionary: Dict(KnownSubjectKey, KnownSubject),
  )
}

pub type DispatcherServiceMessage {
  // Tell the actor to stop
  Shutdown

  // Add a new service to the dispatcher
  AddService

  // Add a new recipe instance and start executing it
  AddRecipe(recipe: Recipe)

  // Receive acknowledgement from a service provider that a step has been accepted
  ReceiveAcknowledgeSubmitStep(result: Result(String, String))

  // Continue running a recipe using an update from the client
  ReceiveClientUpdate(submission: ArgumentSubmission)

  // Continue running a recipe using an update from the service
  ReceiveServiceUpdate(result: DispatcherReturn)

  // Query the status of the running recipe instance with 'id'
  QueryStatus(id: String, reply_with: Subject(store.RecipeState))

  // Get the service IDs of the loaded provider modules
  QueryServices(reply_with: Subject(List(String)))

  // Register a listening actor with the store
  // normally this is a Glisten Actor (e.g. a Mist web socket process)
  RegisterListener(
    sender: Subject(ServiceCallResponse),
    instance_id: RecipeInstanceID,
  )
}

pub fn supervised(
  name: Name(DispatcherServiceMessage),
  provider_dispatch_dict: Dict(String, DispatchInfo),
) -> ChildSpecification(Subject(DispatcherServiceMessage)) {
  supervision.worker(fn() { start(name, provider_dispatch_dict) })
}

fn make_initializer(
  self: Subject(DispatcherServiceMessage),
  service_dictionary: Dict(String, DispatchInfo),
) -> actor.Initialised(
  State,
  DispatcherServiceMessage,
  Subject(DispatcherServiceMessage),
) {
  // create subjects that receive messages from the service providers
  let submit_step_acknowledge: Subject(Result(String, String)) =
    process.new_subject()
  let receive_service_call_response: Subject(DispatcherReturn) =
    process.new_subject()

  // map the subjects to the message loop types
  let selector =
    process.new_selector()
    |> process.select(self)
    |> process.select_map(submit_step_acknowledge, fn(result) {
      ReceiveAcknowledgeSubmitStep(result)
    })
    |> process.select_map(receive_service_call_response, fn(result) {
      ReceiveServiceUpdate(result)
    })

  // add the new subjects to the subject dictionary
  let subject_dictionary: Dict(KnownSubjectKey, KnownSubject) =
    dict.new()
    |> dict.insert(
      SubmitStepAcknowledgeKey,
      SubmitStepAcknowledge(submit_step_acknowledge),
    )
    |> dict.insert(
      ReceiveServiceCallResponseKey,
      ReceiveServiceCallResponse(receive_service_call_response),
    )

  // start the result store
  let assert Ok(actor.Started(pid: _, data: store)) = store.start()

  // register this actor as a listener to each of the service provider services
  service_dictionary
  |> dict.values()
  |> list.each(fn(dispatch_info) {
    dispatch_info.process_name
    |> process.named_subject()
    |> process.send(service_provider.RegisterListener(
      receive_service_call_response,
    ))
  })

  let state = State(self:, store:, service_dictionary:, subject_dictionary:)

  actor.initialised(state)
  |> actor.selecting(selector)
  |> actor.returning(self)
}

pub fn start(
  name: Name(DispatcherServiceMessage),
  provider_name_dict: Dict(String, DispatchInfo),
) -> Result(actor.Started(Subject(DispatcherServiceMessage)), actor.StartError) {
  actor.new_with_initialiser(100, fn(self) {
    self
    |> make_initializer(provider_name_dict)
    |> Ok
  })
  // register the name for this service
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn handle_message(
  state: State,
  message: DispatcherServiceMessage,
) -> actor.Next(State, DispatcherServiceMessage) {
  case message {
    Shutdown -> actor.stop()

    // TODO
    AddService -> actor.continue(state)

    // Store a new recipe instance and start executing it
    AddRecipe(
      Recipe(id: _, iid: _, description: _, root: _, error: None) as recipe,
    ) -> {
      // store the recipe with default values for status and last service call response
      process.send(state.store, AddOrUpdateRecipe(recipe, store.Pending))

      // Submit the recipe
      submit_recipe(state, recipe, None)

      // continue (but expecting an acknowledgement message)
      actor.continue(state)
    }

    AddRecipe(Recipe(id: _, iid: _, description: _, root: _, error: Some(_))) -> {
      // log the error
      // TODO

      actor.continue(state)
    }

    ReceiveAcknowledgeSubmitStep(result) -> {
      // receive acknowledgement of a step submitted to the relevant service provider
      case result {
        Ok(recipe_instance_id) -> {
          // update the status in the store
          process.send(
            state.store,
            IncrementDispatchAcknowledgement(recipe_instance_id),
          )
        }
        Error(_description) -> {
          // TODO log the error
          Nil
        }
      }

      actor.continue(state)
    }

    ReceiveClientUpdate(submission) -> {
      // update the status in the store
      process.send(
        state.store,
        IncrementClientResponse(submission.recipe_instance_id),
      )

      case get_recipe(state.store, submission.recipe_instance_id) {
        Ok(recipe_state) -> {
          submit_recipe(state, recipe_state.recipe, Some(submission))
        }
        Error(_description) -> {
          // TODO log error
          Nil
        }
      }

      actor.continue(state)
    }

    // Process the result from the service call
    ReceiveServiceUpdate(result) -> {
      case handle_service_update(state, result) {
        Error(_error) -> {
          // TODO log error
          Nil
        }
        _ -> Nil
      }

      actor.continue(state)
    }

    QueryStatus(recipe_instance_id, client) -> {
      case get_recipe(state.store, recipe_instance_id) {
        Ok(recipe_state) -> {
          process.send(client, recipe_state)
        }
        Error(_description) -> {
          // TODO log error
          Nil
        }
      }

      actor.continue(state)
    }

    QueryServices(client) -> {
      let service_ids =
        state.service_dictionary
        |> dict.keys()
      process.send(client, service_ids)

      actor.continue(state)
    }

    RegisterListener(sender, instance_id) -> {
      process.send(state.store, store.RegisterListener(sender, instance_id))

      actor.continue(state)
    }
  }
}

fn submit_recipe(
  state: State,
  recipe: Recipe,
  submission: Option(ArgumentSubmission),
) -> Nil {
  // look up the sender subject for an 'submit step' acknowledgement
  let assert Ok(SubmitStepAcknowledge(sender)) =
    state.subject_dictionary
    |> dict.get(SubmitStepAcknowledgeKey)

  // find the next execution-eligible step within the recipe
  // and call the service provider associated with the step
  // the sender is passed to the service provider so it can acknowledge receipt of the step
  case
    dispatch_executor.run_next_step(
      sender,
      state.service_dictionary,
      recipe,
      submission,
    )
  {
    Ok(Nil) -> Nil
    Error(description) -> {
      // TODO log the error
      // this call will only return an error if the client response provides the wrong service
      // for initial dispatch the client response is None and an error cannot be returned
      echo #("submit_recipe error: ", description)

      // set the execution status to suspending
      process.send(
        state.store,
        AddOrUpdateRecipe(recipe, store.Suspending(None)),
      )
    }
  }
}

fn handle_service_update(
  state: State,
  dispatcher_return: DispatcherReturn,
) -> Result(Nil, String) {
  // retrieve the recipe from the store
  use recipe_state <- result.try(get_recipe(
    state.store,
    dispatcher_return.recipe_instance_id,
  ))

  // update the stats for this recipe in the store
  process.send(
    state.store,
    IncrementServiceResult(dispatcher_return.recipe_instance_id),
  )

  recipe_state.recipe
  |> updater.maybe_update_recipe(dispatcher_return)
  |> result.map(fn(updated) {
    get_next_execution_state(updated, dispatcher_return)
  })
  |> result.map(fn(next_state) { perform_actions(state, next_state) })
}

fn perform_actions(state: State, next_state) -> Nil {
  let #(updated_recipe, execution_status) = next_state

  // store the updates to recipe and status
  process.send(state.store, AddOrUpdateRecipe(updated_recipe, execution_status))

  case execution_status {
    store.Pending -> Nil
    store.Requesting(_) -> {
      // Note the the client request statistic is incremented
      // even when there are no connected clients
      process.send(state.store, IncrementClientRequest(updated_recipe.iid))
    }
    store.Resubmitting -> submit_recipe(state, updated_recipe, None)
    store.Completing(_) -> Nil
    store.Suspending(_) -> {
      // TODO log the error response that caused the suspension
      Nil
    }
  }
}

fn get_next_execution_state(
  updated: updater.MaybeSubstitutedRecipe,
  dispatcher_return: DispatcherReturn,
) -> #(Recipe, store.RecipeExecutionStatus) {
  let MaybeSubstitutedRecipe(substituted:, recipe: maybe_updated_recipe) =
    updated

  let next_state = case substituted {
    True -> {
      // the current step has been substituted
      // and therefore has updated the arguments of its parent step
      // it can continue to run until another result is produced
      store.Resubmitting
    }
    False -> {
      case dispatcher_return {
        DispatcherReturnServiceCall(recipe_instance_id: _, service_state:) -> {
          // if the return value is a result then it must be the FINAL result
          // as no substitution has occurred
          case service_state.service_return {
            ServiceReturnResult(_result) -> store.Completing(service_state)
            ServiceReturnRequest(_request) -> store.Requesting(service_state)
          }
        }
        _ -> {
          // the call to the service provider has returned an error
          // suspend the recipe until it is resolved
          store.Suspending(
            Some(ServiceCallResponse(
              recipe_id: maybe_updated_recipe.id,
              recipe_desc: recipe_step_encoder.encode(maybe_updated_recipe.root),
              dispatcher_return:,
            )),
          )
        }
      }
    }
  }
  #(maybe_updated_recipe, next_state)
}

fn get_recipe(sender: Subject(DispatcherStoreMessage), instance_id) {
  process.call(sender, 100, GetRecipe(instance_id, _))
}
