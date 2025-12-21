//// Encoding of the client response

import app/types/client_response.{
  type ClientResponse, ClientQuery, ClientSubmitArgument, ClientSubmitRecipe,
  QueryTypeRecipeList, QueryTypeRecipeStatistics,
}
import app/types/recipe.{type Argument}
import gleam/json
import gleam/option.{type Option, None, Some}
import serde/client/argument/encoder as argument_encoder
import serde/client/service_reference/encoder as service_reference_encoder

pub fn encode(response: ClientResponse) -> String {
  response
  |> encode_fragment()
  |> json.to_string
}

/// Return a JSON fragment that describes the client response to a request
pub fn encode_fragment(response: ClientResponse) -> json.Json {
  case response {
    ClientSubmitRecipe(recipe_desc:) -> {
      json.object([
        #("type", json.string("submit_recipe")),
        #("recipe", json.string(recipe_desc)),
      ])
    }
    ClientSubmitArgument(submission:) -> {
      json.object([
        #("type", json.string("submit_argument")),
        #(
          "argument",
          json.object([
            #("recipe_id", json.string(submission.recipe_id)),
            #("recipe_instance_id", json.string(submission.recipe_instance_id)),
            #(
              "service",
              service_reference_encoder.encode_fragment(submission.service),
            ),
            #("response", encode_argument_response(submission.response)),
          ]),
        ),
      ])
    }
    ClientQuery(query_type:) -> encode_client_query(query_type)
  }
}

fn encode_client_query(query_type: client_response.QueryType) -> json.Json {
  case query_type {
    QueryTypeRecipeList -> [#("type", json.string("query_recipe_list"))]
    QueryTypeRecipeStatistics(recipe_instance_id) -> {
      [
        #("type", json.string("query_recipe_stats")),
        #("recipe_instance_id", json.string(recipe_instance_id)),
      ]
    }
  }
  |> json.object()
}

fn encode_argument_response(optional_arg: Option(Argument)) -> json.Json {
  case optional_arg {
    Some(argument) -> argument_encoder.encode_argument(argument)
    None -> json.null()
  }
}
