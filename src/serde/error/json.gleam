import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string_tree.{type StringTree}

pub fn describe_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "UnexpectedEndOfInput"
    json.UnexpectedByte(desc) -> "UnexpectedByte: " <> desc
    json.UnexpectedSequence(desc) -> "UnexpectedSequence: " <> desc
    // json.UnexpectedFormat(decode_errors) ->
    //   "UnexpectedFormat: "
    //   <> describe_decode_errors(decode_errors, format_dynamic_error)
    json.UnableToDecode(decode_errors) ->
      "UnableToDecode: "
      <> describe_decode_errors(decode_errors, format_decode_error)
  }
}

pub fn describe_decode_errors(
  decode_errors: List(_),
  stringify: fn(_) -> String,
) -> String {
  decode_errors
  |> list.map(fn(decode_error) { stringify(decode_error) })
  |> stringlist_to_string()
}

// pub fn format_dynamic_error(error: dynamic.DecodeError) -> String {
//   case error {
//     dynamic.DecodeError(expected:, found:, path:) ->
//       stringify_error(expected, found, path)
//   }
// }

pub fn format_decode_error(error: decode.DecodeError) -> String {
  case error {
    decode.DecodeError(expected:, found:, path:) ->
      stringify_error(expected, found, path)
  }
}

pub fn make_json_error(error_description: String) -> StringTree {
  error_description |> json.string() |> json.to_string_tree()
}

fn stringify_error(expected, found, path) {
  "Expected "
  <> expected
  <> " but found "
  <> found
  <> " on path: "
  <> stringlist_to_string(path)
  <> "\n"
}

fn stringlist_to_string(items) {
  string_tree.from_strings(items)
  |> string_tree.to_string()
}
