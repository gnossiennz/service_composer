//// A service provider that performs simple arithmetic
//// It takes the following arguments: operator, operand1, operand2
//// See the sqrt service provider for an even simpler example

import app/types/client_request.{RequestSpecification}
import app/types/definition.{
  type ServiceInfo, ArgumentTypeInfo, BaseNumberFloat, BaseNumberIntOrFloat,
  BaseTextString, Bytes, NumberEntity, RestrictedTextExplicit, Scalar,
  ServiceInfo, ServiceReturnType, ServiceReturnTypePassByValue, TextEntity,
}
import app/types/recipe.{
  type Argument, type ArgumentValue, type Arguments, Argument, FloatValue,
  SerializedValue,
}
import app/types/service.{
  type ServiceDescription, ServiceDescription, ServiceReference,
}
import app/types/service_call.{
  type DispatcherReturn, type ServiceReturn, ServiceReturnRequest,
  ServiceReturnResult,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree
import service_providers/shared.{type InternalState, InternalState}

pub type Operator {
  Add
  Subtract
  Multiply
  Divide
}

pub type OperandName {
  Operand1
  Operand2
}

// Subtract and Divide operators are order-dependant so a well-defined order is maintained
pub type InternalArguments {
  InternalArguments(
    operator: Option(Operator),
    operand1: Option(ArgumentValue),
    operand2: Option(ArgumentValue),
  )
}

pub const operator_prompt = "Provide a calculation operator (one of: +, -, * or /)"

pub const operand_prompt = "Provide a calculation operand"

/// Get the service description
pub fn get_service_desc() -> ServiceDescription {
  ServiceDescription(
    reference: ServiceReference(
      name: "calc",
      path: "com.examples.service_composer",
    ),
    description: "Simple calculation service example",
  )
}

/// Get the argument types and the return type of the resolver function
pub fn get_type_info() -> ServiceInfo {
  // This service accepts numbers (int or float) for its operand arguments
  // and returns a float number type
  ServiceInfo(
    arguments: [
      ArgumentTypeInfo(
        argument_name: "operator",
        type_info: Bytes(TextEntity(
          base: BaseTextString,
          specialization: Some(RestrictedTextExplicit(["+", "-", "*", "/"])),
        )),
      ),
      ArgumentTypeInfo(
        argument_name: "operand1",
        type_info: Scalar(NumberEntity(
          base: BaseNumberIntOrFloat,
          specialization: None,
        )),
      ),
      ArgumentTypeInfo(
        argument_name: "operand2",
        type_info: Scalar(NumberEntity(
          base: BaseNumberIntOrFloat,
          specialization: None,
        )),
      ),
    ],
    returns: ServiceReturnType(
      type_info: Scalar(NumberEntity(
        base: BaseNumberFloat,
        specialization: None,
      )),
      passing_convention: ServiceReturnTypePassByValue,
    ),
  )
}

/// Resolve the service call
/// client_update: the UI response for the currently specified request e.g. "operator"
/// argument_state: the accumulated state of the service call (required arguments)
pub fn resolve(
  recipe_instance_id: String,
  client_update: Option(Argument),
  argument_state: Arguments,
) -> DispatcherReturn {
  // the argument state is held externally to the service provider
  // for convenience, the external state for THIS service
  // is converted to an internal state on each call
  // the internal state will initally be unset and
  // is opaque to any code outside of this calculation service
  // including for example any web service handlers and the UI

  // If an argument update is provided then update the state
  // Each argument is either an operator or an operand (two operands are expected)
  // Once the state has all of the required values then calculate a result
  argument_state
  |> shared.update_state(client_update, map_existing_arguments)
  |> shared.get_service_response(
    recipe_instance_id,
    get_service_desc().reference,
    resolver,
    internal_arguments_to_external,
  )
}

/// Convert external state to an internal form
pub fn map_existing_arguments(
  existing: Arguments,
) -> InternalState(InternalArguments) {
  existing
  |> list.fold(
    InternalState(InternalArguments(None, None, None), None),
    fn(acc, argument) {
      // these are the expected argument names
      // any errors with argument conversion generate a warning only
      case argument {
        Argument(name: "operator", value: _) as arg -> update_operator(acc, arg)
        Argument(name: "operand1", value: _) as arg ->
          update_operand(Operand1, acc, arg)
        Argument(name: "operand2", value: _) as arg ->
          update_operand(Operand2, acc, arg)
        Argument(name: _, value: _) as arg ->
          InternalState(
            acc.arguments,
            Some("Unexpected argument name: " <> arg.name),
          )
      }
    },
  )
}

fn update_operator(
  state: InternalState(InternalArguments),
  argument: Argument,
) -> InternalState(InternalArguments) {
  case parse_operator(argument.value) {
    Ok(operator) ->
      InternalState(
        InternalArguments(..state.arguments, operator: Some(operator)),
        None,
      )
    Error(description) ->
      InternalState(
        state.arguments,
        [
          "Argument is not of the expected type: ",
          argument.name,
          "(",
          description,
          ")",
        ]
          |> string_tree.from_strings()
          |> string_tree.to_string()
          |> Some(),
      )
  }
}

fn update_operand(
  which: OperandName,
  state: InternalState(InternalArguments),
  argument: Argument,
) -> InternalState(InternalArguments) {
  case parse_operand(argument.value) {
    Ok(operand) -> {
      InternalState(set_operand_value(which, operand, state.arguments), None)
    }
    Error(_err) ->
      InternalState(
        state.arguments,
        Some("Argument is not of the expected type: " <> argument.name),
      )
  }
}

fn set_operand_value(
  which: OperandName,
  value: ArgumentValue,
  existing: InternalArguments,
) {
  case which {
    Operand1 -> InternalArguments(..existing, operand1: Some(value))
    Operand2 -> InternalArguments(..existing, operand2: Some(value))
  }
}

fn parse_operator(value: ArgumentValue) -> Result(Operator, String) {
  // an operator is represented as SerializedValue externally and Operator internally
  case value {
    SerializedValue(string_value) -> {
      case string_value {
        "+" -> Ok(Add)
        "-" -> Ok(Subtract)
        "*" -> Ok(Multiply)
        "/" -> Ok(Divide)
        _ -> Error("Unknown operator: " <> string_value)
      }
    }
    _ -> Error("Unexpected operator representation")
  }
}

fn parse_operand(value: ArgumentValue) -> Result(ArgumentValue, String) {
  // an operand is represented as SerializedValue or FloatValue externally
  // and FloatValue internally
  case value {
    SerializedValue(string_value) ->
      parse_as_int_operand(string_value)
      |> result.try_recover(fn(v) { parse_as_float_operand(v) })
    FloatValue(_) as float_value -> Ok(float_value)
    _ -> Error("Unexpected operator representation")
  }
}

fn parse_as_int_operand(value: String) -> Result(ArgumentValue, String) {
  case int.parse(value) {
    Ok(i) -> Ok(FloatValue(int.to_float(i)))
    Error(_) -> Error(value)
  }
}

fn parse_as_float_operand(value: String) -> Result(ArgumentValue, String) {
  case float.parse(value) {
    Ok(f) -> Ok(FloatValue(f))
    Error(_) -> Error(value)
  }
}

/// Take the internal state and generate a request or a result
pub fn resolver(arguments) {
  case arguments {
    InternalArguments(
      operator: Some(operator),
      operand1: Some(operand1),
      operand2: Some(operand2),
    ) -> calculate_with(operator, operand1, operand2)
    InternalArguments(operator: None, operand1: _, operand2: _) ->
      request_operator()
    InternalArguments(operator: Some(_), operand1: None, operand2: _) ->
      request_operand("operand1")
    InternalArguments(operator: Some(_), operand1: Some(_), operand2: None) ->
      request_operand("operand2")
  }
}

fn calculate_with(
  operator: Operator,
  operand1: ArgumentValue,
  operand2: ArgumentValue,
) -> ServiceReturn {
  // at this point the argument representation should be FloatValue
  let assert FloatValue(op1) = operand1
  let assert FloatValue(op2) = operand2

  let result = case operator {
    Add -> op1 +. op2
    Subtract -> op1 -. op2
    Multiply -> op1 *. op2
    Divide -> op1 /. op2
  }

  ServiceReturnResult(result: float.to_string(result))
}

pub fn internal_arguments_to_external(
  arguments: InternalArguments,
) -> Option(Arguments) {
  let InternalArguments(operator:, operand1:, operand2:) = arguments

  // maintain a strict ordering: operator, operand1, operand2
  [
    operator |> operator_to_argument_value() |> shared.make_argument("operator"),
    operand1 |> shared.make_argument("operand1"),
    operand2 |> shared.make_argument("operand2"),
  ]
  |> list.filter_map(fn(arg) { option.to_result(arg, "") })
  |> empty_to_none()
}

fn empty_to_none(args: Arguments) -> Option(Arguments) {
  case args {
    [] -> None
    _ -> Some(args)
  }
}

fn operator_to_argument_value(
  operator: Option(Operator),
) -> Option(ArgumentValue) {
  option.map(operator, fn(op) {
    case op {
      Add -> SerializedValue("+")
      Subtract -> SerializedValue("-")
      Multiply -> SerializedValue("*")
      Divide -> SerializedValue("/")
    }
  })
}

fn request_operator() -> ServiceReturn {
  // request a single operator value from the range: +, -, *, /
  let request =
    RequestSpecification(
      request: definition.restricted_string(["+", "-", "*", "/"]),
      name: "operator",
      required: True,
      prompt: operator_prompt,
    )

  ServiceReturnRequest(request: request)
}

fn request_operand(name: String) -> ServiceReturn {
  // request the operands from the range: postive number
  let request =
    RequestSpecification(
      request: definition.any_number(),
      name:,
      required: True,
      prompt: operand_prompt,
    )

  ServiceReturnRequest(request: request)
}
