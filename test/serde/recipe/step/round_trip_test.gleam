import gleam/dict
import gleeunit
import gleeunit/should
import serde/recipe/step/decoder as recipe_step_decoder
import serde/recipe/step/encoder as recipe_step_encoder

pub fn main() {
  gleeunit.main()
}

const service_list = [
  #("calc", "com.examples.service_composer:calc"),
  #("other", "com.examples.service_composer:other"),
]

// ###################################################
// Round-trip tests: decoding and encoding a recipe step
// ###################################################

pub fn round_trip_one_level_test() {
  let services = dict.from_list(service_list)

  "calc operator:+ operand:5"
  |> recipe_step_decoder.decode(services)
  |> should.be_ok()
  |> recipe_step_encoder.encode()
  |> should.equal("calc operator:+ operand:5")
}

pub fn round_trip_two_levels_test() {
  let services = dict.from_list(service_list)

  "calc operator:+ operand:5 operand:(other operator:* operand:2)"
  |> recipe_step_decoder.decode(services)
  |> should.be_ok()
  |> recipe_step_encoder.encode()
  |> should.equal(
    "calc operator:+ operand:5 operand:(other operator:* operand:2)",
  )
}

pub fn round_trip_two_levels_fully_substituted_test() {
  let services = dict.from_list(service_list)

  "calc operator:+ operand:(other operator:+ operand:2 operand:3) operand:(other operator:* operand:2)"
  |> recipe_step_decoder.decode(services)
  |> should.be_ok()
  |> recipe_step_encoder.encode()
  |> should.equal(
    "calc operator:+ operand:(other operator:+ operand:2 operand:3) operand:(other operator:* operand:2)",
  )
}

pub fn round_trip_three_levels_test() {
  let services = dict.from_list(service_list)

  "calc operator:* operand:7 operand:(other operator:+ operand:(other operator:+ operand:2 operand:5))"
  |> recipe_step_decoder.decode(services)
  |> should.be_ok()
  |> recipe_step_encoder.encode()
  |> should.equal(
    "calc operator:* operand:7 operand:(other operator:+ operand:(other operator:+ operand:2 operand:5))",
  )
}
