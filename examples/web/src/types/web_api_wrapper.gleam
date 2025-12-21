//// The Web API response values
//// These are the allowed values passed to a web client

import app/types/recipe.{type RecipeInstanceID}
import app/types/service_call.{type DispatcherReturn}
import gleam/dict.{type Dict}
import types/web_api_acknowledgement.{type WebAPIAcknowledgement}

// The WrappedResponse value comes from the dispatcher
// All others are generated within the web service
pub type WebAPIWrapper {
  WrappedResponse(DispatcherReturn)
  WrappedAcknowledgement(WebAPIAcknowledgement)
  WrappedRecipeList(List(RecipeEntry))
  WrappedRecipeStatistics(RecipeInstanceStatistics)
  WrappedError(WebAPIError)
}

pub type RecipeEntry {
  RecipeEntry(description: String, specification: String)
}

pub type RecipeInstanceStatistics {
  RecipeInstanceStatistics(
    recipe_instance_id: RecipeInstanceID,
    dictionary: Dict(String, Int),
  )
}

pub type WebAPIError {
  GeneralError(String)
  ClientDeserializationError(DispatcherReturn)
}
