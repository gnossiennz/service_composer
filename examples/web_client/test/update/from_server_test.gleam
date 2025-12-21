import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import types/web_api_acknowledgement.{
  ReceivedClientUpdate, ReceivedNewRecipe, WebAPIAcknowledgement,
}
import update/shared.{
  get_instance_changes, get_model_changes, make_acknowledgement_msg,
  make_empty_model, make_interaction, make_model, make_request_msg,
  make_result_msg, operator_request, recipe_evolution, recipe_id,
  recipe_instance_id, update_model_with, warning,
}

// TODO add tests for the remaining wrapped server types

pub fn main() -> Nil {
  gleeunit.main()
}

// ###################################################
// Server Acknowledge Recipe
// ###################################################

pub fn receive_recipe_acknowledgement_message_test() {
  // when the server acknowledges a newly submitted recipe
  // a new RecipeInteractionInstance is created
  let msg =
    make_acknowledgement_msg(WebAPIAcknowledgement(
      ack_type: ReceivedNewRecipe,
      recipe_id:,
      recipe_instance_id:,
      warning: None,
    ))

  // starting with no instances...
  let change = make_empty_model() |> update_model_with(msg)

  // expect a new instance in the instance dictionary
  change
  |> get_model_changes()
  |> should.equal([shared.InstanceDictSizeChange(1)])

  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([shared.NewInstanceCreated(recipe_instance_id)])
}

pub fn receive_client_update_acknowledgement_message_test() {
  // when the server acknowledges a client update
  // the instance is updated with a notification
  let msg =
    make_acknowledgement_msg(WebAPIAcknowledgement(
      ack_type: ReceivedClientUpdate,
      recipe_id:,
      recipe_instance_id:,
      warning: None,
    ))

  // starting with an existing instance with known instance ID
  let change =
    recipe_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(msg)

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([
    shared.InstanceNotificationsChange(["Client update acknowledged"]),
  ])
}

// ###################################################
// Service Provider Request
// ###################################################

pub fn server_request_message_no_instance_test() {
  // if a service provider request is unexpectedly received
  // where there is no corresponding instance
  // then the model remains unchanged

  let msg =
    make_request_msg(recipe_instance_id, operator_request, Some(warning))

  // starting with an existing instance with a DIFFERENT instance ID
  let existing_instance_id = "another instance ID"
  let change =
    existing_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(msg)

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // or instance-level changes
  change
  |> get_instance_changes(existing_instance_id)
  |> should.equal([])
}

pub fn server_request_message_test() {
  let msg =
    make_request_msg(recipe_instance_id, operator_request, Some(warning))

  // starting with an existing instance with known instance ID
  let change =
    recipe_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(msg)

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // however, expect the recipe instance to be updated
  // with a new interaction for handling the service provider request
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([
    shared.InstanceWarningsChange(["More than two operands provided"]),
    shared.InstanceCurrentInteractionChange(
      operator_request |> make_interaction() |> Some(),
    ),
    shared.InstanceHistoryChange([recipe_evolution]),
  ])
}

pub fn server_result_message_test() {
  let msg = make_result_msg(recipe_instance_id, "44", Some(warning))

  let change =
    recipe_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(msg)

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // however, expect the recipe instance to hold the result
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([
    shared.InstanceWarningsChange([warning]),
    shared.InstanceResultChange(Some("44")),
    shared.InstanceHistoryChange([recipe_evolution]),
  ])
}
