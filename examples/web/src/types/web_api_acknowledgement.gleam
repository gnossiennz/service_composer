import app/types/recipe.{type RecipeID, type RecipeInstanceID}
import gleam/option.{type Option}

pub type WebAPIAcknowledgement {
  WebAPIAcknowledgement(
    recipe_id: RecipeID,
    recipe_instance_id: RecipeInstanceID,
    ack_type: AcknowledgementType,
    warning: Option(String),
  )
}

pub type AcknowledgementType {
  ReceivedNewRecipe
  ReceivedClientUpdate
}
