import app/types/client_request.{type RequestSpecification, RequestSpecification}
import app/types/definition.{
  BaseTextString, Bytes, RestrictedTextExplicit, TextEntity,
}
import app/types/recipe.{type RecipeInstanceID, Argument, FloatValue, IntValue}
import app/types/service.{ServiceReference}
import app/types/service_call.{
  DispatcherReturnServiceCall, ServiceReturnRequest, ServiceReturnResult,
  ServiceState,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should
import lustre_websocket.{type WebSocket, OnTextMessage}
import serde/wrapped/encoder as wrapped_encoder
import types/error.{type Error}
import types/interaction.{
  type CurrentInteraction, type PastInteraction, CurrentInteraction,
}
import types/message.{SocketReceivedData}
import types/model.{
  type Model, type RecipeEvolution, type RecipeInteractionInstance, Model,
  RecipeEvolution, RecipeInfo, RecipeInteractionInstance,
}
import types/web_api_acknowledgement.{type WebAPIAcknowledgement}
import types/web_api_wrapper.{
  type RecipeEntry, WrappedAcknowledgement, WrappedResponse,
}
import web_client.{update}

pub const recipe_id = "some_recipe_desc"

pub const recipe_instance_id = "recipe:abcd-efg-hijk"

pub const recipe_info = RecipeInfo(
  recipe_id: "some_recipe_id",
  recipe_instance_id: "some_instance_id",
  template: "some_template",
)

pub const service = ServiceReference(
  name: "some_service_provider",
  path: "com.examples.some_service_provider",
)

pub const service_state = Some(
  [Argument("test1", IntValue(33)), Argument("test2", FloatValue(44.4))],
)

pub const operator_request = RequestSpecification(
  request: Bytes(
    TextEntity(
      base: BaseTextString,
      specialization: Some(RestrictedTextExplicit(values: ["+", "-"])),
    ),
  ),
  name: "operator",
  required: True,
  prompt: "The calculation operator (such as + or -)",
)

pub const warning = "More than two operands provided"

pub const recipe_evolution = RecipeEvolution(
  recipe_instance_id:,
  recipe_desc: "some_service_provider test1:33 test2:44.4",
)

pub type ModelCompare {
  ModelCompare(before: Model, after: Model)
}

pub type ModelField {
  WebSocket
  RecipeList
  RecipeSelection
  InstanceDict
  Notifications
  Errors
}

pub type InstanceField {
  InstanceRecipeTemplate
  InstanceHistory
  InstanceStats
  InstanceNotifications
  InstanceCurrentInteraction
  InstancePastInteractions
  InstanceResult
  InstanceWarnings
}

pub type ModelDiff {
  WebSocketChange(Option(WebSocket))
  RecipeListChange(Option(List(RecipeEntry)))
  RecipeSelectionChange(Option(String))
  InstanceDictSizeChange(Int)
  NotificationsChange(List(String))
  ErrorsChange(List(Error))
  NewInstanceCreated(RecipeInstanceID)
  InstanceRecipeTemplateChange(String)
  InstanceHistoryChange(List(RecipeEvolution))
  InstanceStatsChange(List(Dict(String, Int)))
  InstanceNotificationsChange(List(String))
  InstanceCurrentInteractionChange(Option(CurrentInteraction))
  InstancePastInteractionsChange(List(PastInteraction))
  InstanceResultChange(Option(String))
  InstanceWarningsChange(List(String))
}

pub fn update_model_with(before_model: Model, msg: message.Msg) -> ModelCompare {
  let #(after_model, _) = update(before_model, msg)

  ModelCompare(before_model, after_model)
}

pub fn get_model_changes(change: ModelCompare) -> List(ModelDiff) {
  get_model_diffs(change.before, change.after)
}

pub fn get_instance_changes(
  change: ModelCompare,
  recipe_instance_id: RecipeInstanceID,
) -> List(ModelDiff) {
  // the before state COULD be None
  // the after state will NEVER be None
  // i.e. new instances can be added but they are never deleted
  let before_instance = get_instance(change.before, recipe_instance_id)
  let after_instance =
    get_instance(change.after, recipe_instance_id) |> should.be_some()

  case before_instance {
    None -> [NewInstanceCreated(recipe_instance_id)]
    Some(before_instance) -> get_instance_diffs(before_instance, after_instance)
  }
}

pub fn make_empty_model() {
  let instance_dict = [] |> dict.from_list()

  Model(None, None, None, instance_dict, False, [], [])
}

pub fn make_model(
  recipe_instance_id: RecipeInstanceID,
  with_interaction interaction: Option(CurrentInteraction),
) -> Model {
  let instance_dict =
    recipe_instance_id
    |> make_instance_dictionary(with_interaction: interaction)

  Model(None, None, None, instance_dict, False, [], [])
}

pub fn make_instance_dictionary(
  recipe_instance_id: RecipeInstanceID,
  with_interaction interaction: Option(CurrentInteraction),
) {
  #(recipe_instance_id, make_instance(with_interaction: interaction))
  |> list.wrap()
  |> dict.from_list()
}

fn make_instance(with_interaction interaction: Option(CurrentInteraction)) {
  RecipeInteractionInstance(
    recipe_info:,
    recipe_evolution: [],
    stats: [],
    notifications: [],
    current_interaction: interaction,
    past_interactions: [],
    result: None,
    warnings: [],
  )
}

pub fn make_interaction(request: RequestSpecification) {
  CurrentInteraction(
    service:,
    request:,
    response: None,
    response_sent: False,
    response_acknowledged: False,
  )
}

pub fn make_msg(
  wrapped_server_message: web_api_wrapper.WebAPIWrapper,
) -> message.Msg {
  wrapped_server_message
  |> wrapped_encoder.encode()
  |> OnTextMessage()
  |> SocketReceivedData()
}

pub fn make_request_msg(
  recipe_instance_id: RecipeInstanceID,
  request: RequestSpecification,
  warning: Option(String),
) -> message.Msg {
  WrappedResponse(DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state:,
      service_return: ServiceReturnRequest(request),
      warning:,
    ),
  ))
  |> make_msg()
}

pub fn make_result_msg(
  recipe_instance_id: RecipeInstanceID,
  value: String,
  warning: Option(String),
) -> message.Msg {
  WrappedResponse(DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service:,
      service_state:,
      service_return: ServiceReturnResult(value),
      warning: warning,
    ),
  ))
  |> make_msg()
}

pub fn make_acknowledgement_msg(
  acknowledgement: WebAPIAcknowledgement,
) -> message.Msg {
  acknowledgement |> WrappedAcknowledgement() |> make_msg()
}

// ###################################################
// Utility functions
// ###################################################

fn get_model_diffs(before: Model, after: Model) -> List(ModelDiff) {
  [WebSocket, RecipeList, RecipeSelection, InstanceDict, Notifications, Errors]
  |> list.fold([], fn(acc, field) {
    let #(before, after) = case field {
      WebSocket -> #(WebSocketChange(before.ws), WebSocketChange(after.ws))
      RecipeList -> #(
        RecipeListChange(before.recipe_list),
        RecipeListChange(after.recipe_list),
      )
      RecipeSelection -> #(
        RecipeSelectionChange(before.selected_recipe),
        RecipeSelectionChange(after.selected_recipe),
      )
      InstanceDict -> #(
        InstanceDictSizeChange(dict.size(before.instance_dict)),
        InstanceDictSizeChange(dict.size(after.instance_dict)),
      )
      Notifications -> #(
        NotificationsChange(before.notifications),
        NotificationsChange(after.notifications),
      )
      Errors -> #(ErrorsChange(before.errors), ErrorsChange(after.errors))
    }

    add_if_changed(acc, before, after)
  })
}

fn get_instance(
  model: Model,
  recipe_instance_id: RecipeInstanceID,
) -> Option(RecipeInteractionInstance) {
  model.instance_dict
  |> dict.get(recipe_instance_id)
  |> option.from_result()
}

fn get_instance_diffs(
  before: RecipeInteractionInstance,
  after: RecipeInteractionInstance,
) -> List(ModelDiff) {
  [
    InstanceRecipeTemplate,
    InstanceHistory,
    InstanceStats,
    InstanceNotifications,
    InstanceCurrentInteraction,
    InstancePastInteractions,
    InstanceResult,
    InstanceWarnings,
  ]
  |> list.fold([], fn(acc, field) {
    let #(before, after) = case field {
      InstanceRecipeTemplate -> #(
        InstanceRecipeTemplateChange(before.recipe_info.template),
        InstanceRecipeTemplateChange(after.recipe_info.template),
      )
      InstanceHistory -> #(
        InstanceHistoryChange(before.recipe_evolution),
        InstanceHistoryChange(after.recipe_evolution),
      )
      InstanceStats -> #(
        InstanceStatsChange(before.stats),
        InstanceStatsChange(after.stats),
      )
      InstanceNotifications -> #(
        InstanceNotificationsChange(before.notifications),
        InstanceNotificationsChange(after.notifications),
      )
      InstanceCurrentInteraction -> #(
        InstanceCurrentInteractionChange(before.current_interaction),
        InstanceCurrentInteractionChange(after.current_interaction),
      )
      InstancePastInteractions -> #(
        InstancePastInteractionsChange(before.past_interactions),
        InstancePastInteractionsChange(after.past_interactions),
      )
      InstanceResult -> #(
        InstanceResultChange(before.result),
        InstanceResultChange(after.result),
      )
      InstanceWarnings -> #(
        InstanceWarningsChange(before.warnings),
        InstanceWarningsChange(after.warnings),
      )
    }

    add_if_changed(acc, before, after)
  })
}

fn add_if_changed(
  acc: List(ModelDiff),
  before: ModelDiff,
  after: ModelDiff,
) -> List(ModelDiff) {
  case before == after {
    True -> acc
    False -> [after, ..acc]
  }
}
