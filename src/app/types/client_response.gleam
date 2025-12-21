//// Client Response types (used in client response to service requests)

import app/types/recipe.{type Argument, type RecipeID, type RecipeInstanceID}
import app/types/service.{type ServiceReference}
import gleam/option.{type Option}

pub type ClientResponse {
  ClientSubmitRecipe(recipe_desc: String)
  ClientSubmitArgument(submission: ArgumentSubmission)
  ClientQuery(query_type: QueryType)
}

// An argument submission is a user's response to a request from a service provider
// where the service provider is called within the specified recipe instance
// The dispatcher deals only with this client response type
pub type ArgumentSubmission {
  ArgumentSubmission(
    recipe_id: RecipeID,
    recipe_instance_id: RecipeInstanceID,
    service: ServiceReference,
    response: Option(Argument),
  )
}

// Query for a list of available recipes or the statistics for a running recipe
pub type QueryType {
  QueryTypeRecipeList
  QueryTypeRecipeStatistics(recipe_instance_id: RecipeInstanceID)
}
