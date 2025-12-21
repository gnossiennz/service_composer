//// Test the calculation service

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
import service_providers/calc.{
  Add, Divide, InternalArguments, Multiply, Subtract,
}
import service_providers/shared.{type InternalState, InternalState}

pub fn main() {
  gleeunit.main()
}

// ###############################################
// State update tests
// ###############################################

pub fn update_state_with_operator_test() {
  let add = Argument(name: "operator", value: SerializedValue("+"))
  let subtract = Argument(name: "operator", value: SerializedValue("-"))
  let multiply = Argument(name: "operator", value: SerializedValue("*"))
  let divide = Argument(name: "operator", value: SerializedValue("/"))
  let operand1 = Argument(name: "operand1", value: SerializedValue("33"))
  let add_incorrect_repr = Argument(name: "operator", value: StringValue("+"))
  let op_unknown = Argument(name: "operator", value: SerializedValue("~"))

  // operator representation is SerializedValue
  update_state([], Some(add_incorrect_repr))
  |> should.equal(InternalState(
    InternalArguments(None, None, None),
    Some(
      "Argument is not of the expected type: operator(Unexpected operator representation)",
    ),
  ))

  // an unknown operator cannot change the internal state (but generates a warning)
  update_state([], Some(op_unknown))
  |> should.equal(InternalState(
    InternalArguments(None, None, None),
    Some("Argument is not of the expected type: operator(Unknown operator: ~)"),
  ))

  // can add plus operator
  update_state([], Some(add))
  |> should.equal(InternalState(InternalArguments(Some(Add), None, None), None))

  // can add subtract operator
  update_state([], Some(subtract))
  |> should.equal(InternalState(
    InternalArguments(Some(Subtract), None, None),
    None,
  ))

  // can add multiply operator
  update_state([], Some(multiply))
  |> should.equal(InternalState(
    InternalArguments(Some(Multiply), None, None),
    None,
  ))

  // can add divide operator
  update_state([], Some(divide))
  |> should.equal(InternalState(
    InternalArguments(Some(Divide), None, None),
    None,
  ))

  // can change operator from subtract to add
  update_state([subtract], Some(add))
  |> should.equal(InternalState(InternalArguments(Some(Add), None, None), None))

  // can change operator from add to subtract
  update_state([add], Some(subtract))
  |> should.equal(InternalState(
    InternalArguments(Some(Subtract), None, None),
    None,
  ))

  // existing arguments are unaffected by operator change
  update_state([add, operand1], Some(subtract))
  |> should.equal(InternalState(
    InternalArguments(Some(Subtract), Some(FloatValue(33.0)), None),
    None,
  ))
}

pub fn update_state_with_operand_test() {
  let add = Argument(name: "operator", value: SerializedValue("+"))
  let operand1 = Argument(name: "operand1", value: SerializedValue("33"))
  let operand2 = Argument(name: "operand2", value: SerializedValue("44"))
  let operand3 = Argument(name: "operand3", value: SerializedValue("55"))
  let operand1_with_new_value =
    Argument(name: "operand1", value: SerializedValue("66"))
  let operand1_incorrect_repr =
    Argument(name: "operand1", value: StringValue("33"))
  let operand1_as_float = Argument(name: "operand1", value: FloatValue(33.0))
  let operand1_as_serialized_float =
    Argument(name: "operand1", value: SerializedValue("-33.0"))
  let operand1_unparseable =
    Argument(name: "operand1", value: SerializedValue("x33.0"))

  // operand representation is SerializedValue or FloatValue
  update_state([], Some(operand1_incorrect_repr))
  |> should.equal(InternalState(
    InternalArguments(None, None, None),
    Some("Argument is not of the expected type: operand1"),
  ))

  // SerializedValue must be parseable as an int or float
  update_state([], Some(operand1_unparseable))
  |> should.equal(InternalState(
    InternalArguments(None, None, None),
    Some("Argument is not of the expected type: operand1"),
  ))

  // can add a SerializedValue integer operand
  update_state([], Some(operand1))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(33.0)), None),
    None,
  ))

  // can add a SerializedValue float operand
  update_state([], Some(operand1_as_serialized_float))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(-33.0)), None),
    None,
  ))

  // can add a FloatValue operand
  update_state([], Some(operand1_as_float))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(33.0)), None),
    None,
  ))

  // can add a second operand
  update_state([operand1], Some(operand2))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(33.0)), Some(FloatValue(44.0))),
    None,
  ))

  // updating the first operand updates the internal state
  update_state([operand1, operand2], Some(operand1_with_new_value))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(66.0)), Some(FloatValue(44.0))),
    None,
  ))

  // adding a third operand has no affect (but adds a warning)
  update_state([operand1, operand2], Some(operand3))
  |> should.equal(InternalState(
    InternalArguments(None, Some(FloatValue(33.0)), Some(FloatValue(44.0))),
    Some("Unexpected argument name: operand3"),
  ))

  // an existing operator argument is not affected
  update_state([add], Some(operand1))
  |> should.equal(InternalState(
    InternalArguments(Some(Add), Some(FloatValue(33.0)), None),
    None,
  ))
}

pub fn get_next_state_test() {
  let recipe_instance_id = "1234"
  let service = calc.get_service_desc().reference
  let arguments =
    InternalArguments(
      operator: Some(Add),
      operand1: Some(FloatValue(44.4)),
      operand2: Some(FloatValue(33.0)),
    )
  let state = InternalState(arguments, None)

  get_service_response(service, state, recipe_instance_id)
  |> should.equal(DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state: Some([
        Argument(name: "operator", value: SerializedValue("+")),
        Argument(name: "operand1", value: FloatValue(44.4)),
        Argument(name: "operand2", value: FloatValue(33.0)),
      ]),
      service_return: ServiceReturnResult(result: "77.4"),
      warning: None,
    ),
  ))
}

fn update_state(
  existing: Arguments,
  maybe_update: Option(Argument),
) -> InternalState(calc.InternalArguments) {
  // call the update_state function with the mapper from the calc module
  existing |> shared.update_state(maybe_update, calc.map_existing_arguments)
}

fn get_service_response(
  service: ServiceReference,
  state: InternalState(calc.InternalArguments),
  recipe_instance_id: String,
) {
  // call the get_service_response function
  // with the resolver and argument_mapper from the calc module
  shared.get_service_response(
    state,
    recipe_instance_id,
    service,
    calc.resolver,
    calc.internal_arguments_to_external,
  )
}
