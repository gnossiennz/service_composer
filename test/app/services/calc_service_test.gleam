import app/shared/general.{should_be}
import app/shared/service_call.{
  calc_request_operand, calc_request_operator, calc_return_result,
} as _
import app/shared/service_provider_mock as mocked
import app/shared/service_testing_service.{
  type TestResult, type TestingServiceMessage, SelfKey, ServiceResponseReceived,
  StartTest, SubmitStepReceived, make_receiver, make_submitter,
}
import app/types/definition
import app/types/recipe.{Argument, FloatValue, SerializedValue}
import app/types/service_call.{
  DispatcherReturnServiceCall, ServiceReturnResult, ServiceState,
}
import app/types/service_provider.{type ServiceProviderMessage}
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor.{Started}
import gleeunit
import gleeunit/should

const recipe_instance_id = "1234"

pub fn main() {
  gleeunit.main()
}

// ###############################################
// State update tests
// ###############################################

pub fn calc_service_test() {
  let testing_service = start_testing_service()

  let to_recipe_start_message = make_start_message(recipe_instance_id)
  let submit_recipe = make_submitter(testing_service)
  let receive_eventually = make_receiver(testing_service)

  // no arguments
  "calc"
  |> to_recipe_start_message()
  |> submit_recipe()
  |> receive_eventually()
  |> should_be(Some(SubmitStepReceived(Ok("1234"))))
  |> receive_eventually()
  |> should_be(
    Some(ServiceResponseReceived(calc_request_operator(recipe_instance_id, []))),
  )

  // with operator only
  "calc operator:+"
  |> to_recipe_start_message()
  |> submit_recipe()
  |> receive_eventually()
  |> should_be(Some(SubmitStepReceived(Ok("1234"))))
  |> receive_eventually()
  |> should_be(
    Some(
      ServiceResponseReceived(
        calc_request_operand(
          recipe_instance_id,
          "operand1",
          definition.positive_number(),
          [Argument("operator", SerializedValue("+"))],
        ),
      ),
    ),
  )

  // with all required arguments
  "calc operator:+ operand1:3 operand2:4"
  |> to_recipe_start_message()
  |> submit_recipe()
  |> receive_eventually()
  |> should_be(Some(SubmitStepReceived(Ok("1234"))))
  |> receive_eventually()
  |> should_be(
    Some(
      ServiceResponseReceived(
        calc_return_result(recipe_instance_id, "7.0", None, [
          Argument("operator", SerializedValue("+")),
          Argument("operand1", FloatValue(3.0)),
          Argument("operand2", FloatValue(4.0)),
        ]),
      ),
    ),
  )
}

pub fn calc_ordering_test() {
  let testing_service = start_testing_service()

  let to_recipe_start_message = make_start_message(recipe_instance_id)
  let submit_recipe = make_submitter(testing_service)
  let receive_eventually = make_receiver(testing_service)
  let eval =
    evaluate(to_recipe_start_message, submit_recipe, receive_eventually)

  "calc operator:- operand1:3 operand2:4" |> eval() |> should.equal("-1.0")
  "calc operator:- operand1:4 operand2:3" |> eval() |> should.equal("1.0")

  "calc operator:/ operand1:2 operand2:4" |> eval() |> should.equal("0.5")
  "calc operator:/ operand1:4 operand2:2" |> eval() |> should.equal("2.0")

  // insensitive to local ordering of arguments (only the argument name matters)
  "calc operator:/ operand2:2 operand1:4" |> eval() |> should.equal("2.0")
}

fn evaluate(to_recipe_start_message, submit_recipe, receive_eventually) {
  fn(recipe) {
    recipe
    |> to_recipe_start_message()
    |> submit_recipe()
    |> receive_eventually()
    |> should_be(Some(SubmitStepReceived(Ok("1234"))))
    |> receive_eventually()
    |> should.be_some()
    |> extract_result()
  }
}

fn extract_result(result: TestResult) -> String {
  let assert ServiceResponseReceived(DispatcherReturnServiceCall(
    recipe_instance_id: _,
    service_state: ServiceState(
      service: _,
      service_state: _,
      service_return:,
      warning: _,
    ),
  )) = result

  let assert ServiceReturnResult(result:) = service_return

  result
}

fn make_start_message(recipe_instance_id: String) {
  fn(recipe_description) { StartTest(recipe_instance_id, recipe_description) }
}

fn start_testing_service() -> Subject(TestingServiceMessage) {
  // create a process name prefixed by 'calc'
  // this name references a provider service that processes messages
  // of the ServiceProviderMessage type and whose functionality
  // is determined by the supplied resolver function
  let name: Name(ServiceProviderMessage) = process.new_name("calc")

  // see service provider mock in test/shared for the mocked resolver function
  let resolver_fn = mocked.resolve

  // start the testing service and its wrapped service (the service being tested)
  let Started(_pid, #(known_subjects, _wrapped_service)) =
    service_testing_service.start(name, resolver_fn) |> should.be_ok()

  // lookup the testing service (self) subject
  let assert Ok(service_testing_service.Self(testing_service, _)) =
    dict.get(known_subjects, SelfKey)

  testing_service
}
