//// Decoding of the client response

import app/types/client_response.{
  type ArgumentSubmission, type ClientResponse, ArgumentSubmission, ClientQuery,
  ClientSubmitArgument, ClientSubmitRecipe, QueryTypeRecipeList,
  QueryTypeRecipeStatistics,
}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string_tree
import serde/client/argument/decoder as argument_decoder
import serde/client/service_reference/decoder as service_reference_decoder

// import gleam/dynamic

// /// Wrap the error result so that the input data is included
// pub type DynamicDecodeError {
//   DynamicDecodeError(data: dynamic.Dynamic, errors: List(decode.DecodeError))
// }

// pub fn decode_dynamic(
//   data: dynamic.Dynamic,
// ) -> Result(ClientResponse, DynamicDecodeError) {
//   run_dynamic_decode(data)
// }

// fn run_dynamic_decode(data) {
//   let decoder = get_decoder()

//   case decode.run(data, decoder) {
//     Ok(result) -> Ok(result)
//     Error(decode_errors) -> Error(DynamicDecodeError(data, decode_errors))
//   }
// }

pub fn decode_json(
  json_string: String,
) -> Result(ClientResponse, json.DecodeError) {
  // "{
  //    \"type\": \"submit_recipe\",
  //    \"recipe\": \"calc\"
  // }"
  // OR
  // "{
  //    \"type\": \"submit_argument\",
  //    \"argument\": {
  //      \"recipe_id\": \"some_id\",
  //      \"recipe_instance_id\": \"some_instance_id\",
  //      \"service\": {
  //        \"id\":\"1234\",
  //        \"name\":\"calc\"
  //      },
  //      \"response\": {
  //        \"name\":\"test\",
  //        \"value\": {
  //          \"type\":\"Serialized\",
  //          \"value\": \"33\"
  //        }
  //      }
  //   }
  // }"
  // OR
  // "{
  //    \"type\": \"query_recipe_list\",
  // }"
  // OR
  // "{
  //    \"type\": \"query_recipe_stats"
  //    \"recipe_instance_id\": \"some_instance_id\"
  // }"
  // OR
  // "{
  //    \"type\": \"unknown\",
  // }"

  let decoder = get_client_response_decoder()

  case json.parse(from: json_string, using: decoder) {
    Ok(decoder_result) -> {
      decoder_result
      |> result.try_recover(fn(desc) { Error(json.UnexpectedSequence(desc)) })
    }
    Error(decode_error) -> Error(decode_error)
  }
}

fn get_client_response_decoder() -> Decoder(Result(ClientResponse, String)) {
  use response_type <- decode.field("type", decode.string)

  case response_type {
    "submit_recipe" -> {
      use recipe_desc <- decode.field("recipe", decode.string)
      decode.success(Ok(ClientSubmitRecipe(recipe_desc:)))
    }
    "submit_argument" -> {
      use submission <- decode.field("argument", get_submit_argument_decoder())
      decode.success(Ok(ClientSubmitArgument(submission:)))
    }
    "query_recipe_list" -> {
      decode.success(Ok(ClientQuery(QueryTypeRecipeList)))
    }
    "query_recipe_stats" -> {
      use recipe_instance_id <- decode.field(
        "recipe_instance_id",
        decode.string,
      )
      decode.success(
        Ok(ClientQuery(QueryTypeRecipeStatistics(recipe_instance_id:))),
      )
    }
    _ ->
      make_decode_failure(
        ["Unknown ClientResponse encoding: ", response_type],
        "ClientResponse",
      )
  }
}

fn get_submit_argument_decoder() -> decode.Decoder(ArgumentSubmission) {
  use recipe_id <- decode.field("recipe_id", decode.string)

  use recipe_instance_id <- decode.field("recipe_instance_id", decode.string)

  use service <- decode.field(
    "service",
    service_reference_decoder.get_service_decoder(),
  )

  use response <- decode.optional_field(
    "response",
    None,
    decode.optional(argument_decoder.get_argument_decoder()),
  )

  decode.success(ArgumentSubmission(
    recipe_id:,
    recipe_instance_id:,
    service:,
    response:,
  ))
}

fn make_decode_failure(
  parts: List(String),
  type_name: String,
) -> Decoder(Result(a, String)) {
  parts
  |> string_tree.from_strings()
  |> string_tree.to_string()
  |> Error()
  |> decode.failure(type_name)
}
