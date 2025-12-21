//// Use this module to create a Recipe from a description

import app/types/recipe.{type Recipe, type RecipeID, Recipe}
import app/types/service.{type FullyQualifiedServiceName, type ServiceName}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/option.{None}
import gleam/result
import serde/recipe/step/decoder as recipe_step_decoder

pub fn make_recipe(
  recipe_instance_id: String,
  recipe_description: String,
  services: Dict(ServiceName, FullyQualifiedServiceName),
) -> Result(Recipe, String) {
  // The recipe instance ID should be unique
  // across the controlling system (e.g. a web service)
  // This is in contrast to the recipe ID which is shared across all instances
  // with the same recipe description.
  // The recipe ID is the recipe template i.e. it encodes the original recipe description.
  // Using the recipe ID alone, a new instance of the recipe can be recreated.
  // Although a recipe description can also be generated using the root step of
  // the recipe, this evolves over time as the recipe executes, so it is useful
  // to encode the original recipe description (the recipe template) within the ID
  // Why bother encoding the template? Why not use it directly? Just because :-)
  let recipe_id =
    recipe_description
    |> bit_array.from_string()
    |> bit_array.base64_encode(True)

  recipe_description
  |> recipe_step_decoder.decode(services)
  |> result.map(fn(step) {
    Recipe(
      id: recipe_id,
      iid: recipe_instance_id,
      description: None,
      root: step,
      error: None,
    )
  })
}

/// Extract the original recipe description from the recipe ID
pub fn extract_template(recipe_id: RecipeID) -> String {
  recipe_id
  |> bit_array.base64_decode()
  |> result.try(fn(bits) { bit_array.to_string(bits) })
  |> result.lazy_unwrap(fn() { "" })
}
