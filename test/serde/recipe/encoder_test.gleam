import app/types/recipe.{
  Argument, ComposableStep, Recipe, SerializedValue, Substitution,
}
import app/types/service.{ServiceReference}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/recipe/encoder

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub const alt_calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.alt_examples.service_composer",
)

pub const other_service_reference = ServiceReference(
  name: "other",
  path: "com.examples.service_composer",
)

pub fn main() {
  gleeunit.main()
}

// ###################################################
// Encode a recipe
// ###################################################

pub fn encode_single_reference_test() {
  // there is a single ServiceReference in the recipe
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "instance:abcd-efg-hijk",
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
  |> should.equal(
    "{\"id\":\"recipe:abcd-efg-hijk\",\"iid\":\"instance:abcd-efg-hijk\",\"description\":\"Resolve the equation: 7x\",\"refs\":{\"calc\":\"com.examples.service_composer:calc\"},\"recipe\":\"calc operator:* operand:7\"}",
  )
}

pub fn encode_two_references_test() {
  // there are two ServiceReferences in the recipe with different names and IDs
  let recipe =
    Recipe(
      id: "recipe:abcd-efg-hijk",
      iid: "instance:abcd-efg-hijk",
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
  |> should.equal(
    "{\"id\":\"recipe:abcd-efg-hijk\",\"iid\":\"instance:abcd-efg-hijk\",\"description\":\"Resolve the equation: 7(3 + x)\",\"refs\":{\"other\":\"com.examples.service_composer:other\",\"calc\":\"com.examples.service_composer:calc\"},\"recipe\":\"calc operator:* operand:7 operand:(other operator:+ operand:3)\"}",
  )
}

pub fn encode_duplicate_references_test() {
  // there are two ServiceReferences in the recipe with the same name and different IDs
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
              service: alt_calc_service_reference,
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
  |> should.be_error()
  |> should.equal("Duplicate service name with different IDs: calc")
}
