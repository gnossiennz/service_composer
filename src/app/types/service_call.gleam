//// Response types from a call to a service provider

import app/types/client_request.{type RequestSpecification}
import app/types/recipe.{
  type Argument, type Arguments, type RecipeID, type RecipeInstanceID,
}
import app/types/service.{type ServiceReference}
import gleam/option.{type Option}

pub type ServiceCallResponse {
  ServiceCallResponse(
    recipe_id: RecipeID,
    recipe_desc: String,
    dispatcher_return: DispatcherReturn,
  )
}

/// The return values from the dispatcher
pub type DispatcherReturn {
  // Return value from a call to a service provider
  DispatcherReturnServiceCall(
    recipe_instance_id: RecipeInstanceID,
    service_state: ServiceState,
  )
  // Return value from a recipe state request
  DispatcherReturnRecipeState(
    recipe_instance_id: RecipeInstanceID,
    recipe_state: ClientRecipeState,
  )
  // Return value from a misdirected service reference
  DispatcherReturnEndPointError(
    recipe_instance_id: RecipeInstanceID,
    service: ServiceReference,
    description: String,
    client_data: Option(Argument),
  )
  // Return value from a mangled client response
  DispatcherReturnHydrationError(
    recipe_instance_id: RecipeInstanceID,
    error_type: HydrationError,
    description: String,
    client_data: String,
  )
}

/// The state returned from a service provider
pub type ServiceState {
  ServiceState(
    service: ServiceReference,
    service_state: Option(Arguments),
    service_return: ServiceReturn,
    warning: Option(String),
  )
}

/// The return values from a service provider
pub type ServiceReturn {
  ServiceReturnResult(result: String)
  ServiceReturnRequest(request: RequestSpecification)
}

pub type HydrationError {
  // StateHydrationError
  ClientResponseHydrationError
}

pub type ClientRecipeState {
  Pending
  Requesting
  Stepping
  Completing
  Suspending
}
