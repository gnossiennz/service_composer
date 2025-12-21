import gleam/dynamic/decode
import gleam/json
import types/web_api_acknowledgement.{
  type WebAPIAcknowledgement, ReceivedClientUpdate, ReceivedNewRecipe,
  WebAPIAcknowledgement,
}

pub fn decode(
  json_string: String,
) -> Result(WebAPIAcknowledgement, json.DecodeError) {
  let decoder = get_acknowledgement_decoder()

  json.parse(from: json_string, using: decoder)
}

pub fn get_acknowledgement_decoder() -> decode.Decoder(WebAPIAcknowledgement) {
  // "{
  //     \"recipe_id\": "recipe:abcd-efg-hijk",
  //     \"recipe_iid\": "recipe_instance:abcd-efg-hijk",
  //     \"ack_type\": \"received_client_update\",
  //     \"warning\": null
  // }"

  let acknowledgement_type_decoder = {
    use decoded_string <- decode.then(decode.string)
    case decoded_string {
      "received_new_recipe" -> decode.success(ReceivedNewRecipe)
      "received_client_update" -> decode.success(ReceivedClientUpdate)
      _ -> decode.failure(ReceivedClientUpdate, "AcknowledgementType")
    }
  }

  use recipe_id <- decode.field("recipe_id", decode.string)
  use recipe_instance_id <- decode.field("recipe_iid", decode.string)
  use ack_type <- decode.field("ack_type", acknowledgement_type_decoder)
  use warning <- decode.field("warning", decode.optional(decode.string))

  decode.success(WebAPIAcknowledgement(
    recipe_id:,
    recipe_instance_id:,
    ack_type:,
    warning:,
  ))
}
