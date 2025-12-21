import app/types/client_request.{
  type ProviderServiceArgumentName, RequestSpecification,
}
import app/types/definition.{
  type EntityType, BaseTextString, Bytes, RestrictedTextExplicit, TextEntity,
}
import app/types/recipe.{type Arguments}
import app/types/service.{type ServiceReference, ServiceReference}
import app/types/service_call.{
  type ClientRecipeState, type DispatcherReturn, type ServiceReturn,
  DispatcherReturnEndPointError, DispatcherReturnRecipeState,
  DispatcherReturnServiceCall, ServiceReturnRequest, ServiceReturnResult,
  ServiceState,
}
import gleam/option.{type Option, None, Some}

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub const sqrt_service_reference = ServiceReference(
  name: "sqrt",
  path: "com.examples.service_composer",
)

pub fn make_request(
  recipe_instance_id: String,
  service_reference: ServiceReference,
  request: EntityType,
  name: ProviderServiceArgumentName,
  required: Bool,
  prompt: String,
  known_arguments: Arguments,
) -> DispatcherReturn {
  make_dispatcher_return_service_call(
    recipe_instance_id,
    service_reference,
    known_arguments,
    ServiceReturnRequest(RequestSpecification(request, name, required, prompt)),
    None,
  )
}

pub fn make_result(
  recipe_instance_id: String,
  service_reference: ServiceReference,
  known_arguments: Arguments,
  result: String,
  warning: Option(String),
) -> DispatcherReturn {
  make_dispatcher_return_service_call(
    recipe_instance_id,
    service_reference,
    known_arguments,
    ServiceReturnResult(result),
    warning,
  )
}

fn make_dispatcher_return_service_call(
  recipe_instance_id: String,
  service_reference: ServiceReference,
  known_arguments: Arguments,
  service_return: ServiceReturn,
  warning: Option(String),
) -> DispatcherReturn {
  DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service: service_reference,
      service_state: make_service_state(known_arguments),
      service_return:,
      warning:,
    ),
  )
}

//******************************************************************
// Service-specific utility functions
//******************************************************************

pub fn calc_request_operator(
  recipe_instance_id: String,
  known_arguments: Arguments,
) -> DispatcherReturn {
  let entity =
    Bytes(TextEntity(
      base: BaseTextString,
      specialization: Some(RestrictedTextExplicit(["+", "-", "*", "/"])),
    ))

  make_request(
    recipe_instance_id,
    calc_service_reference,
    entity,
    "operator",
    True,
    // calc.operator_prompt,
    "Provide a calculation operator (one of: +, -, * or /)",
    known_arguments,
  )
}

pub fn calc_request_operand(
  recipe_instance_id: String,
  name: ProviderServiceArgumentName,
  entity_type: EntityType,
  known_arguments: Arguments,
) -> DispatcherReturn {
  make_request(
    recipe_instance_id,
    calc_service_reference,
    entity_type,
    name,
    True,
    // calc.operand_prompt,
    "Provide a calculation operand",
    known_arguments,
  )
}

pub fn sqrt_request_operand(
  recipe_instance_id: String,
  name: ProviderServiceArgumentName,
  entity_type: EntityType,
  known_arguments: Arguments,
) -> DispatcherReturn {
  make_request(
    recipe_instance_id,
    sqrt_service_reference,
    entity_type,
    name,
    True,
    // sqrt.argument_prompt,
    "Provide the function argument",
    known_arguments,
  )
}

pub fn calc_return_result(
  recipe_instance_id: String,
  result: String,
  warning: Option(String),
  known_arguments: Arguments,
) -> DispatcherReturn {
  make_result(
    recipe_instance_id,
    calc_service_reference,
    known_arguments,
    result,
    warning,
  )
}

pub fn calc_recipe_state_update(
  recipe_instance_id: String,
  recipe_state: ClientRecipeState,
) -> DispatcherReturn {
  DispatcherReturnRecipeState(recipe_instance_id, recipe_state)
}

pub fn calc_end_point_error(recipe_instance_id: String) -> DispatcherReturn {
  DispatcherReturnEndPointError(
    recipe_instance_id:,
    service: calc_service_reference,
    description: "Some error",
    client_data: None,
  )
}

fn make_service_state(known_arguments: Arguments) -> Option(Arguments) {
  case known_arguments {
    [] -> None
    _ -> Some(known_arguments)
  }
}
