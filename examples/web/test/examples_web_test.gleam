import app/types/caller.{CallerInfo}
import app/types/client_request.{RequestSpecification}
import app/types/definition.{
  BaseTextString, Bytes, RestrictedTextExplicit, TextEntity,
}
import app/types/service.{ServiceReference}
import app/types/service_call.{
  type DispatcherReturn, type ServiceReturn, ServiceReturnRequest, ServiceState,
}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import serde/client/dispatcher_return/decoder as dispatcher_return_decoder
import service_composer

// import stratus

// TODO either get stratus working here
// OR test at a function level (i.e. rewrite router to support testing)

type Acknowledgement {
  Acknowledgement(
    msg_type: String,
    recipe_id: String,
    recipe_iid: String,
    ack_type: String,
    warning: Option(String),
  )
}

type State {
  ExpectingOperatorRequest
  ExpectingAcknowledgement
  ExpectingOperand1Request
}

type Msg {
  Close
  TimeUpdated(String)
  DoTheThing(Subject(Int))
}

// when the service asks for an 'operator' send this
pub const operator_response = "{
      \"service\": {
        \"name\": \"calc\",
        \"path\": \"com.examples.service_composer\"
      },
      \"response\": {
        \"name\": \"operator\",
        \"value\": {
          \"type\": \"Serialized\",
          \"value\": \"+\"
        }
      }
    }"

pub fn main() {
  gleeunit.main()
}

// pub fn simple_client_connection_test() {
//   let assert Ok(CallerInfo(dispatcher: _, service_dictionary: _)) =
//     service_composer.start_dispatcher()

//   let assert Ok(req) = request.to("localhost:3000/ws")

//   let builder =
//     stratus.websocket(
//       request: req,
//       init: fn() { #(ExpectingOperatorRequest, None) },
//       loop: fn(state, msg, conn) {
//         case msg {
//           stratus.Text(msg) -> {
//             echo "Got a message: " <> msg

//             case state {
//               ExpectingOperatorRequest -> {
//                 // first, expect a request
//                 handle_request(msg)
//                 // then (after sending a response), expect an ack, and another request
//                 stratus.continue(ExpectingAcknowledgement)
//               }
//               ExpectingAcknowledgement -> {
//                 handle_acknowledgement(msg)
//                 stratus.continue(ExpectingOperand1Request)
//               }
//               ExpectingOperand1Request -> {
//                 // TODO
//                 stratus.continue(ExpectingOperand1Request)
//               }
//             }
//           }
//           stratus.User(TimeUpdated(msg)) -> {
//             let assert Ok(_resp) = stratus.send_text_message(conn, msg)
//             stratus.continue(state)
//           }
//           stratus.User(DoTheThing(resp)) -> {
//             process.send(resp, 1234)
//             stratus.continue(state)
//           }
//           stratus.Binary(_msg) -> stratus.continue(state)
//           stratus.User(Close) -> {
//             let assert Ok(_) =
//               stratus.close_with_reason(conn, stratus.GoingAway(<<"goodbye">>))
//             stratus.stop()
//           }
//         }
//       },
//     )
//     |> stratus.on_close(fn(_state) { io.println("oh noooo") })

//   let assert Ok(subj) = stratus.initialize(builder)

//   process.spawn(fn() {
//     process.sleep(6000)

//     stratus.to_user_message(Close)
//     |> process.send(subj.data, _)
//   })

//   process.spawn(fn() {
//     process.sleep(500)
//     let resp =
//       process.call(subj.data, 100, fn(subj) {
//         stratus.to_user_message(DoTheThing(subj))
//       })
//     echo #("got the thing", resp)
//     process.sleep(1000)
//     let resp =
//       process.call_forever(subj.data, fn(subj) {
//         stratus.to_user_message(DoTheThing(subj))
//       })
//     echo #("got the thing pt 2", resp)
//   })
// }

fn handle_request(recipe_instance_id, service_state, msg: String) -> Nil {
  msg
  |> dispatcher_return_decoder.decode()
  |> should.be_ok()
  |> should.equal(get_expected_request_for_operator(
    recipe_instance_id,
    service_state,
  ))
}

fn handle_acknowledgement(msg: String) -> Nil {
  msg
  |> decode_acknowledgement()
  |> should.be_ok()
  |> should.equal(get_expected_acknowledgement())
}

fn get_expected_acknowledgement() -> Acknowledgement {
  Acknowledgement(
    msg_type: "ack",
    recipe_id: "some_id",
    recipe_iid: "some_iid",
    ack_type: "received_client_update",
    warning: None,
  )
}

fn decode_acknowledgement(
  json_string: String,
) -> Result(Acknowledgement, json.DecodeError) {
  json.parse(from: json_string, using: get_acknowledgement_decoder())
}

fn get_acknowledgement_decoder() -> decode.Decoder(Acknowledgement) {
  use msg_type <- decode.field("type", decode.string)
  use recipe_id <- decode.field("recipe_id", decode.string)
  use recipe_iid <- decode.field("recipe_iid", decode.string)
  use ack_type <- decode.field("ack_type", decode.string)
  use warning <- decode.optional_field(
    "warning",
    None,
    decode.optional(decode.string),
  )

  decode.success(Acknowledgement(
    msg_type:,
    recipe_id:,
    recipe_iid:,
    ack_type:,
    warning:,
  ))
}

fn get_expected_request_for_operator(
  recipe_instance_id,
  service_state,
) -> DispatcherReturn {
  service_call.DispatcherReturnServiceCall(
    recipe_instance_id:,
    service_state: ServiceState(
      service: ServiceReference(
        name: "calc",
        path: "com.examples.service_composer",
      ),
      service_state:,
      service_return: ServiceReturnRequest(request: RequestSpecification(
        request: Bytes(TextEntity(
          BaseTextString,
          Some(RestrictedTextExplicit(["+", "-"])),
        )),
        name: "operator",
        required: True,
        prompt: "Provide a calculation operator (one of: +, -, * or /)",
      )),
      warning: None,
    ),
  )
}
