//// Finds the current step and dispatches to the appropriate service

import app/types/client_response.{type ArgumentSubmission}
import app/types/dispatch.{type DispatchInfo}
import app/types/recipe.{
  type Argument, type Arguments, type ComposableStep, type Recipe,
  ComposableStep, Recipe, Substitution,
}
import app/types/service.{
  type ServiceReference, ServiceReference, make_service_name,
}
import app/types/service_provider.{SubmitStep}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/string_tree
import serde/argument/value as argument_value
import serde/client/service_reference/encoder as service_reference_encoder

pub fn run_next_step(
  dispatcher: Subject(_),
  service_dictionary: Dict(String, DispatchInfo),
  recipe: Recipe,
  submission: Option(ArgumentSubmission),
) -> Result(Nil, String) {
  // assert that the instance has no errors
  let assert Recipe(_id, _iid, _description, root, None) = recipe

  let dispatch_result =
    dispatch_next_step(
      dispatcher,
      service_dictionary,
      recipe.iid,
      root,
      submission,
    )

  case dispatch_result {
    Ok(Nil) -> Ok(Nil)
    Error(description) ->
      Error(make_dispatch_error(
        recipe.id,
        recipe.iid,
        recipe.description,
        root.arguments,
        submission,
        description,
      ))
  }
}

fn dispatch_next_step(
  dispatcher: Subject(_),
  service_dictionary: Dict(String, DispatchInfo),
  recipe_instance_id: String,
  current_step: ComposableStep,
  submission: Option(ArgumentSubmission),
) -> Result(Nil, String) {
  // Preconditions:
  // when the substitutions are all resolved then we remove the substitutions list
  // therefore the substitutions list is always either None or some non-empty list

  let ComposableStep(_service, _arguments, substitutions:) = current_step

  // find the current step in the recipe using a depth-first descent
  // fully resolved substitutions are removed so find the deepest unsubstituted step
  case substitutions {
    None -> {
      // this is a leaf node, the current (executing) step in the recipe
      wrap_dispatch(
        dispatcher,
        service_dictionary,
        recipe_instance_id,
        current_step,
        submission,
      )
    }

    Some(substitutions_list) -> {
      // this is not a leaf node; drill further
      // assert: the substitutions list must be non-empty (because empty lists are removed)
      let assert Ok(sub) = list.first(substitutions_list)
      let Substitution(_name, step:) = sub

      dispatch_next_step(
        dispatcher,
        service_dictionary,
        recipe_instance_id,
        step,
        submission,
      )
    }
  }
}

fn wrap_dispatch(
  dispatcher: Subject(_),
  service_dictionary: Dict(String, DispatchInfo),
  recipe_instance_id: String,
  current_step: ComposableStep,
  submission: Option(ArgumentSubmission),
) -> Result(Nil, String) {
  // check that client response service matches the service reference of the current step
  use _ <- result.try(check_arguments(current_step, submission))

  let client_update =
    submission |> option.then(fn(submission) { submission.response })

  dispatch_to_service(
    dispatcher,
    service_dictionary,
    recipe_instance_id,
    current_step,
    client_update,
  )
}

fn dispatch_to_service(
  dispatcher: Subject(_),
  service_dictionary: Dict(String, DispatchInfo),
  recipe_instance_id: String,
  step: ComposableStep,
  client_update: Option(Argument),
) -> Result(Nil, String) {
  // echo #("dispatch_to_service: ", service_dictionary, step.service)
  case dict.get(service_dictionary, make_service_name(step.service)) {
    Ok(dispatch_info) -> {
      dispatch_info.process_name
      |> process.named_subject()
      |> process.send(SubmitStep(
        dispatcher,
        recipe_instance_id,
        step,
        client_update,
      ))
      Ok(Nil)
    }

    Error(Nil) ->
      Error(
        "Service not known: " <> service_reference_encoder.encode(step.service),
      )
  }
}

fn make_dispatch_error(
  recipe_id: String,
  recipe_instance_id: String,
  recipe_description: Option(String),
  service_arguments: Option(Arguments),
  submission: Option(ArgumentSubmission),
  description: String,
) -> String {
  let expected_service =
    submission
    |> unwrap_service(defaulting_to: ServiceReference("unknown", "unknown"))

  "Error in recipe (name: "
  <> recipe_id
  <> maybe_quote(recipe_description)
  <> "\n\tinstance: "
  <> recipe_instance_id
  <> "\n\tat service: "
  <> service_reference_encoder.encode(expected_service)
  <> "\n\twith args: "
  <> maybe_add_arguments(service_arguments)
  <> ") : "
  <> description
}

fn maybe_quote(recipe_description: Option(String)) -> String {
  recipe_description
  |> option.map(fn(desc) { "\"" <> desc <> "\"" })
  |> option.unwrap("")
}

fn maybe_add_arguments(arguments: Option(Arguments)) -> String {
  case arguments {
    Some(args) ->
      args
      |> list.map(fn(arg) {
        [
          "(",
          arg.name,
          ": ",
          argument_value.argument_value_to_string(arg.value),
          ")",
        ]
        |> string_tree.from_strings()
        |> string_tree.to_string()
      })
      |> string.join(with: ", ")
    None -> "None"
  }
}

fn check_arguments(
  step: ComposableStep,
  submission: Option(ArgumentSubmission),
) -> Result(Nil, String) {
  let expected_service =
    submission |> unwrap_service(defaulting_to: step.service)

  // the current step should have the same service reference as the client response
  case step.service == expected_service {
    True -> Ok(Nil)
    False ->
      Error(
        "Expecting service ID: "
        <> service_reference_encoder.encode(expected_service)
        <> " but found service ID: "
        <> service_reference_encoder.encode(step.service),
      )
  }
}

fn unwrap_service(
  submission: Option(ArgumentSubmission),
  defaulting_to default: ServiceReference,
) {
  submission
  |> option.then(fn(submission) { Some(submission.service) })
  |> option.unwrap(default)
}
