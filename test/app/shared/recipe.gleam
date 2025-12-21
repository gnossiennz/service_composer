//// Functions for recipe making for testing purposes only
//// see also recipe_utility which is for non-testing purposes

import app/types/recipe.{
  type Arguments, type ComposableStep, type Recipe, type RecipeError,
  type Substitutions, ComposableStep, Recipe, RecipeError, Substitution,
}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import serde/recipe/step/decoder as recipe_step_decoder

pub fn make_recipe(
  recipe_description: String,
  recipe_id: Option(String),
  recipe_instance_id: Option(String),
  root_transformer: Option(fn(recipe.ComposableStep) -> recipe.ComposableStep),
) -> Recipe {
  make_recipe_impl(
    recipe_description,
    recipe_id,
    recipe_instance_id,
    None,
    root_transformer,
  )
}

pub fn make_recipe_with_error(
  recipe_description: String,
  root_transformer: Option(fn(recipe.ComposableStep) -> recipe.ComposableStep),
) -> Recipe {
  make_recipe_impl(
    recipe_description,
    None,
    None,
    Some(RecipeError(error: "some error", detail: None)),
    root_transformer,
  )
}

fn make_recipe_impl(
  recipe_description: String,
  recipe_id: Option(String),
  recipe_instance_id: Option(String),
  error: Option(RecipeError),
  root_transformer: Option(fn(recipe.ComposableStep) -> recipe.ComposableStep),
) -> Recipe {
  // Note that the services dict is keyed by name not ID
  // TODO this is fragile; instead, get the service refs from the loaded modules
  let services =
    dict.from_list([
      #("calc", "com.examples.service_composer:calc"),
      #("sqrt", "com.examples.service_composer:sqrt"),
    ])

  let assert Ok(root) = recipe_step_decoder.decode(recipe_description, services)

  // optionally transform the decoded step
  // for example: convert argument representations from SerializedValue to FloatValue
  // provider services try and hold onto the most efficient representation so this
  // conversion may be observed when receiving argument updates from a service call
  Recipe(
    id: case recipe_id {
      Some(id) -> id
      None -> "some_recipe"
    },
    iid: case recipe_instance_id {
      Some(iid) -> iid
      None -> "some_recipe_instance"
    },
    description: None,
    root: case root_transformer {
      Some(transformer) -> transformer(root)
      None -> root
    },
    error:,
  )
}

/// Run a conversion function on the arguments of a recipe step and all sub-steps
pub fn convert_root(
  root: ComposableStep,
  argument_converter: fn(Option(Arguments)) -> Option(Arguments),
) -> ComposableStep {
  let ComposableStep(service:, arguments:, substitutions:) = root
  let updated_arguments = argument_converter(arguments)

  case substitutions {
    Some(substitutions_list) -> {
      ComposableStep(
        service:,
        arguments: updated_arguments,
        substitutions: convert_substitutions(
          substitutions_list,
          argument_converter,
        ),
      )
    }
    None -> {
      // leaf node
      ComposableStep(service:, arguments: updated_arguments, substitutions:)
    }
  }
}

fn convert_substitutions(
  substitutions: Substitutions,
  argument_converter: fn(Option(Arguments)) -> Option(Arguments),
) -> Option(Substitutions) {
  substitutions
  |> list.fold([], fn(acc, sub) {
    let Substitution(name:, step:) = sub
    let updated_step = convert_root(step, argument_converter)
    [Substitution(name:, step: updated_step), ..acc]
  })
  |> Some
}
