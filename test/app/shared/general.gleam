import app/shared/service_testing_service.{type TestResult}
import app/types/recipe.{type ArgumentValue, FloatValue}
import gleam/float
import gleam/int
import gleam/option.{type Option}
import gleeunit/should

pub fn should_be(
  result: Option(TestResult),
  expected: Option(TestResult),
) -> Option(TestResult) {
  result |> should.equal(expected)
  result
}

pub fn parse_as_int_operand(value: String) -> Result(ArgumentValue, String) {
  case int.parse(value) {
    Ok(i) -> Ok(FloatValue(int.to_float(i)))
    Error(_) -> Error(value)
  }
}

pub fn parse_as_float_operand(value: String) -> Result(ArgumentValue, String) {
  case float.parse(value) {
    Ok(f) -> Ok(FloatValue(f))
    Error(_) -> Error(value)
  }
}
