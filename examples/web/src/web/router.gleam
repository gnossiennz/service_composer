import app/engine/dispatcher.{
  type DispatcherServiceMessage, AddRecipe, QueryStatus, ReceiveClientUpdate,
}
import app/engine/dispatcher_store
import app/types/client_response.{
  type ArgumentSubmission, type ClientResponse, ClientQuery,
  ClientSubmitArgument, ClientSubmitRecipe,
}
import app/types/recipe.{type Recipe, type RecipeID, type RecipeInstanceID}
import app/types/service.{type FullyQualifiedServiceName, type ServiceName}
import app/types/service_call.{type ServiceCallResponse}
import gleam/bytes_tree.{type BytesTree}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/http.{type Header}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import glisten/socket
import mist.{type Connection, type ResponseData, type WebsocketConnection}
import recipe/create as recipe_creator
import serde/client/response/decoder as response_decoder
import serde/error/json as json_utilities
import serde/wrapped/encoder as wrapped_response_encoder
import types/web_api_acknowledgement.{
  type AcknowledgementType, ReceivedClientUpdate, ReceivedNewRecipe,
  WebAPIAcknowledgement,
}
import types/web_api_wrapper.{
  type WebAPIError, type WebAPIWrapper, GeneralError, RecipeEntry,
  WrappedAcknowledgement, WrappedError, WrappedRecipeList,
  WrappedRecipeStatistics, WrappedResponse,
}
import web/context.{type Context, Context}
import youid/uuid

// TODO store these somewhere
const known_recipes = [
  RecipeEntry("Simple calc", "calc"),
  RecipeEntry("Calc with plus operator", "calc operator:+"),
  RecipeEntry(
    "Square root of 3x + 2",
    "sqrt arg:(calc operator:+ operand1:(calc operator:* operand1:3) operand2:2)",
  ),
]

type SocketState {
  SocketState(
    services_dict: Dict(String, String),
    dispatcher: Name(DispatcherServiceMessage),
    receiving_subject: Subject(ServiceCallResponse),
  )
}

pub type MessageUpdate {
  ServiceMessageUpdate(ServiceCallResponse)
}

type SubmissionError {
  SocketSubmissionError(reason: socket.SocketReason)
  OtherSubmissionError(desc: String)
}

pub fn handle_request(
  request: Request(Connection),
  context: Context,
) -> Response(ResponseData) {
  case request.path_segments(request) {
    ["ws"] -> {
      // client messages arriving on the socket are handled
      // by handle_submission
      mist.websocket(
        request:,
        on_init: initialise_socket(_, context),
        on_close: fn(_state) {
          echo "socket says goodbye!"
          Nil
        },
        handler: handle_ws_message,
      )
    }

    _ -> make_response(404, None, bytes_tree.new())
  }
}

fn initialise_socket(
  _connection: WebsocketConnection,
  context: Context,
) -> #(SocketState, Option(_)) {
  let service_call_response_subject: Subject(ServiceCallResponse) =
    process.new_subject()

  let selector =
    process.new_selector()
    |> process.select_map(service_call_response_subject, fn(service_response) {
      ServiceMessageUpdate(service_response)
    })

  let Context(dispatcher_name, service_dictionary) = context

  // map the short (service reference) name to the fully qualified name
  let service_names_dict =
    service_dictionary
    |> dict.fold(dict.new(), fn(acc, fully_qualified_service_name, info) {
      dict.insert(
        acc,
        info.description.reference.name,
        fully_qualified_service_name,
      )
    })

  let state =
    SocketState(
      services_dict: service_names_dict,
      dispatcher: dispatcher_name,
      receiving_subject: service_call_response_subject,
    )

  #(state, Some(selector))
}

fn handle_ws_message(state, message, conn) {
  case message {
    mist.Text(maybe_client_response) -> {
      // echo #("Socket incoming text: ", maybe_client_response)
      // TODO log socket failure reason
      case handle_submission(conn, state, maybe_client_response) {
        Ok(Nil) -> mist.continue(state)
        Error(_err) -> mist.continue(state)
      }
    }
    mist.Binary(_) -> {
      mist.continue(state)
    }
    mist.Custom(ServiceMessageUpdate(service_response)) -> {
      // echo #("Web service received service update: ", service_response)

      let received_msg =
        service_response.dispatcher_return
        |> WrappedResponse()
        |> wrapped_response_encoder.encode()

      // TODO log socket failure reason
      let assert Ok(_) = mist.send_text_frame(conn, received_msg)

      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn handle_submission(
  conn: WebsocketConnection,
  state: SocketState,
  client_data: String,
) -> Result(Nil, SubmissionError) {
  let SocketState(services_dict, dispatcher_name, receiving_subject) = state

  // the client_data string is assumed to be JSON request data
  // (see ClientResponse decoder)
  case deserialize_client_response(client_data) {
    Ok(client_response) -> {
      case client_response {
        ClientSubmitRecipe(recipe_desc) ->
          handle_client_submit_recipe(
            conn,
            dispatcher_name,
            receiving_subject,
            recipe_desc,
            services_dict,
          )
        ClientSubmitArgument(submission) ->
          handle_client_submit_argument(conn, dispatcher_name, submission)
        ClientQuery(query_type) ->
          handle_client_query(conn, dispatcher_name, query_type)
      }
    }
    Error(error) -> {
      let error_description =
        error |> WrappedError() |> wrapped_response_encoder.encode()

      mist.send_text_frame(conn, error_description)
      |> result.map_error(fn(error) { SocketSubmissionError(error) })
    }
  }
}

fn handle_client_submit_recipe(
  conn: WebsocketConnection,
  dispatcher_name: Name(DispatcherServiceMessage),
  service_call_response_subject: Subject(ServiceCallResponse),
  recipe_desc: String,
  services: Dict(ServiceName, FullyQualifiedServiceName),
) -> Result(Nil, SubmissionError) {
  case submit_recipe(dispatcher_name, recipe_desc, services) {
    Ok(recipe) -> {
      // register this process to receive ServiceCallResponse updates
      // for this recipe instance

      dispatcher_name
      |> process.named_subject()
      |> process.send(dispatcher.RegisterListener(
        service_call_response_subject,
        recipe.iid,
      ))

      // acknowledge the recipe submission
      send_acknowledgement(conn, recipe.id, recipe.iid, ReceivedNewRecipe)
      |> result.map_error(fn(error) { SocketSubmissionError(error) })
    }
    Error(desc) -> Error(OtherSubmissionError(desc))
  }
}

fn handle_client_submit_argument(
  conn: WebsocketConnection,
  dispatcher_name: Name(DispatcherServiceMessage),
  submission: ArgumentSubmission,
) -> Result(Nil, SubmissionError) {
  // submission data includes a recipe instance ID, a service reference,
  // and optionally a submitted argument

  // send the submission on to the dispatcher
  dispatcher_name
  |> process.named_subject()
  |> process.send(ReceiveClientUpdate(submission))

  // ... and then send an acknowledgement to the client
  send_acknowledgement(
    conn,
    submission.recipe_id,
    submission.recipe_instance_id,
    ReceivedClientUpdate,
  )
  |> result.map_error(fn(error) { SocketSubmissionError(error) })
}

fn handle_client_query(
  conn: WebsocketConnection,
  dispatcher_name: Name(DispatcherServiceMessage),
  query_type: client_response.QueryType,
) -> Result(Nil, SubmissionError) {
  let query_response =
    case query_type {
      client_response.QueryTypeRecipeList -> get_recipe_list()
      client_response.QueryTypeRecipeStatistics(recipe_instance_id) ->
        get_recipe_statistics(recipe_instance_id, dispatcher_name)
    }
    |> wrapped_response_encoder.encode()

  mist.send_text_frame(conn, query_response)
  |> result.map_error(fn(error) { SocketSubmissionError(error) })
}

fn get_recipe_list() -> WebAPIWrapper {
  known_recipes
  |> WrappedRecipeList()
}

fn get_recipe_statistics(
  recipe_instance_id: RecipeInstanceID,
  dispatcher_name: Name(DispatcherServiceMessage),
) -> WebAPIWrapper {
  // TODO handle call timeout
  let recipe_state =
    dispatcher_name
    |> process.named_subject()
    |> process.call(50, QueryStatus(recipe_instance_id, _))

  let stats_dictionary =
    recipe_state.stats.dictionary
    |> dict.fold(dict.new(), fn(acc: Dict(String, Int), key, value) {
      dict.insert(acc, key_to_string(key), value)
    })

  recipe_instance_id
  |> web_api_wrapper.RecipeInstanceStatistics(stats_dictionary)
  |> WrappedRecipeStatistics()
}

fn submit_recipe(
  dispatcher_name: Name(DispatcherServiceMessage),
  recipe_desc: String,
  services: Dict(ServiceName, FullyQualifiedServiceName),
) -> Result(Recipe, String) {
  recipe_desc
  |> make_recipe_instance(services)
  |> result.map(fn(recipe) {
    // add the recipe
    dispatcher_name
    |> process.named_subject()
    |> process.send(AddRecipe(recipe))

    recipe
  })
}

fn send_acknowledgement(
  conn: WebsocketConnection,
  recipe_id: RecipeID,
  recipe_instance_id: RecipeInstanceID,
  acknowledgement_type: AcknowledgementType,
) -> Result(Nil, socket.SocketReason) {
  let acknowledgement =
    WebAPIAcknowledgement(
      recipe_id:,
      recipe_instance_id:,
      ack_type: acknowledgement_type,
      warning: None,
    )
    |> WrappedAcknowledgement()
    |> wrapped_response_encoder.encode()

  mist.send_text_frame(conn, acknowledgement)
}

fn deserialize_client_response(
  client_data: String,
) -> Result(ClientResponse, WebAPIError) {
  client_data
  |> response_decoder.decode_json()
  |> result.map_error(fn(decode_error) {
    // TODO check the client can decode this Json
    json.object([
      #("error", "Decode error: client data failed to decode" |> json.string),
      #("client_data", client_data |> json.string),
      #("details", json_utilities.describe_error(decode_error) |> json.string),
    ])
    |> json.to_string()
    |> GeneralError()
  })
}

// ###################################################
// Utilities
// ###################################################

fn make_response(
  code: Int,
  header: Option(Header),
  body: BytesTree,
) -> Response(ResponseData) {
  response.new(code)
  |> fn(response) {
    case header {
      Some(#(key, value)) -> response |> response.set_header(key, value)
      None -> response
    }
  }
  |> response.set_body(mist.Bytes(body))
}

fn make_recipe_instance(
  recipe_description: String,
  services: Dict(String, String),
) -> Result(Recipe, String) {
  recipe_creator.make_recipe(uuid.v4_string(), recipe_description, services)
}

fn key_to_string(key: dispatcher_store.RecipeStatisticsKey) -> String {
  case key {
    dispatcher_store.DispatchAcknowledgeKey -> "add_acknowledgements"
    dispatcher_store.ServiceResultKey -> "step_results"
    dispatcher_store.ClientRequestKey -> "requests"
    dispatcher_store.ClientResponseKey -> "responses"
  }
}
