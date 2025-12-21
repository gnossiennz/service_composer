//// Deserialize the dispatcher returns for logging and testing purposes only
//// Otherwise, only the client needs to decode JSON of this schema

import app/types/service_call.{
  type DispatcherReturn, ClientResponseHydrationError,
  DispatcherReturnEndPointError, DispatcherReturnHydrationError,
  DispatcherReturnRecipeState, DispatcherReturnServiceCall, ServiceReturnRequest,
  ServiceReturnResult, ServiceState,
}
import gleam/dynamic/decode
import gleam/json
import serde/client/argument/decoder as argument_decoder
import serde/client/request/decoder as request_decoder
import serde/client/service_reference/decoder as service_reference_decoder

pub fn decode(json_string: String) -> Result(DispatcherReturn, json.DecodeError) {
  let decoder = get_dispatcher_return_decoder()

  json.parse(from: json_string, using: decoder)
}

pub fn get_dispatcher_return_decoder() -> decode.Decoder(DispatcherReturn) {
  use recipe_instance_id <- decode.field("recipe_instance_id", decode.string)
  use response_type <- decode.field("type", decode.string)

  case response_type {
    "request" -> get_request_decoder(recipe_instance_id)
    "result" -> get_result_decoder(recipe_instance_id)
    "state" -> get_recipe_state_decoder(recipe_instance_id)
    "endpoint_error" -> get_endpoint_error_decoder(recipe_instance_id)
    "hydration_error" -> get_hydration_error_decoder(recipe_instance_id)
    _ -> {
      let return =
        DispatcherReturnHydrationError(
          recipe_instance_id:,
          error_type: ClientResponseHydrationError,
          description: "Unknown serialized response type",
          client_data: "",
        )

      decode.failure(return, "DispatcherReturn")
    }
  }
}

fn get_result_decoder(
  recipe_instance_id: String,
) -> decode.Decoder(DispatcherReturn) {
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

  use service <- decode.field(
    "service",
    service_reference_decoder.get_service_decoder(),
  )
  use argument_state <- decode.field(
    "state",
    argument_decoder.get_arguments_decoder(),
  )
  use result <- decode.field("result", decode.string)
  use warning <- decode.field("warning", decode.optional(decode.string))

  decode.success(DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state: argument_state,
      service_return: ServiceReturnResult(result),
      warning:,
    ),
  ))
}

fn get_request_decoder(
  recipe_instance_id: String,
) -> decode.Decoder(DispatcherReturn) {
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
  //     \"warning\": null
  // }"

  use service <- decode.field(
    "service",
    service_reference_decoder.get_service_decoder(),
  )
  use argument_state <- decode.field(
    "state",
    argument_decoder.get_arguments_decoder(),
  )
  use request <- decode.field(
    "spec",
    request_decoder.get_request_specification_decoder(),
  )
  use warning <- decode.field("warning", decode.optional(decode.string))

  decode.success(DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state: argument_state,
      service_return: ServiceReturnRequest(request),
      warning:,
    ),
  ))
}

fn get_recipe_state_decoder(
  recipe_instance_id: String,
) -> decode.Decoder(DispatcherReturn) {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"state\",
  //     \"recipe_state\": \"requesting\"
  // }"

  let recipe_state_decoder = {
    use decoded_string <- decode.then(decode.string)
    case decoded_string {
      "pending" -> decode.success(service_call.Pending)
      "requesting" -> decode.success(service_call.Requesting)
      "stepping" -> decode.success(service_call.Stepping)
      "completing" -> decode.success(service_call.Completing)
      "suspending" -> decode.success(service_call.Suspending)
      _ -> decode.failure(service_call.Pending, "ClientRecipeState")
    }
  }

  // use recipe_id <- decode.field("recipe_id", decode.string)
  // use recipe_desc <- decode.field("recipe_desc", decode.string)
  use recipe_state <- decode.field("recipe_state", recipe_state_decoder)

  decode.success(DispatcherReturnRecipeState(recipe_instance_id:, recipe_state:))
}

fn get_endpoint_error_decoder(
  recipe_instance_id: String,
) -> decode.Decoder(DispatcherReturn) {
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

  use service <- decode.field(
    "service",
    service_reference_decoder.get_service_decoder(),
  )
  let error_decoder = {
    use description <- decode.field("description", decode.string)
    use client_data <- decode.field(
      "client_data",
      decode.optional(argument_decoder.get_argument_decoder()),
    )

    decode.success(#(description, client_data))
  }

  use #(description, client_data) <- decode.field(
    "endpoint_error",
    error_decoder,
  )

  decode.success(DispatcherReturnEndPointError(
    recipe_instance_id:,
    service:,
    description:,
    client_data:,
  ))
}

fn get_hydration_error_decoder(
  recipe_instance_id: String,
) -> decode.Decoder(DispatcherReturn) {
  // "{
  //     \"recipe_instance_id": \"recipe:abcd-efg-hijk\",
  //     \"type\": \"hydration_error\",
  //     \"hydration_error\": {
  //         \"error_type\": \"client_response_hydration_error\",
  //         \"description\": \"An error has occurred\",
  //         \"client_data\": \"some arbitrary string data perhaps JSON encoded\"
  //     }
  // }"

  let error_decoder = {
    let error_type_decoder = {
      use decoded_string <- decode.then(decode.string)
      case decoded_string {
        // "state_hydration_error" -> decode.success(StateHydrationError)
        "client_response_hydration_error" ->
          decode.success(ClientResponseHydrationError)

        _ -> decode.failure(ClientResponseHydrationError, "HydrationError")
      }
    }

    use error_type <- decode.field("error_type", error_type_decoder)
    use description <- decode.field("description", decode.string)
    use client_data <- decode.field("client_data", decode.string)

    decode.success(#(error_type, description, client_data))
  }

  use #(error_type, description, client_data) <- decode.field(
    "hydration_error",
    error_decoder,
  )

  decode.success(DispatcherReturnHydrationError(
    recipe_instance_id:,
    error_type:,
    description:,
    client_data:,
  ))
}
