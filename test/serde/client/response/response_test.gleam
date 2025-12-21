//// This is the response from the client
//// It consists of the service reference and an optional argument
//// The argument (if any) is the client's response to a request
//// from the current service provider

import app/types/client_response.{
  type ClientResponse, ArgumentSubmission, ClientQuery, ClientSubmitArgument,
  ClientSubmitRecipe, QueryTypeRecipeList, QueryTypeRecipeStatistics,
}
import app/types/recipe.{
  Argument, FloatValue, IntValue, SerializedValue, StringValue,
}
import app/types/service.{ServiceReference}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/client/response/decoder as client_response_decoder
import serde/client/response/encoder as client_response_encoder

const test_recipe_id = "some_recipe_id"

const test_recipe_instance_id = "some_recipe_instance_id"

const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub fn main() {
  gleeunit.main()
}

// ###############################################
// Decoding tests
// ###############################################

pub fn submit_recipe_client_response_test() {
  let client_response_json =
    "{
       \"type\": \"submit_recipe\",
       \"recipe\": \"calc\"
    }"

  check_decoded(client_response_json, ClientSubmitRecipe("calc"))
}

pub fn submit_argument_client_response_test() {
  let client_response_json = "{
     \"type\": \"submit_argument\",
     \"argument\": {
        \"recipe_id\": \"" <> test_recipe_id <> "\",
        \"recipe_instance_id\": \"" <> test_recipe_instance_id <> "\",
        \"service\": {
          \"name\": \"calc\",
          \"path\": \"com.examples.service_composer\"
        },
        \"response\": {
          \"name\":\"test\",
          \"value\": {
            \"type\":\"Serialized\",
            \"value\": \"33\"
          }
        }
      }
    }"

  check_decoded(
    client_response_json,
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: Some(Argument(name: "test", value: SerializedValue("33"))),
    )),
  )
}

pub fn query_recipe_stats_client_response_test() {
  let client_response_json = "{
     \"type\": \"query_recipe_stats\",
     \"recipe_instance_id\": \"" <> test_recipe_instance_id <> "\"
  }"

  check_decoded(
    client_response_json,
    ClientQuery(QueryTypeRecipeStatistics(test_recipe_instance_id)),
  )
}

pub fn query_recipes_client_response_test() {
  let client_response_json =
    "{
     \"type\": \"query_recipe_list\"
    }"

  check_decoded(client_response_json, ClientQuery(QueryTypeRecipeList))
}

// ###############################################
// Round-trip tests
// ###############################################

pub fn round_trip_submit_recipe_test() {
  run_round_trip(ClientSubmitRecipe("calc"))
}

pub fn round_trip_submit_argument_test() {
  run_round_trip(
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: None,
    )),
  )

  run_round_trip(
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: Some(Argument(name: "test", value: SerializedValue("33"))),
    )),
  )

  run_round_trip(
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: Some(Argument(name: "test", value: IntValue(33))),
    )),
  )

  run_round_trip(
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: Some(Argument(name: "test", value: FloatValue(44.4))),
    )),
  )

  run_round_trip(
    ClientSubmitArgument(ArgumentSubmission(
      recipe_id: test_recipe_id,
      recipe_instance_id: test_recipe_instance_id,
      service: calc_service_reference,
      response: Some(Argument(name: "test", value: StringValue("33"))),
    )),
  )
}

pub fn round_trip_query_recipe_stats_test() {
  run_round_trip(
    ClientQuery(QueryTypeRecipeStatistics(test_recipe_instance_id)),
  )
}

pub fn round_trip_query_recipe_list_test() {
  run_round_trip(ClientQuery(QueryTypeRecipeList))
}

fn run_round_trip(client_response: ClientResponse) -> Nil {
  client_response
  |> client_response_encoder.encode()
  |> client_response_decoder.decode_json()
  |> should.be_ok()
  |> should.equal(client_response)
}

fn check_decoded(client_response_json: String, expected: ClientResponse) -> Nil {
  client_response_json
  |> client_response_decoder.decode_json()
  |> should.be_ok()
  |> should.equal(expected)
}
