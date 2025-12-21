import app/types/client_request.{type RequestSpecification}
import app/types/definition.{
  type RestrictedNumber, type RestrictedText, BaseTextString, Bytes,
  LocalReference, NumberEntity, NumberRangeNegative, NumberRangePositive,
  Resource, RestrictedNumberExplicit, RestrictedNumberNamed,
  RestrictedNumberRange, RestrictedTextExplicit, Scalar, TextEntity,
}
import app/types/recipe.{type RecipeInstanceID}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/element.{type Element, text}
import lustre/element/html
import lustre/event.{on_click, on_input}
import sketch/css.{type Class}
import sketch/lustre/element/html as sketch_element
import style
import types/interaction.{
  type CurrentInteraction, type PastInteraction, type ServiceInteraction,
  ServiceInteractionCurrent, ServiceInteractionPast,
}
import types/message.{type Msg, UserSentResponse, UserUpdatedResponse}

type PartialElement {
  PartialElement(
    creator_fn: fn(Class, List(Attribute(Msg))) -> Element(Msg),
    css_class: Class,
    input_type: Option(String),
    default_attrs: List(Attribute(Msg)),
    special_attrs: List(Attribute(Msg)),
  )
}

pub fn create_interaction_row(
  instance_id: RecipeInstanceID,
  interaction: ServiceInteraction,
) -> Element(Msg) {
  // generate a UI for collecting the user response
  // the UI should be appropriate to the request types and domain
  // e.g. one of a restricted set of operator values of type string
  // or a number that is a positive integer
  [
    make_editable_element(instance_id, interaction),
    make_indicator_element(interaction, fn(current_interaction) {
      current_interaction.response_sent
    }),
    make_indicator_element(interaction, fn(current_interaction) {
      current_interaction.response_acknowledged
    }),
    make_button_element(instance_id, interaction),
  ]
  |> list.filter_map(fn(x) { option.to_result(x, Nil) })
  |> create_row()
}

fn create_row(children: List(Element(Msg))) -> Element(Msg) {
  sketch_element.div(style.interaction_row_style(), [], children)
}

// ###################################################
// Element generation functions
// ###################################################

fn make_editable_element(
  instance_id: RecipeInstanceID,
  interaction: ServiceInteraction,
) -> Option(Element(Msg)) {
  case interaction {
    ServiceInteractionCurrent(current_interaction) ->
      make_current_editable_elem(instance_id, current_interaction)
    ServiceInteractionPast(past_interaction) ->
      make_past_editable_elem(past_interaction)
  }
  |> Some
}

fn make_indicator_element(
  interaction: ServiceInteraction,
  flag_checker_fn: fn(CurrentInteraction) -> Bool,
) -> Option(Element(Msg)) {
  let checked = case interaction {
    ServiceInteractionCurrent(current_interaction) ->
      flag_checker_fn(current_interaction)
    ServiceInteractionPast(_) -> True
  }

  [
    #(True, fn() { Some(attribute.type_("checkbox")) }),
    #(True, fn() { Some(attribute.disabled(True)) }),
    #(checked, fn() { Some(attribute.checked(True)) }),
  ]
  |> lazy_make()
  |> html.input()
  |> Some
}

fn make_button_element(
  instance_id: RecipeInstanceID,
  interaction: ServiceInteraction,
) -> Option(Element(Msg)) {
  let is_disabled = send_response_is_disabled(interaction)
  let is_current = interaction_is_current(interaction)

  [
    #(is_current, fn() { Some(on_click(UserSentResponse(instance_id))) }),
    #(is_disabled, fn() { Some(attribute.disabled(is_disabled)) }),
  ]
  |> lazy_make()
  |> fn(attrs) {
    sketch_element.button(style.interaction_row_button_style(), attrs, [
      text("Send"),
    ])
  }
  |> Some
}

fn lazy_make(
  candidate_criterion_list: List(#(Bool, fn() -> Option(a))),
) -> List(a) {
  // make attributes or elements on demand when the criterion for each is met

  candidate_criterion_list
  |> list.map(fn(candidate_criterion) {
    let #(criterion, maker) = candidate_criterion

    lazy_make_item(criterion, maker)
  })
  |> list.filter_map(fn(x) { option.to_result(x, Nil) })
}

fn lazy_make_item(criterion: Bool, maker: fn() -> Option(a)) -> Option(a) {
  case criterion {
    True -> maker()
    False -> None
  }
}

fn interaction_is_current(interaction: ServiceInteraction) -> Bool {
  case interaction {
    ServiceInteractionCurrent(_) -> True
    ServiceInteractionPast(_) -> False
  }
}

fn send_response_is_disabled(interaction: ServiceInteraction) -> Bool {
  // the send response button is disabled when:
  // 1. the current interaction doesn't yet have a response to send
  // 2. the interaction is a past interaction
  case interaction {
    ServiceInteractionCurrent(current_interaction) ->
      current_interaction.response |> option.is_none()
    ServiceInteractionPast(_) -> True
  }
}

fn make_current_editable_elem(
  instance_id: RecipeInstanceID,
  interaction: CurrentInteraction,
) -> Element(Msg) {
  let default_attrs = make_default_attributes(instance_id, interaction)

  // create an input-type element such as an input or select element
  interaction.request
  |> choose_element_type_with_defaults(default_attrs)
  |> make_element()
}

fn make_default_attributes(
  instance_id: RecipeInstanceID,
  interaction: CurrentInteraction,
) -> List(Attribute(Msg)) {
  let has_response = interaction.response |> option.is_some()

  // lazily construct some attributes depending on whether the response is set
  // the placeholder attribute is set when there is not yet a user response
  // the value attribute is set only when there is a user response
  [
    #(!has_response, fn() {
      interaction.request.prompt
      |> attribute.placeholder()
      |> Some()
    }),
    #(has_response, fn() {
      interaction.response
      |> option.unwrap("")
      |> attribute.value()
      |> Some()
    }),
  ]
  |> lazy_make()
  |> list.append([
    attribute.required(interaction.request.required),
    on_input(UserUpdatedResponse(instance_id, _)),
  ])
}

fn make_past_editable_elem(interaction: PastInteraction) -> Element(Msg) {
  [
    attribute.type_("text"),
    attribute.disabled(True),
    attribute.value(interaction.response),
  ]
  |> fn(attrs) {
    sketch_element.input(style.interaction_row_input_style(), attrs)
  }
}

fn choose_element_type_with_defaults(
  request_specification: RequestSpecification,
  default_attrs: List(Attribute(Msg)),
) -> PartialElement {
  case request_specification.request {
    Scalar(NumberEntity(base: _, specialization: restriction)) ->
      make_numeric_partial(restriction, default_attrs)
    Bytes(TextEntity(base: BaseTextString, specialization: restriction)) ->
      make_text_partial(restriction, default_attrs)
    Resource(LocalReference(mime_type: _)) ->
      // TODO mime type
      PartialElement(
        creator_fn: sketch_element.input,
        css_class: style.interaction_row_input_style(),
        input_type: Some("file"),
        default_attrs:,
        special_attrs: [],
      )
  }
}

fn make_element(partial: PartialElement) -> Element(Msg) {
  let attributes =
    partial.input_type
    |> option.map(fn(input_type) { [attribute.type_(input_type)] })
    |> option.unwrap([])
    |> list.append(partial.default_attrs)
    |> list.append(partial.special_attrs)

  partial.creator_fn(partial.css_class, attributes)
}

fn make_text_partial(
  allowed: Option(RestrictedText),
  default_attrs: List(Attribute(Msg)),
) -> PartialElement {
  let default_text_element =
    PartialElement(
      creator_fn: sketch_element.input,
      css_class: style.interaction_row_input_style(),
      input_type: Some("text"),
      default_attrs:,
      special_attrs: [],
    )

  allowed
  |> option.map(fn(restriction) {
    // TODO derive pattern and length from the restriction
    // [attribute.pattern("[\\+\\-\\*\\/]"), attribute.maxlength(1)]
    case restriction {
      RestrictedTextExplicit(values) -> {
        let creator_fn = fn(class, attrs) {
          sketch_element.select(class, attrs, make_select_options(values))
        }

        PartialElement(
          creator_fn:,
          css_class: style.interaction_row_input_style(),
          input_type: None,
          default_attrs:,
          special_attrs: [],
        )
      }
    }
  })
  |> option.unwrap(default_text_element)
}

fn make_numeric_partial(
  allowed: Option(RestrictedNumber),
  default_attrs: List(Attribute(Msg)),
) -> PartialElement {
  let default_element_with = PartialElement(
    creator_fn: sketch_element.input,
    css_class: style.interaction_row_input_style(),
    input_type: Some("number"),
    default_attrs:,
    special_attrs: _,
  )

  allowed
  |> option.map(fn(restriction) {
    case restriction {
      RestrictedNumberExplicit(values) ->
        PartialElement(
          creator_fn: fn(class, attrs) {
            sketch_element.select(
              class,
              attrs,
              make_select_options(transform_option_type(values)),
            )
          },
          css_class: style.interaction_row_input_style(),
          input_type: None,
          default_attrs:,
          special_attrs: [],
        )
      RestrictedNumberRange(start, end) -> {
        let special_attrs =
          add_number_bounding_attributes(Some(start), Some(end))
        default_element_with(special_attrs)
      }
      RestrictedNumberNamed(named_range) -> {
        let special_attrs = case named_range {
          NumberRangePositive -> add_number_bounding_attributes(Some(0), None)
          NumberRangeNegative -> add_number_bounding_attributes(None, Some(-1))
        }
        default_element_with(special_attrs)
      }
    }
  })
  |> option.unwrap(default_element_with([]))
}

fn add_number_bounding_attributes(
  start: Option(Int),
  end: Option(Int),
) -> List(Attribute(Msg)) {
  [maybe_make_bound(start, attribute.min), maybe_make_bound(end, attribute.max)]
  |> list.filter_map(fn(wrapped_attribute) {
    case wrapped_attribute {
      Some(attr) -> Ok(attr)
      None -> Error(Nil)
    }
  })
}

fn maybe_make_bound(
  bound: Option(Int),
  maker: fn(String) -> Attribute(Msg),
) -> Option(Attribute(Msg)) {
  bound
  |> option.map(fn(bound) { bound |> int.to_string() |> maker() })
}

fn transform_option_type(values: List(Int)) -> List(String) {
  values |> list.map(fn(value) { int.to_string(value) })
}

fn make_select_options(options: List(String)) -> List(Element(Msg)) {
  // add a zero-length attribute value for the first item
  // zero-length values are ignored as updates
  options
  |> list.map(fn(str) { #(str, str) })
  |> list.prepend(#("", "Not set"))
  |> list.map(fn(value_label) {
    html.option([attribute.value(value_label.0)], value_label.1)
  })
}
