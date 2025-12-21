import app/types/service_call.{type ServiceCallResponse, ServiceCallResponse}
import gleam/json
import serde/client/dispatcher_return/encoder as dispatcher_return_encoder

/// Serialize a service call response
pub fn encode(service_response: ServiceCallResponse) -> String {
  service_response
  |> encode_service_call_response()
  |> json.to_string()
}

pub fn encode_service_call_response(
  service_response: ServiceCallResponse,
) -> json.Json {
  let ServiceCallResponse(recipe_id:, recipe_desc:, dispatcher_return:) =
    service_response

  json.object([
    #("recipe_id", json.string(recipe_id)),
    #("recipe_desc", json.string(recipe_desc)),
    #(
      "dispatcher_return",
      dispatcher_return_encoder.encode_dispatcher_return(dispatcher_return),
    ),
  ])
}
