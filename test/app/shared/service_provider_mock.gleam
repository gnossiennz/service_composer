//// A mocked resolver function that performs simple calculations
//// This uses pattern matching to cover only the tested cases
//// A better calculator implementation (calc) can be found in examples/service_providers

import app/shared/service_call.{
  calc_end_point_error, calc_request_operand, calc_request_operator,
  calc_return_result,
} as _
import app/types/definition
import app/types/recipe.{
  type Argument, type ArgumentValue, type Arguments, Argument, FloatValue,
  SerializedValue,
}
import app/types/service_call.{type DispatcherReturn}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

type Operator {
  Add
  Subtract
  Multiply
  Divide
}

type InternalState {
  InternalState(arguments: InternalArguments, warning: Option(String))
}

type InternalArguments {
  InternalArguments(
    operator: Option(Operator),
    operand1: Option(ArgumentValue),
    operand2: Option(ArgumentValue),
  )
}

//******************************************************************
// Mock service provider function: resolve
//******************************************************************

pub fn resolve(
  recipe_instance_id: String,
  client_update: Option(Argument),
  argument_state: Arguments,
) -> DispatcherReturn {
  case client_update {
    Some(update) ->
      argument_state |> list.append([update]) |> process(recipe_instance_id)
    None -> process(argument_state, recipe_instance_id)
  }
  |> option.lazy_unwrap(fn() { calc_end_point_error(recipe_instance_id) })
}

fn process(
  args: Arguments,
  recipe_instance_id: String,
) -> Option(DispatcherReturn) {
  // match the provided arguments but only cover the tested cases
  // test cases include operand re-ordering and an unnecessary extra argument
  case args {
    [] -> request_operator(recipe_instance_id)
    [Argument(name: "operator", value: _)] ->
      request_operand(recipe_instance_id, "operand1", args)
    [Argument(name: "operator", value: _), Argument(name: "operand1", value: _)] ->
      request_operand(recipe_instance_id, "operand2", args)
    [
      Argument(name: "operator", value: _) as operator,
      Argument(name: "operand1", value: _) as op1,
      Argument(name: "operand2", value: _) as op2,
    ] ->
      make_state(Some(operator), Some(op1), Some(op2), None)
      |> calculate_with(recipe_instance_id, args)
    [
      Argument(name: "operator", value: _) as operator,
      Argument(name: "operand2", value: _) as op2,
      Argument(name: "operand1", value: _) as op1,
    ] ->
      make_state(Some(operator), Some(op1), Some(op2), None)
      |> calculate_with(recipe_instance_id, args)
    [
      Argument(name: "operator", value: _) as operator,
      Argument(name: "operand1", value: _) as op1,
      Argument(name: "operand2", value: _) as op2,
      Argument(name: "operand3", value: _),
    ] ->
      make_state(
        Some(operator),
        Some(op1),
        Some(op2),
        Some("Unexpected argument name: operand3"),
      )
      |> calculate_with(recipe_instance_id, args)
    _ -> None
  }
}

fn make_state(
  operator: Option(Argument),
  operand1: Option(Argument),
  operand2: Option(Argument),
  warning: Option(String),
) -> InternalState {
  let operator = operator |> parse_operator() |> option.from_result()

  // retrieve the internal argument value and maybe convert to FloatValue
  let operand1 =
    operand1 |> option.map(fn(op) { op.value }) |> maybe_convert_to_float()
  let operand2 =
    operand2 |> option.map(fn(op) { op.value }) |> maybe_convert_to_float()

  InternalState(
    InternalArguments(
      operator: operator,
      operand1: operand1,
      operand2: operand2,
    ),
    warning,
  )
}

fn maybe_convert_to_float(value: Option(ArgumentValue)) -> Option(ArgumentValue) {
  // convert SerializedValue arguments to FloatValue arguments
  value
  |> option.map(fn(arg_value) {
    case arg_value {
      SerializedValue(value) -> {
        let assert Ok(converted) = parse_operand(value)
        converted
      }
      _ -> arg_value
    }
  })
}

fn parse_operand(value: String) -> Result(ArgumentValue, String) {
  case int.parse(value) {
    Ok(i) -> Ok(FloatValue(int.to_float(i)))
    Error(_) ->
      case float.parse(value) {
        Ok(f) -> Ok(FloatValue(f))
        Error(_) -> Error(value)
      }
  }
}

fn parse_operator(operator_arg: Option(Argument)) -> Result(Operator, String) {
  use arg <- result.try(operator_arg |> option.to_result("No operator"))
  let assert SerializedValue(string_value) = arg.value

  case string_value {
    "+" -> Ok(Add)
    "-" -> Ok(Subtract)
    "*" -> Ok(Multiply)
    "/" -> Ok(Divide)
    _ -> Error("Unknown operator: " <> string_value)
  }
}

fn calculate_with(
  state: InternalState,
  recipe_instance_id: String,
  original_arguments: Arguments,
) -> Option(DispatcherReturn) {
  let InternalState(
    arguments: InternalArguments(operator:, operand1:, operand2:),
    warning: _,
  ) = state
  let assert Some(operator) = operator
  let assert Some(FloatValue(operand1)) = operand1
  let assert Some(FloatValue(operand2)) = operand2

  let make_result = make_result(
    _,
    recipe_instance_id,
    state,
    original_arguments,
  )

  // only include the tested cases
  case operator, operand1, operand2 {
    Add, 3.0, 4.0 -> make_result(7.0)
    Subtract, 3.0, 4.0 -> make_result(-1.0)
    Subtract, 4.0, 3.0 -> make_result(1.0)
    Divide, 2.0, 4.0 -> make_result(0.5)
    Divide, 4.0, 2.0 -> make_result(2.0)
    Add, 33.0, 44.0 -> make_result(77.0)
    Add, 33.0, 55.0 -> make_result(88.0)
    _, _, _ -> None
  }
}

fn make_result(
  result: Float,
  recipe_instance_id: String,
  state: InternalState,
  original_arguments: Arguments,
) -> Option(DispatcherReturn) {
  calc_return_result(
    recipe_instance_id,
    float.to_string(result),
    state.warning,
    internal_arguments_to_external(original_arguments, state.arguments),
  )
  |> Some
}

fn internal_arguments_to_external(
  original_arguments: Arguments,
  arguments: InternalArguments,
) -> Arguments {
  let assert Ok(operator) =
    original_arguments
    |> list.filter(fn(arg) { arg.name == "operator" })
    |> list.first()

  let InternalArguments(operator: _, operand1:, operand2:) = arguments
  let assert Some(operand1) =
    operand1 |> option.map(fn(value) { Argument(name: "operand1", value:) })
  let assert Some(operand2) =
    operand2 |> option.map(fn(value) { Argument(name: "operand2", value:) })

  [operator, operand1, operand2]
}

fn request_operator(recipe_instance_id: String) -> Option(DispatcherReturn) {
  calc_request_operator(recipe_instance_id, []) |> Some
}

fn request_operand(
  recipe_instance_id: String,
  name: String,
  original_arguments: Arguments,
) -> Option(DispatcherReturn) {
  calc_request_operand(
    recipe_instance_id,
    name,
    definition.positive_number(),
    original_arguments,
  )
  |> Some
}
