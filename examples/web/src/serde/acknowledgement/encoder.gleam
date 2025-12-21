//// Serialize a WebAPIAcknowledgement

import app/types/recipe.{type RecipeID, type RecipeInstanceID}
import gleam/json
import gleam/option.{type Option, None, Some}
import types/web_api_acknowledgement.{
  type AcknowledgementType, type WebAPIAcknowledgement, ReceivedClientUpdate,
  ReceivedNewRecipe, WebAPIAcknowledgement,
}

pub fn encode(acknowledgement: WebAPIAcknowledgement) -> String {
  acknowledgement
  |> encode_acknowledgement()
  |> json.to_string()
}

pub fn encode_acknowledgement(
  acknowledgement: WebAPIAcknowledgement,
) -> json.Json {
  let WebAPIAcknowledgement(
    recipe_id:,
    recipe_instance_id:,
    ack_type:,
    warning:,
  ) = acknowledgement

  encode_acknowledgement_fragment(
    recipe_id,
    recipe_instance_id,
    ack_type,
    warning,
  )
}

fn encode_acknowledgement_fragment(
  recipe_id: RecipeID,
  recipe_instance_id: RecipeInstanceID,
  ack_type: AcknowledgementType,
  warning: Option(String),
) -> json.Json {
  // "{
  //     \"recipe_id\": "recipe:abcd-efg-hijk",
  //     \"recipe_iid\": "recipe_instance:abcd-efg-hijk",
  //     \"ack_type\": \"received_client_update\",
  //     \"warning\": null
  // }"

  json.object([
    #("recipe_id", json.string(recipe_id)),
    #("recipe_iid", json.string(recipe_instance_id)),
    add_acknowledgement_type(ack_type),
    add_warning(warning),
  ])
}

fn add_acknowledgement_type(
  ack_type: AcknowledgementType,
) -> #(String, json.Json) {
  let encoded = case ack_type {
    ReceivedNewRecipe -> "received_new_recipe"
    ReceivedClientUpdate -> "received_client_update"
  }

  #("ack_type", json.string(encoded))
}

fn add_warning(warning: Option(String)) -> #(String, json.Json) {
  case warning {
    Some(description) -> #("warning", json.string(description))
    None -> #("warning", json.null())
  }
}
