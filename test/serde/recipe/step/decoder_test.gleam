import app/types/recipe.{
  type Argument, type Substitution, Argument, ComposableStep, SerializedValue,
  Substitution,
}
import app/types/service.{ServiceReference, make_service_name}
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import serde/recipe/step/decoder as recipe_step_decoder

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
// Decoding a recipe step
// ###################################################

pub fn decode_nothing_recipe_test() {
  ""
  |> fails_with("EndOfInput")
}

pub fn decode_no_such_service_recipe_test() {
  "unknown_service"
  |> fails_with("Expected(expected a service name), got: Name(unknown_service)")
}

pub fn decode_no_arg_recipe_test() {
  "calc"
  |> succeeds_with("com.examples.service_composer:calc", None, None)
}

pub fn decode_one_arg_recipe_test() {
  "calc operator:+"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([Argument("operator", SerializedValue("+"))]),
    None,
  )
}

pub fn decode_malformed_arg_recipe_test() {
  "calc operator:"
  |> fails_with("EndOfInput")
}

pub fn decode_two_arg_recipe_test() {
  "calc operator:+ operand:33"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([
      Argument("operator", SerializedValue("+")),
      Argument("operand", SerializedValue("33")),
    ]),
    None,
  )
}

pub fn decode_three_arg_recipe_test() {
  "calc operator:* operand:7 operand:3"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("7")),
      Argument("operand", SerializedValue("3")),
    ]),
    None,
  )
}

pub fn decode_single_substitution1_recipe_test() {
  "calc operator:* operand:7 operand:(other operator:+ operand:3)"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("7")),
    ]),
    Some([
      Substitution(
        "operand",
        ComposableStep(
          service: other_service_reference,
          arguments: Some([
            Argument("operator", SerializedValue("+")),
            Argument("operand", SerializedValue("3")),
          ]),
          substitutions: None,
        ),
      ),
    ]),
  )
}

pub fn decode_malformed_substitution_recipe_test() {
  "calc operator:* operand:7 operand:()"
  |> fails_with("Expected(expected a service name), got: SubstitutionEnd")
}

pub fn decode_single_substitution2_recipe_test() {
  "calc operand:(other operator:+ operand:3) operator:* operand:7"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("7")),
    ]),
    Some([
      Substitution(
        "operand",
        ComposableStep(
          service: other_service_reference,
          arguments: Some([
            Argument("operator", SerializedValue("+")),
            Argument("operand", SerializedValue("3")),
          ]),
          substitutions: None,
        ),
      ),
    ]),
  )
}

pub fn decode_two_substitutions_recipe_test() {
  "calc operand:(other operator:+ operand:3) operand:(other operator:+ operand:2 operand:5) operator:*"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([Argument("operator", SerializedValue("*"))]),
    Some([
      Substitution(
        "operand",
        ComposableStep(
          service: other_service_reference,
          arguments: Some([
            Argument("operator", SerializedValue("+")),
            Argument("operand", SerializedValue("3")),
          ]),
          substitutions: None,
        ),
      ),
      Substitution(
        "operand",
        ComposableStep(
          service: other_service_reference,
          arguments: Some([
            Argument("operator", SerializedValue("+")),
            Argument("operand", SerializedValue("2")),
            Argument("operand", SerializedValue("5")),
          ]),
          substitutions: None,
        ),
      ),
    ]),
  )
}

pub fn decode_substitute_two_levels_recipe_test() {
  "calc operator:* operand:7 operand:(other operator:+ operand:(other operator:+ operand:2 operand:5))"
  |> succeeds_with(
    "com.examples.service_composer:calc",
    Some([
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("7")),
    ]),
    Some([
      Substitution(
        "operand",
        ComposableStep(
          service: other_service_reference,
          arguments: Some([Argument("operator", SerializedValue("+"))]),
          substitutions: Some([
            Substitution(
              "operand",
              ComposableStep(
                service: other_service_reference,
                arguments: Some([
                  Argument("operator", SerializedValue("+")),
                  Argument("operand", SerializedValue("2")),
                  Argument("operand", SerializedValue("5")),
                ]),
                substitutions: None,
              ),
            ),
          ]),
        ),
      ),
    ]),
  )
}

fn succeeds_with(
  recipe: String,
  service_id: String,
  args: Option(List(Argument)),
  substitutions: Option(List(Substitution)),
) {
  let services =
    dict.from_list([
      #("calc", "com.examples.service_composer:calc"),
      #("other", "com.examples.service_composer:other"),
    ])
  let step =
    ComposableStep(
      service: calc_service_reference,
      arguments: args,
      substitutions: substitutions,
    )

  service_id |> should.equal(make_service_name(step.service))

  recipe
  |> recipe_step_decoder.decode(services)
  |> should.equal(Ok(step))
}

fn fails_with(recipe: String, expected: String) {
  let services =
    dict.from_list([
      #("calc", "com.examples.service_composer:calc"),
      #("other", "com.examples.service_composer:other"),
    ])

  let result = recipe |> recipe_step_decoder.decode(services)
  let assert Error(description) = result

  description |> should.equal(expected)
}
