//// Test encoding/decoding of arguments and argument values
//// The decoder is used within the response decoder
//// (for decoding the argument)
//// This encoder is just for testing but could also be used
//// for external storage of service state

import app/types/recipe.{Argument}
import gleam/json
import gleeunit
import gleeunit/should
import serde/client/argument/decoder as argument_decoder
import serde/client/argument/encoder as argument_encoder

pub fn main() {
  gleeunit.main()
}

// ###############################################
// Round-trip arguments tests
// ###############################################

pub fn round_trip_arguments_test() {
  let argument = [
    Argument(name: "test1", value: recipe.IntValue(33)),
    Argument(name: "test2", value: recipe.FloatValue(44.4)),
    Argument(name: "test3", value: recipe.StringValue("A string test")),
    Argument(name: "test4", value: recipe.SerializedValue("A serialized test")),
  ]

  argument
  |> argument_encoder.encode()
  |> json.to_string()
  |> argument_decoder.decode()
  |> should.be_ok()
  |> should.equal(argument)
}

pub fn round_trip_serialized_arguments_test() {
  let serialized =
    "[{\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},{\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}},{\"name\":\"test3\",\"value\":{\"type\":\"String\",\"value\":\"A string test\"}},{\"name\":\"test4\",\"value\":{\"type\":\"Serialized\",\"value\":\"A serialized test\"}}]"

  serialized
  |> argument_decoder.decode()
  |> should.be_ok()
  |> argument_encoder.encode()
  |> json.to_string()
  |> should.equal(serialized)
}
