import gleam/function
import gleam/json
import gleam/list
import serde/acknowledgement/encoder as acknowledgement_encoder
import serde/client/dispatcher_return/encoder as dispatcher_return_encoder
import types/web_api_wrapper.{
  type WebAPIWrapper, ClientDeserializationError, GeneralError,
  WrappedAcknowledgement, WrappedError, WrappedRecipeList,
  WrappedRecipeStatistics, WrappedResponse,
}

pub fn encode(wrapped: WebAPIWrapper) -> String {
  let encoded = case wrapped {
    WrappedResponse(dispatcher_return) -> {
      dispatcher_return
      |> dispatcher_return_encoder.encode_dispatcher_return()
      |> make_wrapped_object(with_type: "response")
    }
    WrappedAcknowledgement(acknowledgement) -> {
      acknowledgement
      |> acknowledgement_encoder.encode_acknowledgement()
      |> make_wrapped_object(with_type: "ack")
    }
    WrappedRecipeList(recipe_entry_list) -> {
      recipe_entry_list
      |> list.map(fn(entry) {
        [
          #("desc", json.string(entry.description)),
          #("spec", json.string(entry.specification)),
        ]
      })
      |> json.array(of: json.object)
      |> make_wrapped_object(with_type: "recipe_list")
    }
    WrappedRecipeStatistics(instance_stats) -> {
      json.object([
        #("instance_id", json.string(instance_stats.recipe_instance_id)),
        #(
          "stats",
          instance_stats.dictionary
            |> json.dict(function.identity, json.int),
        ),
      ])
      |> make_wrapped_object(with_type: "recipe_stats")
    }
    WrappedError(error) -> {
      case error {
        GeneralError(message) ->
          message
          |> json.string
          |> make_wrapped_object(with_type: "gen_error")
        ClientDeserializationError(dispatcher_return) ->
          dispatcher_return
          |> dispatcher_return_encoder.encode_dispatcher_return()
          |> make_wrapped_object(with_type: "deser_error")
      }
    }
  }

  encoded |> json.to_string
}

fn make_wrapped_object(
  wrapped: json.Json,
  with_type wrapped_type: String,
) -> json.Json {
  json.object([#("type", json.string(wrapped_type)), #("value", wrapped)])
}
