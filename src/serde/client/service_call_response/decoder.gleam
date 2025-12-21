import app/types/service_call.{type ServiceCallResponse, ServiceCallResponse}
import gleam/dynamic/decode
import gleam/json
import serde/client/dispatcher_return/decoder as dispatcher_return_decoder

pub fn decode(
  json_string: String,
) -> Result(ServiceCallResponse, json.DecodeError) {
  let decoder = get_service_call_response_decoder()

  json.parse(from: json_string, using: decoder)
}

pub fn get_service_call_response_decoder() -> decode.Decoder(
  ServiceCallResponse,
) {
  use recipe_id <- decode.field("recipe_id", decode.string)
  use recipe_desc <- decode.field("recipe_desc", decode.string)
  use dispatcher_return <- decode.field(
    "dispatcher_return",
    dispatcher_return_decoder.get_dispatcher_return_decoder(),
  )

  decode.success(ServiceCallResponse(
    recipe_id:,
    recipe_desc:,
    dispatcher_return:,
  ))
}
