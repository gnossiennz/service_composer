import app/types/client_request.{type RequestSpecification}
import app/types/recipe.{type RecipeInstanceID}
import app/types/service.{type ServiceReference}
import gleam/option.{type Option}

pub type ServiceInteraction {
  ServiceInteractionCurrent(CurrentInteraction)
  ServiceInteractionPast(PastInteraction)
}

pub type CurrentInteraction {
  CurrentInteraction(
    service: ServiceReference,
    request: RequestSpecification,
    response: Option(String),
    response_sent: Bool,
    response_acknowledged: Bool,
  )
}

pub type PastInteraction {
  PastInteraction(
    recipe_instance_id: RecipeInstanceID,
    request_name: String,
    response: String,
  )
}
