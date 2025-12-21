import app/types/recipe.{
  Argument, ComposableStep, Recipe, SerializedValue, Substitution,
}
import app/types/service.{ServiceReference}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/recipe/decoder
import serde/recipe/encoder

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub const other_service_reference = ServiceReference(
  name: "other",
  path: "com.examples.service_composer",
)

pub fn main() {
  gleeunit.main()
}

// ###################################################
// Round-trip tests: decoding and encoding a recipe
// ###################################################

pub fn round_trip_recipe_to_recipe_single_reference_test() {
  // there is a single ServiceReference in the recipe
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "recipe:abcd-efg-hijk",
      description: Some("Resolve the equation: 7x"),
      root: ComposableStep(
        service: calc_service_reference,
        arguments: Some([
          Argument(name: "operator", value: SerializedValue("*")),
          Argument(name: "operand", value: SerializedValue("7")),
        ]),
        substitutions: None,
      ),
      error: None,
    )

  recipe
  |> encoder.encode()
  |> should.be_ok()
  |> decoder.decode_instance()
  |> should.be_ok()
  |> should.equal(recipe)
}

pub fn round_trip_recipe_to_recipe_two_references_test() {
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "recipe:abcd-efg-hijk",
      description: Some("Resolve the equation: 7(3 + x)"),
      root: ComposableStep(
        service: calc_service_reference,
        arguments: Some([
          Argument(name: "operator", value: SerializedValue("*")),
          Argument(name: "operand", value: SerializedValue("7")),
        ]),
        substitutions: Some([
          Substitution(
            name: "operand",
            step: ComposableStep(
              service: other_service_reference,
              arguments: Some([
                Argument(name: "operator", value: SerializedValue("+")),
                Argument(name: "operand", value: SerializedValue("3")),
              ]),
              substitutions: None,
            ),
          ),
        ]),
      ),
      error: None,
    )

  recipe
  |> encoder.encode()
  |> should.be_ok()
  |> decoder.decode_instance()
  |> should.be_ok()
  |> should.equal(recipe)
}

pub fn round_trip_serialized_to_serialized_two_references_test() {
  let serialized_recipe =
    "{
      \"id\":\"recipe:abcd-efg-hijk\",
      \"iid\":\"recipe:abcd-efg-hijk\",
      \"description\":\"Resolve the equation: 7(3 + x)\",
      \"refs\":{\"other\":\"com.examples.service_composer:other\",\"calc\":\"com.examples.service_composer:calc\"},
      \"recipe\":\"calc operator:* operand:7 operand:(other operator:+ operand:3)\"
    }"

  // the final result is 'serialized_recipe' without the whitespace
  serialized_recipe
  |> decoder.decode_instance()
  |> should.be_ok()
  |> encoder.encode()
  |> should.be_ok()
}
