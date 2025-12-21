//// Test the updater module
//// This module updates a recipe after a call to a service provider
//// The dispatching service may need to re-submit the recipe immediately
//// or it may need to pass an argument request from the provider to the client
//// This choice is determined by the substitution status of the recipe
//// Substitution is the process of taking the result from a fully resolved
//// child step and adding the result as an argument to the child's parent step
//// Substituted recipes are immediately re-submitted to the service provider
//// as they provide additional step arguments from completed child steps

import app/engine/dispatch_step/update.{MaybeSubstitutedRecipe} as updater
import app/shared/recipe.{make_recipe, make_recipe_with_error} as _
import app/shared/service_call.{
  calc_end_point_error, calc_request_operand, calc_request_operator,
  calc_return_result,
} as _
import app/types/definition
import app/types/recipe.{Argument, SerializedValue}
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn pass_recipe_with_error_updater_test() {
  // recipe has just one step but is in an error state
  // with this recipe, the service call returns a request to the client for an operator
  // however, with the recipe in error state an error is returned when attempting an update
  "calc"
  |> make_recipe_with_error(None)
  |> updater.maybe_update_recipe(calc_request_operator("some_instance_id", []))
  |> should.be_error()
  |> should.equal("Error in recipe")
}

pub fn pass_error_updater_test() {
  // recipe has just one step (with no substitutions)
  // with this recipe, the service call returns a request to the client for an operator
  // however, passing an endpoint error produces no update to the recipe
  let recipe = "calc" |> make_recipe(None, None, None)

  recipe
  |> updater.maybe_update_recipe(calc_end_point_error("some_instance_id"))
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(False, recipe))
}

pub fn pass_request_step_1_updater_test() {
  // recipe has just one step (with no substitutions)
  // with this recipe, the service call returns a request to the client for an operator
  // passing that request with updated arguments returns an updated recipe
  let recipe = "calc" |> make_recipe(None, None, None)
  let response =
    calc_request_operator("some_instance_id", [
      Argument("operator", SerializedValue("+")),
    ])
  let expected = "calc operator:+" |> make_recipe(None, None, None)

  recipe
  |> updater.maybe_update_recipe(response)
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(False, expected))
}

pub fn pass_result_step_1_updater_test() {
  // recipe has just one step (with no substitutions)
  // with this recipe, the service call returns a result for the step
  // passing a result produces the same recipe (no updates)
  let recipe =
    "calc operator:+ operand:33 operand:55" |> make_recipe(None, None, None)
  let response =
    calc_return_result("some_instance_id", "88.0", None, [
      Argument("operator", SerializedValue("+")),
      Argument("operand", SerializedValue("33")),
      Argument("operand", SerializedValue("55")),
    ])

  recipe
  |> updater.maybe_update_recipe(response)
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(False, recipe))
}

pub fn pass_result_step_2_updater_test() {
  // recipe has two steps (with one substitution)
  // with this recipe, the service call returns a result for the inner step
  // passing a result produces a substitution (added as an argument to its parent step)
  let recipe =
    "calc operator:+ operand:(calc operator:* operand:2 operand:3)"
    |> make_recipe(None, None, None)
  let response =
    calc_return_result("some_instance_id", "6.0", None, [
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("2")),
      Argument("operand", SerializedValue("3")),
    ])
  let expected = "calc operand:6.0 operator:+" |> make_recipe(None, None, None)

  recipe
  |> updater.maybe_update_recipe(response)
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(True, expected))
}

pub fn pass_request_step_3_updater_test() {
  // recipe has three steps (with two substitutions)
  // with this recipe, the service call returns a request for the first inner step
  // passing a request produces no substitution as the current step did not produce a result
  let recipe =
    "calc operator:+ operand:(calc operator:* operand:8) operand:(calc operator:* operand:2 operand:3)"
    |> make_recipe(None, None, None)
  let response =
    calc_request_operand(
      "some_instance_id",
      "operands",
      definition.positive_number(),
      [
        Argument("operator", SerializedValue("*")),
        Argument("operand", SerializedValue("8")),
      ],
    )
  let expected = recipe

  recipe
  |> updater.maybe_update_recipe(response)
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(False, expected))
}

pub fn pass_result_step_3_updater_test() {
  // recipe has three steps (with two substitutions)
  // the operand args have been swapped so that the first inner step is immediately resolvable
  // with this recipe, the service call returns a result for the first inner step
  // passing a result produces a substitution of the first operand argument
  let recipe =
    "calc operator:+ operand:(calc operator:* operand:2 operand:3) operand:(calc operator:* operand:8)"
    |> make_recipe(None, None, None)
  let response =
    calc_return_result("some_instance_id", "6.0", None, [
      Argument("operator", SerializedValue("*")),
      Argument("operand", SerializedValue("2")),
      Argument("operand", SerializedValue("3")),
    ])
  let expected =
    "calc operand:6.0 operator:+ operand:(calc operator:* operand:8)"
    |> make_recipe(None, None, None)

  recipe
  |> updater.maybe_update_recipe(response)
  |> should.be_ok()
  |> should.equal(MaybeSubstitutedRecipe(True, expected))
}
