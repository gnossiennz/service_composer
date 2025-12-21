import app/types/client_request.{RequestSpecification}
import app/types/definition.{
  BaseTextString, Bytes, RestrictedTextExplicit, TextEntity,
}
import app/types/recipe.{Argument, FloatValue, IntValue}
import app/types/service.{ServiceReference}
import app/types/service_call.{
  DispatcherReturnEndPointError, DispatcherReturnServiceCall,
  ServiceReturnRequest, ServiceReturnResult, ServiceState,
}
import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/wrapped/decoder as wrapped_decoder
import serde/wrapped/encoder as wrapped_encoder
import types/web_api_acknowledgement.{ReceivedNewRecipe, WebAPIAcknowledgement}
import types/web_api_wrapper.{
  type WebAPIWrapper, ClientDeserializationError, GeneralError, RecipeEntry,
  RecipeInstanceStatistics, WrappedAcknowledgement, WrappedError,
  WrappedRecipeList, WrappedRecipeStatistics, WrappedResponse,
}

const some_service_reference = ServiceReference(
  name: "some_service_provider",
  path: "com.examples.some_service_provider",
)

const dispatcher_return_result = DispatcherReturnServiceCall(
  recipe_instance_id: "wrapped_test_recipe_iid",
  service_state: ServiceState(
    service: some_service_reference,
    service_state: Some(
      [Argument("test1", IntValue(33)), Argument("test2", FloatValue(44.4))],
    ),
    service_return: ServiceReturnResult(result: "44"),
    warning: Some("More than two operands provided"),
  ),
)

const dispatcher_return_request = DispatcherReturnServiceCall(
  recipe_instance_id: "wrapped_test_recipe_iid",
  service_state: ServiceState(
    service: some_service_reference,
    service_state: None,
    service_return: ServiceReturnRequest(
      RequestSpecification(
        Bytes(
          TextEntity(
            BaseTextString,
            Some(RestrictedTextExplicit(["+", "-", "*", "/"])),
          ),
        ),
        "operator",
        True,
        "Provide a calculation operator (one of: +, -, * or /)",
      ),
    ),
    warning: None,
  ),
)

const acknowledgement = WebAPIAcknowledgement(
  recipe_id: "some recipe id",
  recipe_instance_id: "some recipe instance id",
  ack_type: ReceivedNewRecipe,
  warning: Some("test"),
)

const recipe_list = [
  RecipeEntry("first", "1st"),
  RecipeEntry("second", "2nd"),
  RecipeEntry("third", "3rd"),
]

const dispatcher_return_error = DispatcherReturnEndPointError(
  recipe_instance_id: "wrapped_test_recipe_iid",
  service: some_service_reference,
  description: "An error has occurred",
  client_data: Some(Argument(name: "operand", value: IntValue(33))),
)

const recipe_statistics = [
  #("first", 13),
  #("second", 15),
  #("third", 17),
]

pub fn main() {
  gleeunit.main()
}

// ###############################################
// Decoding tests
// ###############################################

pub fn wrapped_response_request_test() {
  let wrapped_response =
    "{
      \"type\":\"response\",
      \"value\": {
        \"recipe_instance_id\":\"wrapped_test_recipe_iid\",
        \"type\":\"request\",
        \"service\": {
          \"name\":\"some_service_provider\",
          \"path\":\"com.examples.some_service_provider\"
        },
        \"state\":null,
        \"spec\": {
          \"request\": {
            \"type\":\"text\",
            \"base\":\"String\",
            \"specialization\": {
              \"type\":\"explicit\",
              \"content\":[\"+\",\"-\",\"*\",\"/\"]
            }
          },
          \"name\":\"operator\",
          \"required\":true,
          \"prompt\":\"Provide a calculation operator (one of: +, -, * or /)\"
        },
        \"warning\":null
      }
    }"

  wrapped_response
  |> get_decoded()
  |> should.equal(WrappedResponse(dispatcher_return_request))
}

pub fn wrapped_response_result_test() {
  let wrapped_response =
    "{
      \"type\":\"response\",
      \"value\": {
          \"recipe_instance_id\": \"wrapped_test_recipe_iid\",
          \"type\": \"result\",
          \"service\": {
              \"name\": \"some_service_provider\",
              \"path\": \"com.examples.some_service_provider\"
          },
          \"state\": [
            {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
            {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}}
          ],
          \"result\": \"44\",
          \"warning\": \"More than two operands provided\"
        }
    }"

  wrapped_response
  |> get_decoded()
  |> should.equal(WrappedResponse(dispatcher_return_result))
}

pub fn wrapped_acknowledgement_test() {
  let wrapped_acknowledgement =
    "{
      \"type\":\"ack\",
      \"value\": {
        \"recipe_id\":\"some recipe id\",
        \"recipe_iid\":\"some recipe instance id\",
        \"ack_type\":\"received_new_recipe\",
        \"warning\":\"test\"
      }
    }"

  wrapped_acknowledgement
  |> get_decoded()
  |> should.equal(WrappedAcknowledgement(acknowledgement))
}

pub fn wrapped_recipe_list_test() {
  let wrapped_recipe_list =
    "{
      \"type\":\"recipe_list\",
      \"value\": [
        {\"desc\":\"first\",\"spec\":\"1st\"},
        {\"desc\":\"second\",\"spec\":\"2nd\"},
        {\"desc\":\"third\",\"spec\":\"3rd\"}
      ]
    }"

  wrapped_recipe_list
  |> get_decoded()
  |> should.equal(WrappedRecipeList(recipe_list))
}

pub fn wrapped_recipe_stats_test() {
  let wrapped_recipe_stats =
    "{
      \"type\":\"recipe_stats\",
      \"value\": {
        \"instance_id\":\"some instance id\",
        \"stats\": {
          \"third\":17,
          \"second\":15,
          \"first\":13
        }
      }
    }"

  wrapped_recipe_stats
  |> get_decoded()
  |> should.equal(WrappedRecipeStatistics(make_instance_statistics()))
}

pub fn wrapped_deserialization_error_test() {
  let wrapped_deserialization_error =
    "{
      \"type\":\"deser_error\",
      \"value\": {
        \"recipe_instance_id\": \"wrapped_test_recipe_iid\",
        \"service\": {
          \"name\":\"some_service_provider\",
          \"path\":\"com.examples.some_service_provider\"
        },
        \"type\":\"endpoint_error\",
        \"endpoint_error\": {
          \"description\":\"An error has occurred\",
          \"client_data\": {
            \"name\":\"operand\",
            \"value\": {
              \"type\":\"Int\",
              \"value\":33
            }
          }
        }
      }
    }"

  wrapped_deserialization_error
  |> get_decoded()
  |> should.equal(
    WrappedError(ClientDeserializationError(dispatcher_return_error)),
  )
}

pub fn wrapped_general_error_test() {
  let wrapped_recipe_stats =
    "{
    \"type\":\"gen_error\",
    \"value\": \"An error message\"
    }"

  wrapped_recipe_stats
  |> get_decoded()
  |> should.equal(WrappedError(GeneralError("An error message")))
}

// ###############################################
// Round-trip tests
// ###############################################

pub fn round_trip_wrapped_response_test() {
  let tested = WrappedResponse(dispatcher_return_result)

  do_round_trip(tested)
}

pub fn round_trip_wrapped_acknowledgement_test() {
  let tested = WrappedAcknowledgement(acknowledgement)

  do_round_trip(tested)
}

pub fn round_trip_wrapped_recipe_list_test() {
  let tested = WrappedRecipeList(recipe_list)

  do_round_trip(tested)
}

pub fn round_trip_wrapped_recipe_stats_test() {
  let tested = WrappedRecipeStatistics(make_instance_statistics())

  do_round_trip(tested)
}

pub fn round_trip_wrapped_deserialization_error_test() {
  let tested = WrappedError(ClientDeserializationError(dispatcher_return_error))

  do_round_trip(tested)
}

pub fn round_trip_wrapped_general_error_test() {
  let tested = WrappedError(GeneralError("A round trip test"))

  do_round_trip(tested)
}

// ###############################################
// Utility functions
// ###############################################

fn do_round_trip(tested: WebAPIWrapper) -> Nil {
  tested
  |> wrapped_encoder.encode()
  |> get_decoded()
  |> should.equal(tested)
}

fn get_decoded(json_string: String) -> WebAPIWrapper {
  json_string
  |> wrapped_decoder.decode()
  |> should.be_ok()
}

fn make_instance_statistics() {
  RecipeInstanceStatistics(
    recipe_instance_id: "some instance id",
    dictionary: dict.from_list(recipe_statistics),
  )
}
