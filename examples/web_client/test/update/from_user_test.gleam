import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import types/interaction.{CurrentInteraction}
import types/message.{
  UserSelectedRecipe, UserSentResponse, UserSubmittedRecipe, UserUpdatedResponse,
}
import update/shared.{
  get_instance_changes, get_model_changes, make_interaction, make_model,
  operator_request, recipe_instance_id, service, update_model_with,
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn recipe_selection_test() {
  // when a user selects a recipe, the recipe is stored in the model
  recipe_instance_id
  |> make_model(with_interaction: None)
  |> update_model_with(UserSelectedRecipe("calc"))
  |> get_model_changes()
  |> should.equal([shared.RecipeSelectionChange(Some("calc"))])
}

pub fn recipe_submission_test() {
  // submitting a recipe has no DIRECT effect on the model
  // the model eventually receives a server acknowledgement
  // and it is this that updates the model
  // (see the from_server tests for an example)
  recipe_instance_id
  |> make_model(with_interaction: None)
  |> update_model_with(UserSubmittedRecipe)
  |> get_model_changes()
  |> should.equal([])
}

pub fn user_sent_response1_test() {
  // if the user sends a response to the server
  // then the sent flag is set for the current interaction within the model
  // here, the current interaction has a request for an operator
  // and whatever response has been set on the current interaction
  // is sent to the server (including None which is the case here)

  let before_model =
    recipe_instance_id
    |> make_model(
      with_interaction: operator_request |> make_interaction() |> Some(),
    )

  let change =
    before_model
    |> update_model_with(UserSentResponse(recipe_instance_id))

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // this is the same before instance except that the sent flag is set
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([
    shared.InstanceCurrentInteractionChange(
      Some(CurrentInteraction(
        service:,
        request: operator_request,
        response: None,
        response_sent: True,
        response_acknowledged: False,
      )),
    ),
  ])
}

pub fn user_sent_response2_test() {
  // if the UI allowed a user to submit an unexpected response
  // e.g. a response to a user interaction that had not yet started
  // then the model would not be updated
  // (if the model has no current interaction then no update occurs)
  let change =
    recipe_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(UserSentResponse(recipe_instance_id))

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // and no changes to the instance
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([])
}

pub fn user_updated_response1_test() {
  // if the user interacts with the UI and generates a response to a request
  // then the user response is set for the current interaction within the model
  // here, the response is for a request for an operator

  let before_model =
    recipe_instance_id
    |> make_model(
      with_interaction: operator_request |> make_interaction() |> Some(),
    )

  let response = "+"

  let change =
    before_model
    |> update_model_with(UserUpdatedResponse(recipe_instance_id, response))

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // this is the same before instance except that the response is set
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([
    shared.InstanceCurrentInteractionChange(
      Some(CurrentInteraction(
        service:,
        request: operator_request,
        response: Some(response),
        response_sent: False,
        response_acknowledged: False,
      )),
    ),
  ])
}

pub fn user_updated_response2_test() {
  // as for UserSentResponse, if the UserUpdatedResponse message is
  // received when there is no current interaction
  // then there is no change to the model
  let change =
    recipe_instance_id
    |> make_model(with_interaction: None)
    |> update_model_with(UserUpdatedResponse(recipe_instance_id, "+"))

  // expect no top-level model changes
  change |> get_model_changes() |> should.equal([])

  // and no changes to the instance
  change
  |> get_instance_changes(recipe_instance_id)
  |> should.equal([])
}
