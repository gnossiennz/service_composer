import app/types/recipe.{
  type Argument, type ArgumentValue, type Arguments, Argument,
}
import app/types/service.{type ServiceReference}
import app/types/service_call.{
  type DispatcherReturn, type ServiceReturn, DispatcherReturnServiceCall,
  ServiceState,
}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type InternalState(args) {
  InternalState(arguments: args, warning: Option(String))
}

pub fn make_argument(
  operand: Option(ArgumentValue),
  name: String,
) -> Option(Argument) {
  case operand {
    Some(value) -> Some(Argument(name:, value:))
    None -> None
  }
}

pub fn update_state(
  existing: Arguments,
  maybe_update: Option(Argument),
  mapper: fn(Arguments) -> InternalState(a),
) -> InternalState(a) {
  // The service provider determines the ordering of arguments
  // by requesting arguments in a specified order
  // The caller is assumed to have NOT modified operand order

  // The update (if any) goes at the end of the list
  // The mapper will update earlier named args with later args of the same name
  case maybe_update {
    Some(update) -> existing |> list.append([update]) |> mapper()
    None -> mapper(existing)
  }
}

pub fn get_service_response(
  state: InternalState(args),
  recipe_instance_id: String,
  service: ServiceReference,
  resolver: fn(args) -> ServiceReturn,
  argument_mapper: fn(args) -> Option(Arguments),
) -> DispatcherReturn {
  // return either a request for the next argument or the result
  let service_return = resolver(state.arguments)

  DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state: state.arguments |> argument_mapper(),
      service_return:,
      warning: state.warning,
    ),
  )
}
