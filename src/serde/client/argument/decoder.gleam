import app/types/recipe.{
  type Argument, type ArgumentValue, type Arguments, Argument, FloatValue,
  IntValue, SerializedValue, StringValue,
}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

pub fn decode(json_string: String) -> Result(Arguments, json.DecodeError) {
  // "[
  //   {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
  //   {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}},
  //   {\"name\":\"test3\",\"value\":{\"type\":\"String\",\"value\":\"A string test\"}},
  //   {\"name\":\"test4\",\"value\":{\"type\":\"Serialized\",\"value\":\"A serialized test\"}}
  // ]"

  let decoder = decode.list(of: get_argument_decoder())

  json.parse(from: json_string, using: decoder)
}

pub fn get_arguments_decoder() -> decode.Decoder(Option(Arguments)) {
  decode.optional(decode.list(of: get_argument_decoder()))
}

pub fn get_argument_decoder() -> decode.Decoder(Argument) {
  let argument_value_decoder = {
    use value_type <- decode.field("type", decode.string)
    case value_type {
      "Int" -> decode_int()
      "Float" -> decode_float()
      "String" -> decode_string()
      "Serialized" -> decode_serialized()
      _ -> decode.failure(SerializedValue(""), "ArgumentValue")
    }
  }

  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", argument_value_decoder)

  decode.success(Argument(name:, value:))
}

fn decode_int() -> decode.Decoder(ArgumentValue) {
  decode_item(decode.int, IntValue)
}

fn decode_float() -> decode.Decoder(ArgumentValue) {
  decode_item(decode.float, FloatValue)
}

fn decode_string() -> decode.Decoder(ArgumentValue) {
  decode_item(decode.string, StringValue)
}

fn decode_serialized() -> decode.Decoder(ArgumentValue) {
  decode_item(decode.string, SerializedValue)
}

fn decode_item(
  decoder: decode.Decoder(_),
  constructor: fn(a) -> ArgumentValue,
) -> decode.Decoder(ArgumentValue) {
  use value <- decode.field("value", decoder)

  decode.success(constructor(value))
}
