import app/types/client_request.{type RequestSpecification}
import app/types/recipe.{type Argument, type Arguments, type RecipeInstanceID}
import app/types/service.{type ServiceReference}
import app/types/service_call.{
  type ClientRecipeState, type DispatcherReturn, type HydrationError,
  ClientResponseHydrationError, DispatcherReturnEndPointError,
  DispatcherReturnHydrationError, DispatcherReturnRecipeState,
  DispatcherReturnServiceCall, ServiceReturnRequest, ServiceReturnResult,
  ServiceState,
}
import gleam/json
import gleam/option.{type Option, None, Some}
import serde/client/argument/encoder as argument_encoder
import serde/client/request/encoder as request_encoder
import serde/client/service_reference/encoder as service_reference_encoder

/// Serialize the different dispatcher return values
pub fn encode(dispatcher_return: DispatcherReturn) -> String {
  dispatcher_return
  |> encode_dispatcher_return()
  |> json.to_string()
}

pub fn encode_dispatcher_return(
  dispatcher_return: DispatcherReturn,
) -> json.Json {
  case dispatcher_return {
    DispatcherReturnServiceCall(recipe_instance_id:, service_state:) ->
      encode_service_call(recipe_instance_id, service_state)

    DispatcherReturnRecipeState(recipe_instance_id:, recipe_state:) ->
      encode_recipe_state(recipe_instance_id, recipe_state)

    DispatcherReturnEndPointError(
      recipe_instance_id:,
      service:,
      description:,
      client_data:,
    ) ->
      encode_endpoint_error(
        recipe_instance_id,
        service,
        description,
        client_data,
      )

    DispatcherReturnHydrationError(
      recipe_instance_id:,
      error_type:,
      description:,
      client_data:,
    ) ->
      encode_hydration_error(
        recipe_instance_id,
        error_type,
        description,
        client_data,
      )
  }
}

fn encode_service_call(
  recipe_instance_id: RecipeInstanceID,
  service_state: service_call.ServiceState,
) -> json.Json {
  let ServiceState(service:, service_state:, service_return:, warning:) =
    service_state

  case service_return {
    ServiceReturnResult(result:) ->
      encode_result(recipe_instance_id, service, service_state, result, warning)

    ServiceReturnRequest(request:) ->
      encode_request(
        recipe_instance_id,
        service,
        service_state,
        request,
        warning,
      )
  }
}

fn encode_result(
  recipe_instance_id: RecipeInstanceID,
  service: ServiceReference,
  service_state: Option(Arguments),
  result: String,
  warning: Option(String),
) -> json.Json {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"result\",
  //     \"service\": {
  //         \"id\": \"1234\",
  //         \"name\": \"calc\"
  //     },
  //     \"state": [
  //       {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
  //       {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}}
  //     ],
  //     \"result\": \"44\",
  //     \"warning\": \"More than two operands provided\"
  // }"

  json.object([
    add_recipe_instance_id(recipe_instance_id),
    add_type("result"),
    add_service(service),
    add_argument_state(service_state),
    #("result", json.string(result)),
    add_warning(warning),
  ])
}

fn encode_request(
  recipe_instance_id: RecipeInstanceID,
  service: ServiceReference,
  service_state: Option(Arguments),
  request: RequestSpecification,
  warning: Option(String),
) -> json.Json {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"request\",
  //     \"service\": {
  //         \"id\": \"1234\",
  //         \"name\": \"calc\"
  //     },
  //     \"state": [
  //       {\"name\":\"test1\",\"value\":{\"type\":\"Int\",\"value\":33}},
  //       {\"name\":\"test2\",\"value\":{\"type\":\"Float\",\"value\":44.4}}
  //     ],
  //     \"spec\": {
  //         \"request\": {
  //             \"type\": \"text\",
  //             \"base\": \"String\",
  //             \"specialization\": {
  //               \"type\": \"explicit\",
  //               \"content\": [
  //                   \"+\",
  //                   \"-\"
  //               ]
  //             }
  //          },
  //         \"name\": \"operator\",
  //         \"required\": true,
  //         \"prompt\": \"The calculation operator (such as + or -)\"
  //     },
  //     \"warning\": \"More than two operands provided\"
  // }"

  json.object([
    add_recipe_instance_id(recipe_instance_id),
    add_type("request"),
    add_service(service),
    add_argument_state(service_state),
    #("spec", request_encoder.encode_fragment(request)),
    add_warning(warning),
  ])
}

fn encode_recipe_state(
  recipe_instance_id: RecipeInstanceID,
  recipe_state: ClientRecipeState,
) -> json.Json {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"state\",
  //     \"recipe_state\": \"requesting\"
  // }"

  json.object([
    add_recipe_instance_id(recipe_instance_id),
    add_type("state"),
    #("recipe_state", recipe_state_to_json(recipe_state)),
  ])
}

fn encode_endpoint_error(
  recipe_instance_id: RecipeInstanceID,
  service: ServiceReference,
  description: String,
  client_data: Option(Argument),
) -> json.Json {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"endpoint_error\",
  //     \"service\": {
  //         \"id\": \"1234\",
  //         \"name\": \"calc\"
  //     },
  //     \"endpoint_error\": {
  //         \"description\": \"An error has occurred\",
  //         \"client_data\": {\"name\": \"operand\", \"value\": {\"type\":\"Int\",\"value\":33}}
  //     }
  // }"

  json.object([
    add_recipe_instance_id(recipe_instance_id),
    add_type("endpoint_error"),
    add_service(service),
    #("endpoint_error", endpoint_error_to_json(description, client_data)),
  ])
}

fn encode_hydration_error(
  recipe_instance_id: RecipeInstanceID,
  error_type: HydrationError,
  description: String,
  client_data: String,
) -> json.Json {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"hydration_error\",
  //     \"hydration_error\": {
  //         \"error_type\": \"client_response_hydration_error\",
  //         \"description\": \"An error has occurred\",
  //         \"client_data\": \"some arbitrary string data perhaps JSON encoded\"
  //     }
  // }"

  json.object([
    add_recipe_instance_id(recipe_instance_id),
    add_type("hydration_error"),
    #(
      "hydration_error",
      webservice_error_to_json(error_type, description, client_data),
    ),
  ])
}

fn webservice_error_to_json(
  error_type: HydrationError,
  description: String,
  client_data: String,
) -> json.Json {
  // the double-encoded request data is just treated as a string
  json.object([
    #("error_type", error_to_json(error_type)),
    #("description", json.string(description)),
    #("client_data", json.string(client_data)),
  ])
}

fn endpoint_error_to_json(
  description: String,
  client_data: Option(Argument),
) -> json.Json {
  json.object([
    #("description", json.string(description)),
    #("client_data", client_argument_to_json(client_data)),
  ])
}

fn client_argument_to_json(client_data: Option(Argument)) -> json.Json {
  // {\"name\": \"operand\", \"value\": \"33\"}
  // or null when value is None
  case client_data {
    Some(argument) -> argument_encoder.encode_argument(argument)
    None -> json.null()
  }
}

fn error_to_json(error_type: HydrationError) -> json.Json {
  case error_type {
    // StateHydrationError -> "state_hydration_error"
    ClientResponseHydrationError -> "client_response_hydration_error"
  }
  |> json.string()
}

fn recipe_state_to_json(recipe_state: ClientRecipeState) -> json.Json {
  let encoded = case recipe_state {
    service_call.Pending -> "pending"
    service_call.Requesting -> "requesting"
    service_call.Stepping -> "stepping"
    service_call.Completing -> "completing"
    service_call.Suspending -> "suspending"
  }

  json.string(encoded)
}

fn add_recipe_instance_id(
  recipe_instance_id: RecipeInstanceID,
) -> #(String, json.Json) {
  #("recipe_instance_id", json.string(recipe_instance_id))
}

fn add_type(encoded_type: String) -> #(String, json.Json) {
  #("type", json.string(encoded_type))
}

fn add_service(service: ServiceReference) -> #(String, json.Json) {
  #("service", service_reference_encoder.encode_fragment(service))
}

fn add_argument_state(service_state: Option(Arguments)) -> #(String, json.Json) {
  #(
    "state",
    json.nullable(service_state, fn(args) { argument_encoder.encode(args) }),
  )
}

fn add_warning(warning: Option(String)) -> #(String, json.Json) {
  case warning {
    Some(description) -> #("warning", json.string(description))
    None -> #("warning", json.null())
  }
}
