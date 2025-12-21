import app/types/recipe.{type RecipeID, type RecipeInstanceID}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
import lustre_websocket.{type WebSocket}
import recipe/create.{extract_template}
import types/error.{type Error}
import types/interaction.{type CurrentInteraction, type PastInteraction}
import types/web_api_wrapper.{type RecipeEntry}

pub type Model {
  Model(
    ws: Option(WebSocket),
    // the list of available recipes (queried on startup)
    recipe_list: Option(List(RecipeEntry)),
    // a recipe that has been selected but not yet submitted
    selected_recipe: Option(String),
    // a dictionary of interactions per recipe instance
    instance_dict: Dict(RecipeInstanceID, RecipeInteractionInstance),
    // show/hide instances in the model viewer
    show_model_instances: Bool,
    // feedback to the user of significant events
    notifications: List(String),
    errors: List(Error),
  )
}

/// An instance handles all of the service interactions required
/// to fully resolve a recipe. Each of these service interactions
/// are handled one by one and retired once they are complete.
/// (see current_interaction and past_interactions)
/// It is possible to have no interactions for an instance:
/// an interaction describes the UI that allows a user to resolve
/// a service provider request; if the service provider already has
/// all of its arguments then it will make no requests
pub type RecipeInteractionInstance {
  RecipeInteractionInstance(
    // the recipe ID and the original recipe description
    // (before evolving through execution of the recipe)
    recipe_info: RecipeInfo,
    // the evolution of the recipe over time
    recipe_evolution: List(RecipeEvolution),
    // the recipe call statistics (returned from the dispatcher at recipe submission
    // or when a recipe step is resolved)
    stats: List(Dict(String, Int)),
    // feedback to the user of significant per-instance events
    notifications: List(String),
    // the current user interaction (a UI element for gathering input)
    current_interaction: Option(CurrentInteraction),
    // the list of past interactions and the values provided by the user
    past_interactions: List(PastInteraction),
    // the final result of recipe evaluation
    result: Option(String),
    warnings: List(String),
  )
}

pub fn make_new_instance(
  recipe_id: RecipeID,
  recipe_instance_id: RecipeInstanceID,
) -> RecipeInteractionInstance {
  RecipeInteractionInstance(
    recipe_info: RecipeInfo(
      recipe_id:,
      recipe_instance_id:,
      template: extract_template(recipe_id),
    ),
    recipe_evolution: [],
    stats: [],
    notifications: [],
    current_interaction: None,
    past_interactions: [],
    result: None,
    warnings: [],
  )
}

pub type RecipeInfo {
  RecipeInfo(
    recipe_id: RecipeID,
    recipe_instance_id: RecipeInstanceID,
    template: String,
  )
}

// the change of the recipe description as the recipe executes
pub type RecipeEvolution {
  RecipeEvolution(recipe_instance_id: RecipeInstanceID, recipe_desc: String)
}
