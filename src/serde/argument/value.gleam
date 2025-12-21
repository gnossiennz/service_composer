import app/types/recipe.{
  type ArgumentValue, FloatValue, IntValue, NoArgument, SerializedValue,
  StringValue,
}
import gleam/float
import gleam/int

pub fn argument_value_to_string(value: ArgumentValue) -> String {
  case value {
    NoArgument -> "none"
    SerializedValue(s) -> s
    IntValue(i) -> int.to_string(i)
    FloatValue(f) -> float.to_string(f)
    StringValue(s) -> s
  }
}
