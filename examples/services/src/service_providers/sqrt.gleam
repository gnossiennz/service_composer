//// A service provider that performs just one mathematical function: square root
//// See the calc service provider example for a service that has multiple arguments

import app/types/client_request.{RequestSpecification}
import app/types/definition.{
  type ServiceInfo, ArgumentTypeInfo, BaseNumberFloat, BaseNumberIntOrFloat,
  NumberEntity, NumberRangePositive, RestrictedNumberNamed, Scalar, ServiceInfo,
  ServiceReturnType, ServiceReturnTypePassByValue,
}
import app/types/recipe.{
  type Argument, type Arguments, Argument, FloatValue, SerializedValue,
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
import service_providers/shared.{type InternalState, InternalState}

pub const argument_prompt = "Provide the function argument"

/// Get the service description
pub fn get_service_desc() -> ServiceDescription {
  ServiceDescription(
    reference: ServiceReference(
      name: "sqrt",
      path: "com.examples.service_composer",
    ),
    description: "Square root service example",
  )
}

/// Get the argument types and the return type of the resolver function
pub fn get_type_info() -> ServiceInfo {
  // This service accepts a positive number (int or float) for its single argument
  // and returns a positive float number type
  ServiceInfo(
    arguments: [
      ArgumentTypeInfo(
        argument_name: "arg",
        type_info: Scalar(NumberEntity(
          base: BaseNumberIntOrFloat,
          specialization: Some(RestrictedNumberNamed(NumberRangePositive)),
        )),
      ),
    ],
    returns: ServiceReturnType(
      type_info: Scalar(NumberEntity(
        base: BaseNumberFloat,
        specialization: Some(RestrictedNumberNamed(NumberRangePositive)),
      )),
      passing_convention: ServiceReturnTypePassByValue,
    ),
  )
}

/// Resolve the service call
/// client_update: the UI response for the currently specified request e.g. "arg"
/// argument_state: the accumulated state of the service call (required arguments)
pub fn resolve(
  recipe_instance_id: String,
  client_update: Option(Argument),
  argument_state: Arguments,
) -> DispatcherReturn {
  argument_state
  |> shared.update_state(client_update, map_existing_arguments)
  |> shared.get_service_response(
    recipe_instance_id,
    get_service_desc().reference,
    resolver,
    argument_to_external,
  )
}

/// Take the internal state and generate a request or a result
pub fn resolver(argument) {
  case argument {
    Some(arg) -> calculate_with(arg)
    None -> request_argument()
  }
}

/// Convert external state to an internal form
pub fn map_existing_arguments(
  existing: Arguments,
) -> InternalState(Option(Float)) {
  // given a list of arguments, select the last valid argument
  // select the last because the argument must be updateable
  // i.e. any later valid argument replaces the existing argument
  existing
  |> list.fold(InternalState(None, None), fn(acc, argument) {
    // an argument is represented as SerializedValue or FloatValue externally
    // it is always represented as a Float internally
    // any error with argument conversion generates a warning only
    // and any existing valid arguments are retained
    case argument {
      Argument(name: "arg", value: SerializedValue(string_value)) ->
        parse_and_maybe_update_state(acc, string_value)
      Argument(name: "arg", value: FloatValue(float_value)) ->
        check_and_maybe_update_state(acc, float_value)
      Argument(name: _, value: _) as arg ->
        InternalState(
          arguments: acc.arguments,
          warning: Some(
            "Unexpected argument name or representation: " <> arg.name,
          ),
        )
    }
  })
}

fn check_and_maybe_update_state(
  state: InternalState(Option(Float)),
  value: Float,
) -> InternalState(Option(Float)) {
  case value >=. 0.0 {
    True -> InternalState(arguments: Some(value), warning: None)
    False ->
      InternalState(
        arguments: state.arguments,
        warning: Some("Argument must be a positive value"),
      )
  }
}

fn parse_and_maybe_update_state(
  state: InternalState(Option(Float)),
  value: String,
) -> InternalState(Option(Float)) {
  case parse_argument(value) {
    Ok(float_value) if float_value >=. 0.0 ->
      InternalState(arguments: Some(float_value), warning: None)
    Ok(_float_value) ->
      InternalState(
        arguments: state.arguments,
        warning: Some("Argument must be a positive value"),
      )
    Error(Nil) ->
      InternalState(
        arguments: state.arguments,
        warning: Some("Argument is not of the expected type"),
      )
  }
}

fn parse_argument(value: String) -> Result(Float, Nil) {
  use _ <- result.try_recover(float.parse(value))
  use i <- result.try(int.parse(value))

  i |> int.to_float() |> Ok()
}

fn calculate_with(argument: Float) -> ServiceReturn {
  // the argument should be a positive float at this point
  let assert Ok(result) = float.square_root(argument)

  ServiceReturnResult(result: float.to_string(result))
}

fn request_argument() -> ServiceReturn {
  // request an argument from the range: postive integer
  let request =
    RequestSpecification(
      request: definition.positive_number(),
      name: "arg",
      required: True,
      prompt: argument_prompt,
    )

  ServiceReturnRequest(request: request)
}

pub fn argument_to_external(argument_value: Option(Float)) -> Option(Arguments) {
  argument_value
  |> option.map(fn(f) { FloatValue(f) })
  |> shared.make_argument("arg")
  |> option.map(fn(arg) { list.wrap(arg) })
}
