//// Message type used by a service provider instance

import app/types/recipe.{type Argument, type ComposableStep}
import app/types/service_call.{type DispatcherReturn}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

pub type ServiceProviderMessage {
  // Tell the actor to stop
  Shutdown

  // Submit a step to the queue
  // A step may be submitted multiple times as its arguments are defined by the client
  // However, a step may not be resubmitted until processing of the step is complete
  SubmitStep(
    sender: Subject(Result(String, String)),
    recipe_instance_id: String,
    step: ComposableStep,
    maybe_update: Option(Argument),
  )

  // Run the next available step and (eventually)
  // return a response to the registered listener
  RunNextJob

  // Register a listening actor (normally this is the dispatcher service)
  RegisterListener(sender: Subject(DispatcherReturn))
}
