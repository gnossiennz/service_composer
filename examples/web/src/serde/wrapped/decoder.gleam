import gleam/dynamic/decode
import gleam/json
import serde/acknowledgement/decoder as acknowledgement_decoder
import serde/client/dispatcher_return/decoder as dispatcher_return_decoder
import types/web_api_wrapper.{
  type WebAPIWrapper, ClientDeserializationError, GeneralError, RecipeEntry,
  RecipeInstanceStatistics, WrappedAcknowledgement, WrappedError,
  WrappedRecipeList, WrappedRecipeStatistics, WrappedResponse,
}

pub fn decode(json_string: String) -> Result(WebAPIWrapper, json.DecodeError) {
  let decoder = get_wrapper_decoder()

  json.parse(from: json_string, using: decoder)
}

fn get_wrapper_decoder() -> decode.Decoder(WebAPIWrapper) {
  // The value attribute holds whatever value is wrapped
  // Response example:
  // "{
  //     \"type\": \"response\",
  //     \"value\": {
  //         \"recipe_instance_id\": \"recipe:abcd-efg-hijk\",
  //         \"type\": \"result\",
  //         \"service\": {
  //             \"id\": \"1234\",
  //             \"name\": \"calc\"
  //         },
  //         \"state\": [
  //           {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
  //           {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}}
  //         ],
  //         \"result\": \"44\",
  //         \"warning\": \"More than two operands provided\"
  //     }
  // }"

  use wrapped_type <- decode.field("type", decode.string)

  case wrapped_type {
    "response" -> get_dispatcher_return_decoder()
    "ack" -> get_acknowledgement_decoder()
    "recipe_list" -> get_recipe_list_decoder()
    "recipe_stats" -> get_recipe_stats_decoder()
    "deser_error" -> get_deser_error_decoder()
    "gen_error" -> get_gen_error_decoder()
    _ -> {
      decode.failure(WrappedRecipeList([]), "WebAPIWrapper")
    }
  }
}

fn get_dispatcher_return_decoder() -> decode.Decoder(WebAPIWrapper) {
  use dispatcher_return <- decode.field(
    "value",
    dispatcher_return_decoder.get_dispatcher_return_decoder(),
  )

  decode.success(WrappedResponse(dispatcher_return))
}

fn get_acknowledgement_decoder() -> decode.Decoder(WebAPIWrapper) {
  use acknowledgement <- decode.field(
    "value",
    acknowledgement_decoder.get_acknowledgement_decoder(),
  )

  decode.success(WrappedAcknowledgement(acknowledgement))
}

fn get_recipe_list_decoder() -> decode.Decoder(WebAPIWrapper) {
  let entry_decoder = {
    use description <- decode.field("desc", decode.string)
    use specification <- decode.field("spec", decode.string)

    decode.success(RecipeEntry(description:, specification:))
  }

  use entry_list <- decode.field("value", decode.list(of: entry_decoder))

  decode.success(WrappedRecipeList(entry_list))
}

fn get_recipe_stats_decoder() -> decode.Decoder(WebAPIWrapper) {
  let stats_instance_decoder = {
    use recipe_instance_id <- decode.field("instance_id", decode.string)
    use dictionary <- decode.field(
      "stats",
      decode.dict(decode.string, decode.int),
    )

    decode.success(RecipeInstanceStatistics(recipe_instance_id:, dictionary:))
  }

  use stats_instance <- decode.field("value", stats_instance_decoder)

  decode.success(WrappedRecipeStatistics(stats_instance))
}

fn get_deser_error_decoder() -> decode.Decoder(WebAPIWrapper) {
  use dispatcher_return <- decode.field(
    "value",
    dispatcher_return_decoder.get_dispatcher_return_decoder(),
  )

  let result =
    dispatcher_return |> ClientDeserializationError() |> WrappedError()

  decode.success(result)
}

fn get_gen_error_decoder() -> decode.Decoder(WebAPIWrapper) {
  use message <- decode.field("value", decode.string)

  decode.success(WrappedError(GeneralError(message)))
}
