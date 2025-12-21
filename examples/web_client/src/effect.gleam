import app/types/client_response.{
  type QueryType, ArgumentSubmission, ClientQuery, ClientSubmitArgument,
  ClientSubmitRecipe,
}
import app/types/recipe.{Argument, SerializedValue}
import gleam/dict
import gleam/option.{None, Some}
import gleam/result
import lustre/effect.{type Effect}
import lustre_websocket as ws
import serde/client/response/encoder as response_encoder
import types/interaction.{CurrentInteraction}
import types/message.{type Msg}
import types/model.{type Model, type RecipeInteractionInstance}

// ###################################################
// Functions that produce an effect
// ###################################################

pub fn send_query(model: Model, query_type: QueryType) -> Effect(Msg) {
  model.ws
  |> option.map(fn(socket) {
    let client_response = ClientQuery(query_type) |> response_encoder.encode()

    ws.send(socket, client_response)
  })
  |> option.unwrap(effect.none())
}

pub fn send_recipe(model: Model) -> Effect(Msg) {
  #(model.ws, model.selected_recipe)
  |> fn(required_args) {
    case required_args {
      #(Some(socket), Some(recipe_desc)) -> Some(#(socket, recipe_desc))
      _ -> None
    }
  }
  |> option.map(fn(required_args) {
    let #(socket, recipe_desc) = required_args

    let client_response =
      ClientSubmitRecipe(recipe_desc) |> response_encoder.encode()

    ws.send(socket, client_response)
  })
  |> option.unwrap(effect.none())
}

// ###################################################
// Per-instance effects
// ###################################################

pub fn send_response(model: Model, recipe_instance_id: String) -> Effect(Msg) {
  send(model, recipe_instance_id, send_response_impl)
}

fn send_response_impl(
  model: Model,
  instance: model.RecipeInteractionInstance,
) -> Effect(Msg) {
  // if the required arguments have been set then send the response
  // on the socket; otherwise, do nothing
  #(model.ws, instance.current_interaction)
  |> fn(required_args) {
    case required_args {
      #(
        Some(socket),
        Some(CurrentInteraction(service, request, Some(response), _, _)),
      ) -> Some(#(socket, instance.recipe_info, service, request, response))
      _ -> None
    }
  }
  |> option.map(fn(required_args) {
    let #(socket, recipe_info, service, request, response) = required_args
    let response_value =
      response
      |> SerializedValue()
      |> fn(value) { Argument(name: request.name, value:) }
      |> Some()
    let client_response =
      ClientSubmitArgument(ArgumentSubmission(
        recipe_id: recipe_info.recipe_id,
        recipe_instance_id: recipe_info.recipe_instance_id,
        service:,
        response: response_value,
      ))
      |> response_encoder.encode()

    ws.send(socket, client_response)
  })
  |> option.unwrap(effect.none())
}

// ###################################################
// Utility functions
// ###################################################

fn send(
  model: Model,
  recipe_instance_id: String,
  sender: fn(Model, RecipeInteractionInstance) -> Effect(Msg),
) -> Effect(Msg) {
  model
  |> get_interaction(recipe_instance_id)
  |> result.map(fn(instance) { sender(model, instance) })
  |> result.lazy_unwrap(fn() { effect.none() })
}

fn get_interaction(
  model: Model,
  recipe_instance_id: String,
) -> Result(RecipeInteractionInstance, Nil) {
  model.instance_dict
  |> dict.get(recipe_instance_id)
}
