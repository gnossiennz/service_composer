//// Test the sqrt function service

import app/types/recipe.{
  type Argument, type Arguments, Argument, FloatValue, SerializedValue,
  StringValue,
}
import app/types/service.{type ServiceReference}
import app/types/service_call.{
  DispatcherReturnServiceCall, ServiceReturnResult, ServiceState,
}
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import service_providers/shared.{type InternalState, InternalState}
import service_providers/sqrt

pub fn main() {
  gleeunit.main()
}

// ###############################################
// State update tests
// ###############################################

pub fn update_state_with_argument_test() {
  // arg representation is SerializedValue or FloatValue
  let as_incorrect_repr = Argument(name: "arg", value: StringValue("16"))
  let as_incorrect_serialized_repr =
    Argument(name: "arg", value: SerializedValue("XX"))
  let as_serialized = Argument(name: "arg", value: SerializedValue("16"))
  let as_serialized_negative =
    Argument(name: "arg", value: SerializedValue("-1"))
  let as_float = Argument(name: "arg", value: FloatValue(81.0))
  let as_float_other = Argument(name: "arg", value: FloatValue(36.0))
  let as_float_negative = Argument(name: "arg", value: FloatValue(-1.0))

  // an unexpected representation generates an error
  update_state([], Some(as_incorrect_repr))
  |> should.equal(InternalState(
    None,
    Some("Unexpected argument name or representation: arg"),
  ))

  // an unexpected serialized representation generates an error
  update_state([], Some(as_incorrect_serialized_repr))
  |> should.equal(InternalState(
    None,
    Some("Argument is not of the expected type"),
  ))

  // a negative value is not accepted
  update_state([], Some(as_float_negative))
  |> should.equal(InternalState(None, Some("Argument must be a positive value")))

  // a negative serialized value is not accepted
  update_state([], Some(as_serialized_negative))
  |> should.equal(InternalState(None, Some("Argument must be a positive value")))

  // can add a serialized argument
  update_state([], Some(as_serialized))
  |> should.equal(InternalState(arguments: Some(16.0), warning: None))

  // can add a float representation argument
  update_state([], Some(as_float))
  |> should.equal(InternalState(arguments: Some(81.0), warning: None))

  // can change the argument
  update_state([as_float], Some(as_float_other))
  |> should.equal(InternalState(arguments: Some(36.0), warning: None))
}

pub fn get_next_state_test() {
  let recipe_instance_id = "1234"
  let service = sqrt.get_service_desc().reference
  let arguments = Some(81.0)
  let state = InternalState(arguments, None)

  get_service_response(service, state, recipe_instance_id)
  |> should.equal(DispatcherReturnServiceCall(
    recipe_instance_id,
    service_state: ServiceState(
      service: sqrt.get_service_desc().reference,
      service_state: Some([Argument(name: "arg", value: FloatValue(81.0))]),
      service_return: ServiceReturnResult(result: "9.0"),
      warning: None,
    ),
  ))
}

fn update_state(
  existing: Arguments,
  maybe_update: Option(Argument),
) -> InternalState(Option(Float)) {
  // call the update_state function with the mapper from the sqrt module
  existing |> shared.update_state(maybe_update, sqrt.map_existing_arguments)
}

fn get_service_response(
  service: ServiceReference,
  state: InternalState(Option(Float)),
  recipe_instance_id: String,
) {
  // call the get_service_response function
  // with the resolver and argument_mapper from the sqrt module
  shared.get_service_response(
    state,
    recipe_instance_id,
    service,
    sqrt.resolver,
    sqrt.argument_to_external,
  )
}
