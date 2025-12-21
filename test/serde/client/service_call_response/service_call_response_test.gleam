//// Test decoding of the different types of service response
//// (includes the request response, result response and error responses)
//// These JSON documents are what the client sees (and builds a UI from)
//// and include the service reference, the service response
//// and any warning returned from the service

import app/types/client_request.{RequestSpecification}
import app/types/definition.{
  BaseNumberFloat, BaseTextString, Bytes, NumberEntity, NumberRangePositive,
  RestrictedNumberNamed, RestrictedTextExplicit, Scalar, TextEntity,
}
import app/types/recipe.{Argument, IntValue}
import app/types/service.{ServiceReference}
import app/types/service_call.{
  type ServiceCallResponse, ClientResponseHydrationError,
  DispatcherReturnEndPointError, DispatcherReturnHydrationError,
  DispatcherReturnRecipeState, DispatcherReturnServiceCall, ServiceCallResponse,
  ServiceReturnRequest, ServiceReturnResult, ServiceState,
}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import serde/client/service_call_response/decoder as service_call_response_decoder
import serde/client/service_call_response/encoder as service_call_response_encoder

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

const some_service_provider_reference = ServiceReference(
  name: "some_service_provider",
  path: "com.examples.some_service_provider",
)

pub fn main() {
  gleeunit.main()
}

// ###############################################
// Decoding tests
// ###############################################

pub fn request_type_response_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"some_service_provider test1:33 test2:44.4\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
          \"type\": \"request\",
          \"service\": {
              \"name\": \"some_service_provider\",
              \"path\": \"com.examples.some_service_provider\"
          },
          \"state\": [
            {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
            {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}}
          ],
          \"spec\": {
              \"request\": {
                  \"type\": \"text\",
                  \"base\": \"String\",
                  \"specialization\": {
                    \"type\": \"explicit\",
                    \"content\": [
                        \"large\",
                        \"small\"
                    ]
                  }
              },
              \"name\": \"test3\",
              \"required\": true,
              \"prompt\": \"Either 'large' or 'small'\"
          },
          \"warning\": \"More than two operands provided\"
        }
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "some_service_provider test1:33 test2:44.4",
    dispatcher_return: DispatcherReturnServiceCall(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      service_state: ServiceState(
        service: some_service_provider_reference,
        service_state: Some([
          Argument(name: "test1", value: recipe.IntValue(33)),
          Argument(name: "test2", value: recipe.FloatValue(44.4)),
        ]),
        service_return: ServiceReturnRequest(request: RequestSpecification(
          request: Bytes(TextEntity(
            BaseTextString,
            Some(RestrictedTextExplicit(["large", "small"])),
          )),
          name: "test3",
          required: True,
          prompt: "Either 'large' or 'small'",
        )),
        warning: Some("More than two operands provided"),
      ),
    ),
  ))
}

pub fn result_type_response_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"some_service_provider test1:33 test2:44.4\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
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

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "some_service_provider test1:33 test2:44.4",
    dispatcher_return: DispatcherReturnServiceCall(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      service_state: ServiceState(
        service: some_service_provider_reference,
        service_state: Some([
          Argument(name: "test1", value: recipe.IntValue(33)),
          Argument(name: "test2", value: recipe.FloatValue(44.4)),
        ]),
        service_return: ServiceReturnResult(result: "44"),
        warning: Some("More than two operands provided"),
      ),
    ),
  ))
}

pub fn result_type_response_no_state_args_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"some_service_provider test1:33 test2:44.4\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
          \"type\": \"result\",
          \"service\": {
              \"name\": \"some_service_provider\",
              \"path\": \"com.examples.some_service_provider\"
          },
          \"state\": null,
          \"result\": \"44\",
          \"warning\": \"More than two operands provided\"
        }
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "some_service_provider test1:33 test2:44.4",
    dispatcher_return: DispatcherReturnServiceCall(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      service_state: ServiceState(
        service: some_service_provider_reference,
        service_state: None,
        service_return: ServiceReturnResult(result: "44"),
        warning: Some("More than two operands provided"),
      ),
    ),
  ))
}

pub fn recipe_state_type_response_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"calc operator:*\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
          \"type\": \"state\",
          \"recipe_state\": \"pending\"
        }
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "calc operator:*",
    dispatcher_return: DispatcherReturnRecipeState(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      recipe_state: service_call.Pending,
    ),
  ))
}

pub fn endpoint_error_response_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"calc\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
          \"type\": \"endpoint_error\",
          \"service\": {
              \"name\": \"calc\",
              \"path\": \"com.examples.service_composer\"
          },
          \"endpoint_error\": {
              \"description\": \"An error has occurred\",
              \"client_data\": {\"name\": \"operand\", \"value\": {\"type\":\"Int\",\"value\":33}}
          }
        }
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "calc",
    dispatcher_return: DispatcherReturnEndPointError(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      service: calc_service_reference,
      description: "An error has occurred",
      client_data: Some(Argument(name: "operand", value: IntValue(33))),
    ),
  ))
}

pub fn hydration_error_response_test() {
  let service_response_json =
    "{
        \"recipe_id\": \"recipe:abcd-efg-hijk\",
        \"recipe_desc\": \"calc\",
        \"dispatcher_return\": {
          \"recipe_instance_id\": \"recipe_instance:abcd-efg-hijk\",
          \"type\": \"hydration_error\",
          \"hydration_error\": {
              \"error_type\": \"client_response_hydration_error\",
              \"description\": \"An error has occurred\",
              \"client_data\": \"some arbitrary string data perhaps JSON encoded\"
          }
        }
    }"

  service_response_json
  |> get_decoded()
  |> should.equal(ServiceCallResponse(
    recipe_id: "recipe:abcd-efg-hijk",
    recipe_desc: "calc",
    dispatcher_return: DispatcherReturnHydrationError(
      recipe_instance_id: "recipe_instance:abcd-efg-hijk",
      error_type: ClientResponseHydrationError,
      description: "An error has occurred",
      client_data: "some arbitrary string data perhaps JSON encoded",
    ),
  ))
}

// ###############################################
// Round-trip tests
// ###############################################

pub fn round_trip_request_test() {
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "some_service_provider test1:33 test2:44.4",
      dispatcher_return: DispatcherReturnServiceCall(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        service_state: ServiceState(
          service: some_service_provider_reference,
          service_state: Some([
            Argument(name: "test1", value: recipe.IntValue(33)),
            Argument(name: "test2", value: recipe.FloatValue(44.4)),
          ]),
          service_return: ServiceReturnRequest(request: RequestSpecification(
            request: Bytes(TextEntity(
              BaseTextString,
              Some(RestrictedTextExplicit(["large", "small"])),
            )),
            name: "test3",
            required: True,
            prompt: "Either 'large' or 'small'",
          )),
          warning: Some("More than two operands provided"),
        ),
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

pub fn round_trip_result_test() {
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "some_service_provider test1:33 test2:44.4",
      dispatcher_return: DispatcherReturnServiceCall(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        service_state: ServiceState(
          service: some_service_provider_reference,
          service_state: Some([
            Argument(name: "test1", value: recipe.IntValue(33)),
            Argument(name: "test2", value: recipe.FloatValue(44.4)),
          ]),
          service_return: ServiceReturnResult(result: "44"),
          warning: Some("More than two operands provided"),
        ),
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

pub fn round_trip_result_no_state_args_test() {
  // before the first request, the service state (arguments) may be None
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "some_service_provider",
      dispatcher_return: DispatcherReturnServiceCall(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        service_state: ServiceState(
          service: some_service_provider_reference,
          service_state: None,
          service_return: ServiceReturnRequest(request: RequestSpecification(
            name: "arg",
            request: Scalar(NumberEntity(
              BaseNumberFloat,
              Some(RestrictedNumberNamed(NumberRangePositive)),
            )),
            prompt: "Provide an argument",
            required: True,
          )),
          warning: Some("More than two operands provided"),
        ),
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

pub fn round_trip_recipe_state_test() {
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "calc operator:*",
      dispatcher_return: DispatcherReturnRecipeState(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        recipe_state: service_call.Pending,
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

pub fn round_trip_endpoint_error_test() {
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "calc",
      dispatcher_return: DispatcherReturnEndPointError(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        service: calc_service_reference,
        description: "An error has occurred",
        client_data: Some(Argument(name: "operand", value: IntValue(33))),
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

pub fn round_trip_hydration_error_test() {
  let service_response =
    ServiceCallResponse(
      recipe_id: "recipe:abcd-efg-hijk",
      recipe_desc: "calc",
      dispatcher_return: DispatcherReturnHydrationError(
        recipe_instance_id: "recipe_instance:abcd-efg-hijk",
        error_type: ClientResponseHydrationError,
        description: "An error has occurred",
        client_data: "some arbitrary string data perhaps JSON encoded",
      ),
    )

  service_response
  |> service_call_response_encoder.encode()
  |> get_decoded()
  |> should.equal(service_response)
}

// ###############################################
// Utilities
// ###############################################

fn get_decoded(json_string: String) -> ServiceCallResponse {
  json_string
  |> service_call_response_decoder.decode()
  |> should.be_ok()
}
