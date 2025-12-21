import app/types/recipe.{
  Argument, ComposableStep, Recipe, SerializedValue, Substitution,
}
import app/types/service.{ServiceReference}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/recipe/step/encoder as recipe_step_encoder

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub fn main() {
  gleeunit.main()
}

// ###################################################
// Encoding a recipe step
// ###################################################

pub fn encode_one_level_recipe_test() {
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "recipe:abcd-efg-hijk",
      description: Some("Add five"),
      root: ComposableStep(
        service: calc_service_reference,
        arguments: Some([
          Argument(name: "operator", value: SerializedValue("+")),
          Argument(name: "operand", value: SerializedValue("5")),
        ]),
        substitutions: None,
      ),
      error: None,
    )

  recipe.root
  |> recipe_step_encoder.encode()
  |> should.equal("calc operator:+ operand:5")
}

pub fn encode_two_level_recipe_test() {
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "recipe:abcd-efg-hijk",
      description: Some("Double an input number and add five"),
      root: ComposableStep(
        service: calc_service_reference,
        arguments: Some([
          Argument(name: "operator", value: SerializedValue("+")),
          Argument(name: "operand", value: SerializedValue("5")),
        ]),
        substitutions: Some([
          Substitution(
            name: "operand",
            step: ComposableStep(
              service: calc_service_reference,
              arguments: Some([
                Argument(name: "operator", value: SerializedValue("*")),
                Argument(name: "operand", value: SerializedValue("2")),
              ]),
              substitutions: None,
            ),
          ),
        ]),
      ),
      error: None,
    )

  recipe.root
  |> recipe_step_encoder.encode()
  |> should.equal(
    "calc operator:+ operand:5 operand:(calc operator:* operand:2)",
  )
}
