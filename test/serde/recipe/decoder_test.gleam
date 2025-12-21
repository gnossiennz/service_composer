import app/types/recipe.{
  Argument, ComposableStep, Recipe, SerializedValue, Substitution,
}
import app/types/service.{ServiceReference}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/error/json as json_error_utility
import serde/recipe/decoder

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
// Decode a recipe
// ###################################################

pub fn decode_unreferenced_test() {
  // the services referenced in the recipe description are not referenced in 'refs'
  let recipe =
    "{
        \"id\": \"recipe:abcd-efg-hijk\",
        \"iid\": \"recipe:abcd-efg-hijk\",
        \"description\": \"Resolve the equation: 7(3 + x)\",
        \"refs\": {
            \"calc\": \"com.examples.service_composer:calc\"
        },
        \"recipe\": \"other operator:* operand:7 operand:(other operator:+ operand:3)\"
    }"

  recipe
  |> decoder.decode_instance()
  |> should.be_error()
  |> json_error_utility.describe_error()
  |> should.equal(
    "UnableToDecode: Expected recipe description but found Dict on path: \n",
  )
}

pub fn decode_duplicate_references_test() {
  // the names used in the refs section should be unique
  // a duplicate reference refers to a different service using a name
  // that was previously allocated in the refs: it has the same name but with different ID
  // Note that this is not currently detected and so will succeed
  // i.e. decoding refs using 'decode.dict' will silently swallow duplicate keys
  // TODO fix this
  let recipe =
    "{
        \"id\": \"recipe:abcd-efg-hijk\",
        \"iid\": \"recipe:abcd-efg-hijk\",
        \"description\": \"Resolve the equation: 7x\",
        \"refs\": {
            \"calc\": \"com.examples.service_composer:calc\",
            \"calc\": \"com.examples.service_composer:other\"
        },
        \"recipe\": \"calc operator:* operand:7\"
    }"

  recipe
  |> decoder.decode_instance()
  |> should.be_ok()
  |> should.equal(Recipe(
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
  ))
}

pub fn decode_single_reference_test() {
  let recipe =
    "{
        \"id\": \"recipe:abcd-efg-hijk\",
        \"iid\": \"recipe:abcd-efg-hijk\",
        \"description\": \"Resolve the equation: 7(3 + x)\",
        \"refs\": {
            \"calc\": \"com.examples.service_composer:calc\"
        },
        \"recipe\": \"calc operator:* operand:7 operand:(calc operator:+ operand:3)\"
    }"

  recipe
  |> decoder.decode_instance()
  |> should.be_ok()
  |> should.equal(Recipe(
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
            service: calc_service_reference,
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
  ))
}

pub fn decode_two_references_test() {
  let recipe =
    "{
        \"id\": \"recipe:abcd-efg-hijk\",
        \"iid\": \"recipe:abcd-efg-hijk\",
        \"description\": \"Resolve the equation: 7(3 + x)\",
        \"refs\": {
            \"calc\": \"com.examples.service_composer:calc\",
            \"other\": \"com.examples.service_composer:other\"
        },
        \"recipe\": \"calc operator:* operand:7 operand:(other operator:+ operand:3)\"
    }"

  recipe
  |> decoder.decode_instance()
  |> should.be_ok()
  |> should.equal(Recipe(
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
  ))
}
