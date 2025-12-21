//// Test the dispatcher module that dispatches a recipe step to a service provider
//// This uses the service_testing_service to receive the responses from the service provider
//// The service_testing_service is also used in other tests

import app/engine/dispatch_step/dispatch as dispatcher
import app/shared/general.{should_be} as _
import app/shared/recipe.{make_recipe} as _
import app/shared/service_call.{
  calc_request_operand, calc_request_operator, calc_return_result,
} as _
import app/shared/service_provider_mock as mocked
import app/shared/service_testing_service.{
  type TestingServiceMessage, SelfKey, ServiceResponseReceived,
  SubjectSubmitStep, SubmitStepKey, SubmitStepReceived, make_receiver,
}
import app/types/client_response.{type ArgumentSubmission, ArgumentSubmission}
import app/types/definition
import app/types/dispatch.{type DispatchInfo, DispatchInfo}
import app/types/recipe.{
  type Argument, type Recipe, Argument, FloatValue, SerializedValue,
}
import app/types/service.{ServiceDescription, ServiceReference}
import app/types/service_call.{type DispatcherReturn}
import app/types/service_provider.{type ServiceProviderMessage}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{Started}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

//******************************************************************
// Test functions
//******************************************************************

pub fn calc_service_dispatcher_test() {
  let #(calc_service_name, testing_service, submit_step_result_subject) =
    start_testing_service()

  // the service id specified here must match the one defined in make_recipe/3
  let service_dictionary: Dict(String, DispatchInfo) =
    dict.new()
    |> dict.insert(
      "com.examples.service_composer:calc",
      DispatchInfo(
        process_name: calc_service_name,
        description: ServiceDescription(
          reference: ServiceReference(
            name: "calc",
            path: "com.examples.service_composer",
          ),
          description: "A test service",
        ),
      ),
    )

  let dispatcher =
    make_dispatcher(submit_step_result_subject, service_dictionary)

  // Test 1: no arguments known, none supplied
  "calc"
  |> make_recipe(
    Some("dispatch_no_args_id"),
    Some("dispatch_no_args_iid"),
    None,
  )
  |> test_dispatch_of(None, dispatcher)
  |> check_message_receipt(
    testing_service,
    expected: calc_request_operator(_, []),
  )

  // Test 2: no arguments known, operator supplied
  "calc"
  |> make_recipe(
    Some("dispatch_with_operator_id"),
    Some("dispatch_with_operator_iid"),
    None,
  )
  |> test_dispatch_of(
    Some(Argument(name: "operator", value: SerializedValue("+"))),
    dispatcher,
  )
  |> check_message_receipt(
    testing_service,
    expected: calc_request_operand(_, "operand1", definition.positive_number(), [
      Argument("operator", SerializedValue("+")),
    ]),
  )

  // Test 3: all but one arguments known, argument supplied, expecting a result
  "calc operator:+ operand1:33"
  |> make_recipe(
    Some("dispatch_with_operator_op1_id"),
    Some("dispatch_with_operator_op1_iid"),
    None,
  )
  |> test_dispatch_of(
    Some(Argument(name: "operand2", value: SerializedValue("44"))),
    dispatcher,
  )
  |> check_message_receipt(
    testing_service,
    expected: calc_return_result(_, "77.0", None, [
      Argument("operator", SerializedValue("+")),
      Argument("operand1", FloatValue(33.0)),
      Argument("operand2", FloatValue(44.0)),
    ]),
  )

  // Test 4: all arguments known, argument supplied, expecting a result
  // The extra argument (44) should be ignored, but a warning is returned
  "calc operator:+ operand1:33 operand2:55"
  |> make_recipe(
    Some("dispatch_all_args_plus_extra_id"),
    Some("dispatch_all_args_plus_extra_iid"),
    None,
  )
  |> test_dispatch_of(
    Some(Argument(name: "operand3", value: SerializedValue("44"))),
    dispatcher,
  )
  |> check_message_receipt(
    testing_service,
    expected: calc_return_result(
      _,
      "88.0",
      Some("Unexpected argument name: operand3"),
      [
        Argument("operator", SerializedValue("+")),
        Argument("operand1", FloatValue(33.0)),
        Argument("operand2", FloatValue(55.0)),
      ],
    ),
  )

  process.send(testing_service, service_testing_service.Shutdown)
}

fn start_testing_service() {
  // create a process name prefixed by 'calc'
  // this name references a provider service that processes messages
  // of the ServiceProviderMessage type and whose functionality
  // is determined by the supplied resolver function
  let name: Name(ServiceProviderMessage) = process.new_name("calc")

  // see service provider mock in test/shared for the mocked resolver function
  let resolver_fn = mocked.resolve

  // start the testing service and its wrapped service (the service being tested)
  let Started(_pid, #(known_subjects, wrapped_service)) =
    service_testing_service.start(name, resolver_fn) |> should.be_ok()

  // lookup the testing service (self) subject
  let assert Ok(service_testing_service.Self(testing_service, _)) =
    dict.get(known_subjects, SelfKey)

  // lookup the testing service subject that acknowledges
  // submitting a step to the wrapped service
  let assert Ok(SubjectSubmitStep(submit_step_result_subject, _)) =
    dict.get(known_subjects, SubmitStepKey)

  #(wrapped_service, testing_service, submit_step_result_subject)
}

fn make_dispatcher(
  submit_step_result_subject,
  service_dictionary,
) -> fn(Recipe, Option(ArgumentSubmission)) -> Result(Nil, String) {
  fn(recipe, submission) {
    dispatcher.run_next_step(
      submit_step_result_subject,
      service_dictionary,
      recipe,
      submission,
    )
  }
}

fn test_dispatch_of(
  recipe: Recipe,
  response: Option(Argument),
  dispatcher: fn(Recipe, Option(ArgumentSubmission)) -> Result(Nil, String),
) -> Recipe {
  // ensure recipe step and client response refer to the same service
  let submission =
    ArgumentSubmission(
      recipe_id: recipe.id,
      recipe_instance_id: recipe.iid,
      service: recipe.root.service,
      response:,
    )
    |> Some()

  dispatcher(recipe, submission) |> should.be_ok()

  recipe
}

fn check_message_receipt(
  recipe: Recipe,
  testing_service: Subject(TestingServiceMessage),
  expected expected_response: fn(String) -> DispatcherReturn,
) {
  let receive_eventually = make_receiver(testing_service)

  // the testing service should eventually receive:
  //  1. an acknowledgement of the step submission
  //  2. the result from the wrapped service (in this case an operator request)
  None
  |> receive_eventually()
  |> should_be(Some(SubmitStepReceived(Ok(recipe.iid))))
  |> receive_eventually()
  |> should_be(Some(ServiceResponseReceived(expected_response(recipe.iid))))
}
