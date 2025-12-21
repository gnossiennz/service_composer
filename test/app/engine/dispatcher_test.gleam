import app/engine/dispatcher.{
  type DispatcherServiceMessage, AddRecipe, QueryStatus, ReceiveClientUpdate,
  Shutdown,
}
import app/engine/dispatcher_store.{
  type RecipeExecutionStatus, type RecipeState, type StatsRecord, StatsRecord,
  recipe_stats_as_record,
}
import app/shared/client_response.{make_client_response}
import app/shared/general.{parse_as_float_operand, parse_as_int_operand}
import app/shared/recipe.{convert_root, make_recipe} as _
import app/shared/service_call.{
  calc_recipe_state_update, calc_request_operand, calc_request_operator,
  calc_return_result, sqrt_request_operand,
} as _
import app/types/definition
import app/types/recipe.{type Arguments, Argument, FloatValue, SerializedValue}
import app/types/service.{ServiceReference}
import app/types/service_call.{
  type ClientRecipeState, type DispatcherReturn, type ServiceCallResponse,
  type ServiceState, DispatcherReturnServiceCall, ServiceCallResponse,
}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleeunit
import gleeunit/should
import service_composer

pub const calc_service_reference = ServiceReference(
  name: "calc",
  path: "com.examples.service_composer",
)

pub const sqrt_service_reference = ServiceReference(
  name: "sqrt",
  path: "com.examples.service_composer",
)

pub type QueryResult {
  State(RecipeState)
  TimedOut
}

pub fn main() {
  gleeunit.main()
}

pub fn dispatcher_test() {
  // the following tests require the 'calc' service provider module to be loaded
  // see service_providers/calc in examples/services
  let assert Ok(caller_info) = service_composer.start_dispatcher()
  let dispatcher_name = caller_info.dispatcher
  process.sleep(50)

  // a function to transform recipes from using 'serialized arguments'
  // to 'native arguments' (the latter form is returned from service providers)
  let root_transformer =
    convert_root(_, convert_serialized_operands_to_float) |> Some

  // the following three sub-tests share the same dispatcher
  // therefore ensure that the recipes in each sub-test have distinct instance IDs

  // 1. test normal use of the dispatcher (i.e. registering a listener)
  let _ = test_registered_listener(dispatcher_name)

  // 2. test a single step recipe and poll the query subject for changes of state
  test_single_step(dispatcher_name, root_transformer)

  // 3. test a multi step recipe and poll the query subject for changes of state
  test_multi_step(dispatcher_name, root_transformer)

  dispatcher_name
  |> process.named_subject()
  |> process.send(Shutdown)
}

fn test_registered_listener(dispatcher_name: Name(DispatcherServiceMessage)) {
  // A simple test for listener registration
  // Uses the calc service module as test module
  // Expects this module to be loaded (see provider_loader)
  // and expects the test module to return results with minimal delay
  let service_call_response_subject: Subject(ServiceCallResponse) =
    process.new_subject()
  let recipe_id = Some("test_registered_listener_id")
  let recipe_iid = Some("test_registered_listener_iid")
  let recipe_desc = "calc operator:* operand1:3"
  let recipe = recipe_desc |> make_recipe(recipe_id, recipe_iid, None)

  // register this process to receive ServiceCallResponse updates
  dispatcher_name
  |> process.named_subject()
  |> process.send(dispatcher.RegisterListener(
    service_call_response_subject,
    recipe.iid,
  ))

  // dispatch the recipe and expect two service call responses:
  // 1. a recipe state update with state of Pending
  // 2. a request for the second argument
  use recipe_state_update <- result.try(dispatch_receive_immediate(
    dispatcher_name,
    AddRecipe(recipe),
    service_call_response_subject,
  ))

  // check the first response is a recipe state update with state of Pending
  recipe_state_update
  |> should.equal(ServiceCallResponse(
    recipe_id: recipe.id,
    recipe_desc: "calc operator:* operand1:3",
    dispatcher_return: calc_recipe_state_update(
      recipe.iid,
      service_call.Pending,
    ),
  ))

  // receive the second expected response
  use request <- result.try(process.receive(
    service_call_response_subject,
    within: 100,
  ))

  // check the second response is an operand request
  request
  |> should.equal(ServiceCallResponse(
    recipe_id: recipe.id,
    recipe_desc: "calc operator:* operand1:3.0",
    dispatcher_return: calc_request_operand(
      recipe.iid,
      "operand2",
      definition.any_number(),
      [
        Argument("operator", SerializedValue("*")),
        Argument("operand1", FloatValue(3.0)),
      ],
    ),
  ))

  // send a client response to the dispatcher and expect a final result
  // as all of the arguments have been provided
  use result <- result.try(dispatch_receive_immediate(
    dispatcher_name,
    ReceiveClientUpdate(make_client_response(
      recipe.id,
      recipe.iid,
      calc_service_reference,
      "operand2",
      "5",
    )),
    service_call_response_subject,
  ))

  result
  |> should.equal(ServiceCallResponse(
    recipe_id: recipe.id,
    recipe_desc: "calc operator:* operand1:3.0 operand2:5.0",
    dispatcher_return: calc_return_result(recipe.iid, "15.0", None, [
      Argument("operator", SerializedValue("*")),
      Argument("operand1", FloatValue(3.0)),
      Argument("operand2", FloatValue(5.0)),
    ]),
  ))

  Ok(result)
}

fn test_single_step(dispatcher_name, root_transformer) {
  // Test a recipe in detail
  // This recipe has a single composable step
  // At each stage check the updated recipe, the status and statistics
  let recipe_id = Some("test_single_step_id")
  let recipe_iid = Some("test_single_step_iid")
  let recipe = "calc" |> make_recipe(recipe_id, recipe_iid, None)

  None
  |> dispatch_receive_eventually(dispatcher_name, recipe.iid, AddRecipe(recipe))
  |> expecting_recipe(recipe_id, recipe_iid, "calc", None)
  |> expecting_status(
    calc_request_operator(recipe.iid, [])
    |> make_status(service_call.Requesting),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 1,
      client_response: 0,
      dispatch_ack: 1,
      service_result: 1,
    )),
  )
  |> dispatch_receive_eventually(
    dispatcher_name,
    recipe.iid,
    ReceiveClientUpdate(make_client_response(
      recipe.id,
      recipe.iid,
      calc_service_reference,
      "operator",
      "+",
    )),
  )
  |> expecting_recipe(
    recipe_id,
    recipe_iid,
    "calc operator:+",
    root_transformer,
  )
  |> expecting_status(
    calc_request_operand(recipe.iid, "operand1", definition.any_number(), [
      Argument("operator", SerializedValue("+")),
    ])
    |> make_status(service_call.Requesting),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 2,
      client_response: 1,
      dispatch_ack: 2,
      service_result: 2,
    )),
  )
  |> dispatch_receive_eventually(
    dispatcher_name,
    recipe.iid,
    ReceiveClientUpdate(make_client_response(
      recipe.id,
      recipe.iid,
      calc_service_reference,
      "operand1",
      "3",
    )),
  )
  |> expecting_recipe(
    recipe_id,
    recipe_iid,
    "calc operator:+ operand1:3",
    root_transformer,
  )
  |> expecting_status(
    calc_request_operand(recipe.iid, "operand2", definition.any_number(), [
      Argument("operator", SerializedValue("+")),
      Argument("operand1", FloatValue(3.0)),
    ])
    |> make_status(service_call.Requesting),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 3,
      client_response: 2,
      dispatch_ack: 3,
      service_result: 3,
    )),
  )
  |> dispatch_receive_eventually(
    dispatcher_name,
    recipe.iid,
    ReceiveClientUpdate(make_client_response(
      recipe.id,
      recipe.iid,
      calc_service_reference,
      "operand2",
      "5",
    )),
  )
  |> expecting_recipe(
    recipe_id,
    recipe_iid,
    "calc operator:+ operand1:3 operand2:5",
    root_transformer,
  )
  |> expecting_status(
    calc_return_result(recipe.iid, "8.0", None, [
      Argument("operator", SerializedValue("+")),
      Argument("operand1", FloatValue(3.0)),
      Argument("operand2", FloatValue(5.0)),
    ])
    |> make_status(service_call.Completing),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 3,
      client_response: 3,
      dispatch_ack: 4,
      service_result: 4,
    )),
  )
}

fn test_multi_step(dispatcher_name, root_transformer) {
  // Test a recipe in detail
  // This recipe has multiple composable steps
  // At each stage check the updated recipe, the status and statistics
  let recipe_id = Some("test_multi_step_id")
  let recipe_iid = Some("test_multi_step_iid")

  // make a recipe that uses "calc" and "sqrt" as the short service references
  // 3/2 + 5(sqrt(x))
  let recipe_description =
    "calc operator:+ operand1:(calc operator:/ operand1:3 operand2:2) operand2:(calc operator:* operand1:5 operand2:(sqrt))"
  let recipe = recipe_description |> make_recipe(recipe_id, recipe_iid, None)

  None
  |> dispatch_receive_eventually(dispatcher_name, recipe.iid, AddRecipe(recipe))
  // operand1 is resolved immediately to the constant 1.5
  |> expecting_recipe(
    recipe_id,
    recipe_iid,
    "calc operand1:1.5 operator:+ operand2:(calc operator:* operand1:5 operand2:(sqrt))",
    None,
  )
  |> expecting_status(
    sqrt_request_operand(recipe.iid, "arg", definition.positive_number(), [])
    |> make_status(service_call.Requesting),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 1,
      client_response: 0,
      dispatch_ack: 2,
      service_result: 2,
    )),
  )
  |> dispatch_receive_eventually(
    dispatcher_name,
    recipe.iid,
    ReceiveClientUpdate(make_client_response(
      recipe.id,
      recipe.iid,
      sqrt_service_reference,
      "arg",
      "16",
    )),
  )
  // the recipe is updated and, bacause of the step being resolved to an argument,
  // the recipe is immediately re-submitted and the operand2 calculation is resolved
  |> expecting_recipe(
    recipe_id,
    recipe_iid,
    "calc operator:+ operand1:1.5 operand2:20.0",
    root_transformer,
  )
  |> expecting_status(
    calc_return_result(recipe.iid, "21.5", None, [
      Argument("operator", SerializedValue("+")),
      Argument("operand1", FloatValue(1.5)),
      Argument("operand2", FloatValue(20.0)),
    ])
    |> make_status(service_call.Completing),
  )
  |> expecting_statistics(
    Some(StatsRecord(
      client_request: 1,
      client_response: 1,
      dispatch_ack: 5,
      service_result: 5,
    )),
  )
}

fn expecting_recipe(
  maybe_result: Option(QueryResult),
  recipe_id: Option(String),
  recipe_instance_id: Option(String),
  expecting_recipe_description: String,
  root_transformer: Option(fn(recipe.ComposableStep) -> recipe.ComposableStep),
) -> Option(QueryResult) {
  // check the status within the (maybe) result against the expected status
  let recipe =
    maybe_result
    |> option.then(fn(result) {
      case result {
        State(state) -> Some(state.recipe)
        TimedOut -> None
      }
    })

  expecting_recipe_description
  |> make_recipe(recipe_id, recipe_instance_id, root_transformer)
  |> Some
  |> should.equal(recipe)

  maybe_result
}

fn expecting_status(
  maybe_result: Option(QueryResult),
  expecting: Option(RecipeExecutionStatus),
) -> Option(QueryResult) {
  // check the status within the (maybe) result against the expected status
  let status =
    maybe_result
    |> option.then(fn(result) {
      case result {
        State(state) -> Some(state.status)
        TimedOut -> None
      }
    })

  expecting |> should.equal(status)

  maybe_result
}

fn expecting_statistics(
  maybe_result: Option(QueryResult),
  expecting: Option(StatsRecord),
) -> Option(QueryResult) {
  // check the statistics within the (maybe) result against the expected statistics
  let statistics =
    maybe_result
    |> option.then(fn(result) {
      case result {
        State(state) -> Some(state.stats |> recipe_stats_as_record())
        TimedOut -> None
      }
    })

  expecting |> should.equal(statistics)

  maybe_result
}

fn dispatch_receive_immediate(
  dispatcher_name: Name(DispatcherServiceMessage),
  dispatch_message: DispatcherServiceMessage,
  receive_subject: Subject(ServiceCallResponse),
) -> Result(ServiceCallResponse, Nil) {
  dispatcher_name
  |> process.named_subject()
  |> process.send(dispatch_message)

  receive_subject
  |> process.receive(within: 100)
}

fn dispatch_receive_eventually(
  last_received: Option(QueryResult),
  dispatcher_name: Name(DispatcherServiceMessage),
  recipe_instance_id: String,
  message: DispatcherServiceMessage,
) -> Option(QueryResult) {
  dispatcher_name
  |> process.named_subject()
  |> process.send(message)

  receive_result(dispatcher_name, recipe_instance_id, last_received)
}

fn receive_result(
  dispatcher_name: Name(DispatcherServiceMessage),
  recipe_instance_id: String,
  last_received: Option(QueryResult),
) -> Option(QueryResult) {
  // try this number of times and then time out
  let intervals = list.repeat(100, times: 20)

  // poll until the result changes from the last_received value
  intervals
  |> list.fold_until(last_received, fn(acc, interval) {
    process.sleep(interval)
    let recipe_state = query_status(dispatcher_name, recipe_instance_id)
    case recipe_state {
      state if Some(State(state)) == acc -> list.Continue(acc)
      state -> list.Stop(Some(State(state)))
    }
  })
  |> fn(result) {
    case result, result == last_received {
      None, _ -> Some(TimedOut)
      Some(_), True -> Some(TimedOut)
      Some(status), False -> Some(status)
    }
  }
}

fn query_status(
  dispatcher_name: Name(DispatcherServiceMessage),
  recipe_instance_id: String,
) -> RecipeState {
  dispatcher_name
  |> process.named_subject()
  |> process.call(50, QueryStatus(recipe_instance_id, _))
}

fn convert_serialized_operands_to_float(
  arguments: Option(Arguments),
) -> Option(Arguments) {
  case arguments {
    Some(args) -> {
      args
      |> list.map(fn(arg) {
        // only convert the operands
        case arg.name {
          "operator" -> arg
          _ -> {
            let assert SerializedValue(str) = arg.value
            let assert Ok(value) =
              str
              |> parse_as_int_operand()
              |> result.try_recover(fn(v) { parse_as_float_operand(v) })
            Argument(arg.name, value)
          }
        }
      })
      |> Some
    }
    None -> None
  }
}

fn make_status(
  dispatcher_return: DispatcherReturn,
  client_recipe_state: ClientRecipeState,
) -> Option(RecipeExecutionStatus) {
  case dispatcher_return {
    DispatcherReturnServiceCall(recipe_instance_id: _, service_state:) ->
      make_execution_state(service_state, client_recipe_state)
    _ -> None
  }
}

fn make_execution_state(
  service_state: ServiceState,
  client_recipe_state: ClientRecipeState,
) -> Option(RecipeExecutionStatus) {
  case client_recipe_state {
    service_call.Pending -> dispatcher_store.Pending
    service_call.Requesting -> dispatcher_store.Requesting(service_state:)
    service_call.Stepping -> dispatcher_store.Resubmitting
    service_call.Completing -> dispatcher_store.Completing(service_state:)
    service_call.Suspending -> dispatcher_store.Suspending(None)
  }
  |> Some
}
