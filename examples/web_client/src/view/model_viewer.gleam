import app/types/recipe.{type RecipeInstanceID}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/string
import lustre/element.{type Element, text}
import lustre/event.{on_click}
import sketch/css
import sketch/lustre/element/html
import style
import types/error.{type Error, WrapperDecodeError, WrapperGeneralError}
import types/interaction.{
  type CurrentInteraction, type PastInteraction, type ServiceInteraction,
  ServiceInteractionCurrent, ServiceInteractionPast,
}
import types/message.{type Msg, UserToggledModelViewerInstanceDisplay}
import types/model.{type Model, type RecipeInteractionInstance}

// ###################################################
// Model viewer functions
// ###################################################

pub fn render_model(model: Model) -> List(Element(Msg)) {
  [
    render_labelled_item(
      "Server connection",
      style.model_viewer_item_style(),
      model.ws
        |> option.map(fn(_) { "Set" })
        |> option.unwrap("Not set")
        |> text()
        |> embed_as_item(),
    ),
    render_labelled_item(
      "Errors",
      style.model_viewer_item_style(),
      model.errors
        |> stringify_errors()
        |> render_item_list()
        |> embed_as_item(),
    ),
    render_labelled_item(
      "Notifications",
      style.model_viewer_item_style(),
      model.notifications |> render_item_list() |> embed_as_item(),
    ),
    render_labelled_item(
      "Instances",
      style.model_viewer_item_style(),
      render_instances(model.instance_dict, model.show_model_instances),
    ),
  ]
}

fn render_instances(
  instance_dict: Dict(RecipeInstanceID, RecipeInteractionInstance),
  show_model_instances: Bool,
) -> Element(Msg) {
  case dict.size(instance_dict) {
    0 -> html.span(style.model_viewer_item_value_style(), [], [render_none()])
    _ ->
      html.span(style.model_viewer_item_value_style(), [], [
        render_show_hide_button(show_model_instances),
        maybe_show_instances(instance_dict, show_model_instances),
      ])
  }
}

fn maybe_show_instances(
  instance_dict,
  show_model_instances: Bool,
) -> Element(Msg) {
  case show_model_instances {
    True -> {
      let children =
        instance_dict
        |> dict.fold([], fn(acc, key, value) {
          let rendered_instance =
            render_labelled_item(
              key,
              style.model_viewer_block_style(),
              render_instance(value),
            )

          [rendered_instance, ..acc]
        })
      html.div(style.model_viewer_block_style(), [], children)
    }
    False -> html.div(style.model_viewer_block_style(), [], [text("...")])
  }
}

fn render_show_hide_button(show_model_instances: Bool) {
  let message = case show_model_instances {
    True -> "See less <<"
    False -> "See more >>"
  }
  html.button(
    style.model_viewer_button_style(),
    [on_click(UserToggledModelViewerInstanceDisplay)],
    [text(message)],
  )
}

fn render_instance(instance: RecipeInteractionInstance) -> Element(Msg) {
  [
    render_labelled_item(
      "current",
      style.model_viewer_block_element_style(),
      instance.current_interaction |> maybe_render_current_interaction(),
    ),
    render_labelled_item(
      "past",
      style.model_viewer_block_element_style(),
      instance.past_interactions |> render_past_interactions(),
    ),
    render_labelled_item(
      "warnings",
      style.model_viewer_block_element_style(),
      [render_item_list(instance.warnings)] |> embed_as_block_element(),
    ),
  ]
  |> embed_as_block_element()
}

fn maybe_render_current_interaction(
  interaction: Option(CurrentInteraction),
) -> Element(Msg) {
  interaction
  |> option.map(fn(interaction) {
    interaction
    |> ServiceInteractionCurrent()
    |> render_interaction()
  })
  |> option.unwrap([render_none()])
  |> embed_as_block_element()
}

fn render_past_interactions(interactions: List(PastInteraction)) -> Element(Msg) {
  interactions
  |> list.map(fn(interaction) {
    interaction |> ServiceInteractionPast() |> render_interaction()
  })
  |> list.flatten()
  |> fn(interactions) {
    case list.length(interactions) {
      0 -> render_none() |> list.wrap()
      _ -> interactions
    }
  }
  |> embed_as_block_element()
}

fn render_interaction(interaction: ServiceInteraction) -> List(Element(Msg)) {
  let extractor = fn(interaction: ServiceInteraction) -> #(String, String) {
    case interaction {
      ServiceInteractionCurrent(current_interaction) -> #(
        current_interaction.request.name,
        current_interaction.response |> option.lazy_unwrap(fn() { "" }),
      )
      ServiceInteractionPast(past_interaction) -> #(
        past_interaction.request_name,
        past_interaction.response,
      )
    }
  }

  let render = fn(label, value) {
    render_labelled_item(
      label,
      style.model_viewer_single_element_style(),
      embed_as_item(text(value)),
    )
  }

  let #(name, response) = extractor(interaction)

  [
    render("request_name", name),
    render("response", response),
  ]
}

fn render_item_list(items: List(String)) -> Element(Msg) {
  case list.length(items) {
    0 -> render_none()
    _ ->
      items
      |> list.map(fn(warning) { html.li_([], [text(warning)]) })
      |> fn(items) { html.ol_([], items) }
  }
}

fn stringify_errors(errors: List(Error)) -> List(String) {
  errors
  |> list.map(fn(error) {
    case error {
      WrapperDecodeError(err) -> err
      WrapperGeneralError(err) -> err
    }
  })
}

fn embed_as_item(child: Element(Msg)) -> Element(Msg) {
  html.span(style.model_viewer_item_value_style(), [], [
    html.span_([], [child]),
  ])
}

fn embed_as_block_element(children: List(Element(Msg))) -> Element(Msg) {
  html.span(style.model_viewer_item_value_style(), [], [
    html.span_([], children),
  ])
}

fn render_labelled_item(
  label: String,
  style: css.Class,
  child_block: Element(Msg),
) {
  child_block |> render_block_with_label(label, style)
}

fn render_block_with_label(
  child_block: Element(Msg),
  label: String,
  style: css.Class,
) -> Element(Msg) {
  let make_label = fn(label: String) -> Element(Msg) {
    label |> string.append(":") |> text()
  }

  html.div(style, [], [
    html.span(style.model_viewer_item_label_style(), [], [make_label(label)]),
    child_block,
  ])
}

fn render_none() -> Element(Msg) {
  text("None")
}
