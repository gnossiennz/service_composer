import app/types/client_response.{type ArgumentSubmission, ArgumentSubmission}
import app/types/recipe.{
  type RecipeID, type RecipeInstanceID, Argument, SerializedValue,
}
import app/types/service.{type ServiceReference}
import gleam/option.{Some}

pub fn make_client_response(
  recipe_id: RecipeID,
  recipe_instance_id: RecipeInstanceID,
  service: ServiceReference,
  name: String,
  value: String,
) -> ArgumentSubmission {
  ArgumentSubmission(
    recipe_id:,
    recipe_instance_id:,
    service:,
    response: Some(Argument(name:, value: SerializedValue(value))),
  )
}
