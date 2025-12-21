//// Deserialize a recipe or recipe template
//// A recipe is a structure with one or more hierarchically embedded steps

import app/types/recipe.{
  type ComposableStep, type Recipe, type RecipeError, ComposableStep, Recipe,
  RecipeError,
}
import app/types/service.{ServiceReference}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import serde/recipe/step/decoder

pub fn decode_instance(json_string: String) -> Result(Recipe, json.DecodeError) {
  let decoder =
    get_decoder(fn(id, iid, description, root, error) {
      Recipe(id:, iid:, description:, root:, error:)
    })

  json_string
  |> json.parse(using: decoder)
}

fn get_decoder(
  constructor: fn(
    String,
    String,
    Option(String),
    ComposableStep,
    Option(RecipeError),
  ) ->
    a,
) -> decode.Decoder(a) {
  use id <- decode.field("id", decode.string)
  use iid <- decode.optional_field("iid", "", decode.string)
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use services <- decode.field(
    "refs",
    decode.dict(decode.string, decode.string),
  )
  use recipe <- decode.field("recipe", decode.string)

  let root_step = recipe |> decoder.decode(services)

  case root_step {
    Ok(root) -> {
      let recipe = constructor(id, iid, description, root, None)
      decode.success(recipe)
    }
    Error(error) -> {
      let recipe_error = RecipeError(error:, detail: None)
      let root =
        ComposableStep(ServiceReference("Unknown", "Unknown"), None, None)
      let recipe = constructor(id, iid, description, root, Some(recipe_error))
      decode.failure(recipe, "recipe description")
    }
  }
}
