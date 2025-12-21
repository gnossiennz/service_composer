import app/types/client_response.{QueryTypeRecipeList}
import app/types/recipe.{type RecipeInstanceID}
import effect as effector
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre
import lustre/effect as lustre_effect
import lustre/element.{type Element, text}
import lustre_websocket.{OnClose, OnOpen, OnTextMessage} as ws
import sketch.{type StyleSheet}
import sketch/css
import sketch/css/length.{px}
import sketch/lustre as sketch_lustre
import sketch/lustre/element/html as sketch_element
import style
import types/interaction.{
  type ServiceInteraction, ServiceInteractionCurrent, ServiceInteractionPast,
}
import types/message.{
  type Msg, SocketReceivedData, UserSelectedRecipe, UserSentResponse,
  UserSubmittedRecipe, UserToggledModelViewerInstanceDisplay,
  UserUpdatedResponse,
}
import types/model.{type Model, type RecipeInteractionInstance, Model}
import update/model as model_updater
import view/element as page_element
import view/interaction as interaction_element
import view/model_viewer

pub fn main() {
  let assert Ok(stylesheet) = sketch_lustre.setup()
  sketch.global(stylesheet, css.global("body", [css.margin(px(0))]))
  let app = lustre.application(init, update, view(_, stylesheet))
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_start_args) {
  #(
    Model(None, None, None, dict.new(), False, [], []),
    ws.init("http://127.0.0.1:3000/ws", SocketReceivedData),
  )
}

pub fn update(model, msg) {
  case msg {
    UserUpdatedResponse(instance_id, response) -> {
      // Update the response in the current interaction
      // Zero-length responses are ignored
      let updated_model = case string.length(response) {
        0 -> model
        _ -> model_updater.update_user_response(model, instance_id, response)
      }

      // echo #(
      //   "User updated response: ",
      //   updated_model |> get_interaction(instance_id),
      // )

      #(updated_model, lustre_effect.none())
    }
    UserSelectedRecipe(recipe_desc) -> {
      #(
        Model(..model, selected_recipe: Some(recipe_desc)),
        lustre_effect.none(),
      )
    }
    UserSubmittedRecipe -> {
      #(model, effector.send_recipe(model))
    }
    UserSentResponse(instance_id) -> {
      // Update the sent flag in the current interaction
      let updated_model =
        model_updater.update_sent_flag(model, instance_id, True)

      #(updated_model, effector.send_response(updated_model, instance_id))
    }
    UserToggledModelViewerInstanceDisplay -> {
      let new_flag_setting = !model.show_model_instances

      #(
        Model(..model, show_model_instances: new_flag_setting),
        lustre_effect.none(),
      )
    }
    SocketReceivedData(OnOpen(socket)) -> {
      let updated_model = Model(..model, ws: Some(socket))

      // immediately query for the recipe list
      #(updated_model, effector.send_query(updated_model, QueryTypeRecipeList))
    }
    SocketReceivedData(OnTextMessage(message)) -> {
      // Update the current interaction (assuming the message can be decoded)
      let updated_model = model_updater.handle_raw_message(model, message)

      #(updated_model, lustre_effect.none())
    }
    SocketReceivedData(OnClose(reason)) -> {
      echo #("Socket closed with reason: ", reason)

      #(
        model_updater.add_global_notification(model, "Socket closed"),
        lustre_effect.none(),
      )
    }
    SocketReceivedData(event) -> {
      echo event

      #(
        model_updater.add_global_notification(
          model,
          "Unexpected data received on socket",
        ),
        lustre_effect.none(),
      )
    }
  }
}

fn view(model: Model, stylesheet: StyleSheet) -> Element(Msg) {
  use <- sketch_lustre.render(stylesheet:, in: [sketch_lustre.node()])
  sketch_element.div(style.main_style(), [], [
    header_view(),
    hint_view(model),
    recipe_list_view(model),
    interactions_view(model),
    model_viewer_view(model),
  ])
}

fn header_view() -> Element(Msg) {
  sketch_element.header(style.header_style(), [], [
    sketch_element.h1_([], [text("Service Composer Demo")]),
  ])
}

fn hint_view(model: Model) -> Element(Msg) {
  let message = case dict.size(model.instance_dict) {
    0 -> "Select a recipe to get started:"
    _ -> "Multiple recipes can be run together (capped at 4 for this UI)"
  }

  sketch_element.section(style.top_level_container_style(), [], [
    sketch_element.h2_([], [text(message)]),
  ])
}

fn recipe_list_view(model) -> Element(Msg) {
  sketch_element.div(
    style.recipes_style(),
    [],
    page_element.show_recipe_list(model),
  )
}

fn interactions_view(model: Model) -> Element(Msg) {
  // this is the parent flex container for all interactions
  let instance_iterator = fn(
    instance_dict: Dict(RecipeInstanceID, RecipeInteractionInstance),
  ) {
    instance_dict
    |> dict.fold([], fn(acc, key, value) {
      [interactions_instance_view(key, value), ..acc]
    })
  }

  sketch_element.div(
    style.interactions_style(),
    [],
    model.instance_dict |> instance_iterator(),
  )
}

fn interactions_instance_view(
  instance_id: RecipeInstanceID,
  instance: RecipeInteractionInstance,
) -> Element(Msg) {
  // this is the flex container that holds all interactions
  // for a single recipe instance
  sketch_element.div(
    style.interactions_instance_style(),
    [],
    [
      page_element.show_recipe(instance_id, instance),
      page_element.show_instance_notifications(instance),
    ]
      |> list.append(view_service_interactions(instance_id, instance))
      |> page_element.maybe_show_result(instance),
  )
}

fn view_service_interactions(
  instance_id: RecipeInstanceID,
  instance: RecipeInteractionInstance,
) -> List(Element(Msg)) {
  instance
  |> merge_interactions()
  |> list.fold([], fn(acc, interaction) {
    [
      interaction_element.create_interaction_row(instance_id, interaction),
      ..acc
    ]
  })
}

fn model_viewer_view(model) -> Element(Msg) {
  sketch_element.div(
    style.model_viewer_style(),
    [],
    model_viewer.render_model(model),
  )
}

fn merge_interactions(
  instance: RecipeInteractionInstance,
) -> List(ServiceInteraction) {
  let past_interactions =
    instance.past_interactions
    |> list.map(fn(interaction) { ServiceInteractionPast(interaction) })

  case instance.current_interaction {
    Some(interaction) -> [
      ServiceInteractionCurrent(interaction),
      ..past_interactions
    ]
    None -> past_interactions
  }
}
// fn get_interaction(
//   model: Model,
//   recipe_instance_id: String,
// ) -> option.Option(interaction.CurrentInteraction) {
//   // for debugging only
//   let assert Ok(instance) =
//     model.instance_dict
//     |> dict.get(recipe_instance_id)

//   instance.current_interaction
// }
