import app/types/recipe.{
  type Argument, type ArgumentValue, type Arguments, FloatValue, IntValue,
  SerializedValue, StringValue,
}
import gleam/json
import gleam/option.{type Option, None, Some}

/// Serialize the argument state for a service
pub fn encode(arguments: Arguments) -> json.Json {
  json.array(arguments, encode_argument)
}

pub fn encode_argument(argument: Argument) -> json.Json {
  case encode_argument_value(argument.value) {
    Some(arg) ->
      json.object([#("name", json.string(argument.name)), #("value", arg)])
    None -> json.null()
  }
}

fn encode_argument_value(argument_value: ArgumentValue) -> Option(json.Json) {
  case argument_value {
    IntValue(value) -> make_argument_value("Int", json.int(value))
    FloatValue(value) -> make_argument_value("Float", json.float(value))
    StringValue(value) -> make_argument_value("String", json.string(value))
    SerializedValue(value) ->
      make_argument_value("Serialized", json.string(value))
    recipe.NoArgument -> None
  }
}

fn make_argument_value(serialized_type, serialized_value) -> Option(json.Json) {
  json.object([
    #("type", json.string(serialized_type)),
    #("value", serialized_value),
  ])
  |> Some
}
