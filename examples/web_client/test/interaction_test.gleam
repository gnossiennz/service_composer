import app/types/client_request.{type RequestSpecification, RequestSpecification}
import app/types/definition.{
  BaseNumberInt, BaseTextString, Bytes, LocalReference, NumberEntity, Resource,
  RestrictedNumberExplicit, RestrictedTextExplicit, Scalar, TextEntity,
}
import app/types/service.{ServiceReference}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import lustre/attribute.{type Attribute, value}
import lustre/element.{type Element, text}
import lustre/element/html.{option}
import sketch/lustre as sketch_lustre
import sketch/lustre/element/html as sketch_element
import style
import types/interaction.{
  type ServiceInteraction, CurrentInteraction, PastInteraction,
  ServiceInteractionCurrent, ServiceInteractionPast,
}
import types/message.{type Msg}
import view/interaction as interaction_element

// ###################################################
// Constants and types
// ###################################################

const recipe_instance_id = "some_recipe_instance_id"

const test_service = ServiceReference("test", "me")

const operator_request = RequestSpecification(
  request: Bytes(
    TextEntity(BaseTextString, Some(RestrictedTextExplicit(["+", "-"]))),
  ),
  name: "operator",
  required: False,
  prompt: "An operator such as '+'",
)

const school_year_request = RequestSpecification(
  request: Scalar(
    NumberEntity(
      BaseNumberInt,
      Some(RestrictedNumberExplicit([13, 14, 15, 16, 17])),
    ),
  ),
  name: "school_year",
  required: False,
  prompt: "The pupils school year: 13-17",
)

type SelectOption {
  SelectOption(value: String)
}

type EditableElement {
  Input(value: String, disabled: Bool)
  Select(
    placeholder: Option(String),
    value: Option(String),
    options: List(SelectOption),
  )
}

type Button {
  Button(disabled: Bool)
}

type AcknowledgementIndicator {
  AcknowledgementIndicator
}

type Expected {
  Expected(
    editable: EditableElement,
    sent_indicator: Option(AcknowledgementIndicator),
    ack_indicator: Option(AcknowledgementIndicator),
    button: Button,
  )
}

pub fn main() -> Nil {
  gleeunit.main()
}

// ###################################################
// Request type test functions
// ###################################################

pub fn restricted_text_request_test() {
  check_rendered(
    make_interaction(using: operator_request),
    make_expected(using: operator_request),
  )
}

pub fn restricted_number_request_test() {
  check_rendered(
    make_interaction(using: school_year_request),
    make_expected(using: school_year_request),
  )
}

// ###################################################
// Row test functions
// ###################################################

pub fn past_interaction_row_test() {
  // show a past interaction
  let interaction = make_past_interaction(request_name: "test", response: "arg")

  let expected =
    Expected(
      editable: Input(value: "arg", disabled: True),
      sent_indicator: Some(AcknowledgementIndicator),
      ack_indicator: Some(AcknowledgementIndicator),
      button: Button(disabled: True),
    )

  check_rendered(interaction, equals: expected)
}

pub fn current_interaction_response_not_set_row_test() {
  // response not yet set in the current interaction
  let interaction =
    make_current_interaction(
      request: operator_request,
      response: None,
      sent: False,
      acknowledged: False,
    )

  let expected =
    Expected(
      editable: Select(
        placeholder: Some("An operator such as '+'"),
        value: None,
        options: [SelectOption(value: "+"), SelectOption(value: "-")],
      ),
      sent_indicator: None,
      ack_indicator: None,
      button: Button(disabled: True),
    )

  check_rendered(interaction, equals: expected)
}

pub fn current_interaction_response_not_sent_row_test() {
  // current interaction has a response but response not yet sent
  let interaction =
    make_current_interaction(
      request: operator_request,
      response: Some("+"),
      sent: False,
      acknowledged: False,
    )

  let expected =
    Expected(
      editable: Select(placeholder: None, value: Some("+"), options: [
        SelectOption(value: "+"),
        SelectOption(value: "-"),
      ]),
      sent_indicator: None,
      ack_indicator: None,
      button: Button(disabled: False),
    )

  check_rendered(interaction, equals: expected)
}

pub fn current_interaction_response_sent_row_test() {
  // response has been sent but acknowledgement not yet received
  let interaction =
    make_current_interaction(
      request: operator_request,
      response: Some("+"),
      sent: True,
      acknowledged: False,
    )

  let expected =
    Expected(
      editable: Select(placeholder: None, value: Some("+"), options: [
        SelectOption(value: "+"),
        SelectOption(value: "-"),
      ]),
      sent_indicator: Some(AcknowledgementIndicator),
      ack_indicator: None,
      button: Button(disabled: False),
    )

  check_rendered(interaction, equals: expected)
}

pub fn current_interaction_response_acknowledged_row_test() {
  // response has been sent and the acknowledgement received
  let interaction =
    make_current_interaction(
      request: operator_request,
      response: Some("+"),
      sent: True,
      acknowledged: True,
    )

  let expected =
    Expected(
      editable: Select(placeholder: None, value: Some("+"), options: [
        SelectOption(value: "+"),
        SelectOption(value: "-"),
      ]),
      sent_indicator: Some(AcknowledgementIndicator),
      ack_indicator: Some(AcknowledgementIndicator),
      button: Button(disabled: False),
    )

  check_rendered(interaction, equals: expected)
}

// ###################################################
// Utility functions
// ###################################################

fn make_interaction(using request: RequestSpecification) -> ServiceInteraction {
  make_current_interaction(
    request: request,
    response: None,
    sent: False,
    acknowledged: False,
  )
}

fn make_expected(using request: RequestSpecification) -> Expected {
  let placeholder = request.prompt |> Some
  let options = make_options(request)

  Expected(
    editable: Select(placeholder:, value: None, options:),
    sent_indicator: None,
    ack_indicator: None,
    button: Button(disabled: True),
  )
}

fn make_options(request: RequestSpecification) -> List(SelectOption) {
  // pull out the explicit restricted domains
  case request.request {
    Scalar(NumberEntity(base: _, specialization: restriction)) -> {
      restriction
      |> option.map(fn(restriction) {
        case restriction {
          RestrictedNumberExplicit(values) ->
            values |> list.map(fn(i) { int.to_string(i) })
          _ -> []
        }
      })
    }
    Bytes(TextEntity(base: BaseTextString, specialization: restriction)) -> {
      restriction
      |> option.map(fn(restriction) {
        case restriction {
          RestrictedTextExplicit(values) -> values
        }
      })
    }
    Resource(LocalReference(mime_type: _)) -> None
  }
  |> option.unwrap([])
  |> list.map(fn(x) { SelectOption(x) })
}

fn check_rendered(
  interaction: ServiceInteraction,
  equals expected: Expected,
) -> Element(Msg) {
  let assert Ok(stylesheet) = sketch_lustre.setup()
  use <- sketch_lustre.render(stylesheet:, in: [sketch_lustre.node()])

  recipe_instance_id
  |> interaction_element.create_interaction_row(interaction)
  |> fn(elem) {
    elem
    |> element.to_string()
    |> should.equal(make_expected_interaction(expected))

    elem
  }
}

fn make_current_interaction(
  request request: RequestSpecification,
  response response: Option(String),
  sent sent: Bool,
  acknowledged acknowledged: Bool,
) -> ServiceInteraction {
  ServiceInteractionCurrent(CurrentInteraction(
    service: test_service,
    request: request,
    response: response,
    response_sent: sent,
    response_acknowledged: acknowledged,
  ))
}

fn make_past_interaction(
  request_name request_name: String,
  response response: String,
) -> ServiceInteraction {
  ServiceInteractionPast(PastInteraction(
    recipe_instance_id:,
    request_name:,
    response:,
  ))
}

fn make_expected_interaction(expected: Expected) -> String {
  sketch_element.div(
    style.interaction_row_style(),
    [],
    make_expected_children(expected),
  )
  |> element.to_string()
}

fn make_expected_children(expected: Expected) -> List(Element(a)) {
  [
    make_expected_editable_child(expected.editable),
    make_expected_indicator(expected.sent_indicator),
    make_expected_indicator(expected.ack_indicator),
    make_expected_button_child(expected.button),
  ]
  |> list.filter_map(fn(elem) { option.to_result(elem, Nil) })
}

fn make_expected_editable_child(editable: EditableElement) -> Option(Element(a)) {
  case editable {
    Select(placeholder:, value:, options:) ->
      make_expected_select_child(placeholder, value, options)
    Input(value:, disabled:) -> make_expected_input_child(value, disabled)
  }
}

fn make_expected_select_child(
  placeholder,
  select_value,
  options,
) -> Option(Element(a)) {
  sketch_element.select(
    style.interaction_row_input_style(),
    make_expected_select_attributes(placeholder, select_value),
    make_expected_select_options(options),
  )
  |> Some
}

fn make_expected_input_child(
  input_value: String,
  disabled: Bool,
) -> Option(Element(a)) {
  sketch_element.input(style.interaction_row_input_style(), [
    attribute.disabled(disabled),
    attribute.type_("text"),
    attribute.value(input_value),
  ])
  |> Some
}

fn make_expected_indicator(
  indicator: Option(AcknowledgementIndicator),
) -> Option(Element(a)) {
  case indicator {
    // Some(_) -> Some(text("&#x2705;"))
    // or &checkmark;
    Some(_) -> [attribute.checked(True)]
    None -> []
  }
  |> list.append([
    attribute.type_("checkbox"),
    attribute.disabled(True),
  ])
  |> html.input()
  |> Some
}

fn make_expected_button_child(expected_button: Button) -> Option(Element(a)) {
  let Button(disabled) = expected_button

  sketch_element.button(
    style.interaction_row_button_style(),
    [attribute.disabled(disabled)],
    [text("Send")],
  )
  |> Some
}

fn make_expected_select_options(options: List(SelectOption)) {
  options
  |> list.map(fn(option) { html.option([value(option.value)], option.value) })
  |> list.prepend(option([value("")], "Not set"))
}

fn make_expected_select_attributes(
  placeholder: Option(String),
  value: Option(String),
) -> List(Attribute(a)) {
  [
    maybe_make_attribute(placeholder, attribute.placeholder),
    maybe_make_attribute(value, attribute.value),
  ]
  |> list.filter_map(fn(attr) { option.to_result(attr, Nil) })
}

fn maybe_make_attribute(
  attr: Option(String),
  maker: fn(String) -> Attribute(a),
) -> Option(Attribute(a)) {
  case attr {
    Some(value) -> Some(maker(value))
    None -> None
  }
}
