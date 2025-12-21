import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/acknowledgement/decoder as acknowledgement_decoder
import serde/acknowledgement/encoder as acknowledgement_encoder
import types/web_api_acknowledgement.{
  type WebAPIAcknowledgement, ReceivedClientUpdate, ReceivedNewRecipe,
  WebAPIAcknowledgement,
}

pub fn main() {
  gleeunit.main()
}

pub fn acknowledgement_test() {
  let service_response_json =
    "{
      \"recipe_id\": \"some recipe id\",
      \"recipe_iid\": \"some recipe instance id\",
      \"ack_type\": \"received_client_update\",
      \"warning\": null
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(WebAPIAcknowledgement(
    recipe_id: "some recipe id",
    recipe_instance_id: "some recipe instance id",
    ack_type: ReceivedClientUpdate,
    warning: None,
  ))
}

pub fn round_trip_acknowledgement_test() {
  let return =
    WebAPIAcknowledgement(
      recipe_id: "some recipe id",
      recipe_instance_id: "some recipe instance id",
      ack_type: ReceivedNewRecipe,
      warning: Some("test"),
    )

  return
  |> acknowledgement_encoder.encode()
  |> get_decoded()
  |> should.equal(return)
}

fn get_decoded(json_string: String) -> WebAPIAcknowledgement {
  json_string
  |> acknowledgement_decoder.decode()
  |> should.be_ok()
}
