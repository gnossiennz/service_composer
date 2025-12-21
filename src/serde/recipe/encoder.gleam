//// Serialize a recipe or recipe template

import app/types/recipe.{
  type ComposableStep, type Recipe, type RecipeError, Recipe,
}
import app/types/service.{
  type ServiceReference, ServiceReference, make_service_name,
}
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import serde/recipe/step/encoder

/// some serialization examples:
// {
//   "id": "recipe: abcd-efg-hijk",
//   "description": "Resolve the equation: 7(3 + x)"
//   "refs": {
//     "calc": "com.examples.service_composer:calc"
//   },
//   "recipe": "calc operator:* operand:7 operand:(calc operator:+ operand:3)"
// }

// OR

// {
//   "id": "recipe: abcd-efg-hijk",
//   "description": "Resolve the equation: 7(3 + x)"
//   "error": "This is the error"
// }

// TODO check examples above
pub fn encode(recipe: Recipe) -> Result(String, String) {
  serialize_recipe(recipe)
}

fn serialize_recipe(recipe: Recipe) -> Result(String, String) {
  let Recipe(id:, iid:, description:, root:, error:) = recipe

  case add_service_references(root) {
    Ok(services) -> {
      services
      |> make_field_dictionary(id, description, root)
      |> add_additional_fields(iid, error)
      |> instance_constructor()
      |> json.to_string()
      |> Ok()
    }
    Error(description) -> Error(description)
  }
}

fn instance_constructor(field_dictionary: Dict(String, json.Json)) -> json.Json {
  ["id", "iid", "description", "refs", "recipe"]
  |> make_object(field_dictionary)
}

fn make_object(
  fields: List(String),
  field_dictionary: Dict(String, json.Json),
) -> json.Json {
  fields
  |> list.map(fn(key) {
    let assert Ok(json) = dict.get(field_dictionary, key)
    #(key, json)
  })
  |> json.object()
}

fn make_field_dictionary(
  services: Dict(String, String),
  id: String,
  description: Option(String),
  root: ComposableStep,
) -> Dict(String, json.Json) {
  [
    #("id", json.string(id)),
    #("description", json.nullable(description, of: json.string)),
    #("refs", services |> json.dict(fn(str) { str }, json.string)),
    add_recipe_description(root),
  ]
  |> dict.from_list()
}

fn add_additional_fields(
  dict: Dict(String, json.Json),
  iid: String,
  error: Option(RecipeError),
) -> Dict(String, json.Json) {
  [#("iid", json.string(iid)), add_error(error)]
  |> list.fold(dict, fn(acc, field) { dict.insert(acc, field.0, field.1) })
}

fn add_error(error: Option(RecipeError)) -> #(String, json.Json) {
  case error {
    Some(error) -> {
      let encoded =
        [
          #("error", json.string(error.error)),
          #("detail", json.nullable(error.detail, of: json.string)),
        ]
        |> json.object()

      #("error", encoded)
    }
    None -> #("error", json.null())
  }
}

fn add_service_references(
  root: ComposableStep,
) -> Result(Dict(String, String), String) {
  dict.new() |> add_refs_impl(root)
}

fn add_recipe_description(root) -> #(String, json.Json) {
  #("recipe", root |> encoder.encode() |> json.string())
}

fn add_refs_impl(
  services: Dict(String, String),
  root: ComposableStep,
) -> Result(Dict(String, String), String) {
  let current = services |> add_service(root.service)

  case current, root.substitutions {
    Ok(current), None -> Ok(current)
    Ok(current), Some(substitutions) -> {
      substitutions
      |> list.try_fold(current, fn(service_dict, substitution) {
        case service_dict |> add_service(substitution.step.service) {
          Ok(service_dict) -> service_dict |> add_refs_impl(substitution.step)
          error -> error
        }
      })
    }
    error, _ -> error
  }
}

fn add_service(
  service_dict: Dict(String, String),
  service_reference: ServiceReference,
) -> Result(Dict(String, String), String) {
  let ServiceReference(name: short_name, path: _path) = service_reference
  let fully_qualified_service_name = make_service_name(service_reference)

  // TODO handle duplicate service names by extending the short name w/ the path

  // check for duplicate service names with different IDs
  case
    is_short_name_shared(service_dict, short_name, fully_qualified_service_name)
  {
    False ->
      Ok(service_dict |> dict.insert(short_name, fully_qualified_service_name))
    True -> Error("Duplicate service name with different IDs: " <> short_name)
  }
}

fn is_short_name_shared(
  service_dict: Dict(String, String),
  short_name: String,
  fully_qualified_name: String,
) -> Bool {
  // return true if the short name already exists in the dictionary
  // for a different fully qualified name
  dict.has_key(service_dict, short_name)
  && { dict.get(service_dict, short_name) |> result.unwrap("") }
  != fully_qualified_name
}
