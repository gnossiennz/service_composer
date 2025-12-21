import app/engine/dispatcher.{type DispatcherServiceMessage}
import app/types/dispatch.{type DispatchInfo}
import app/types/service.{type FullyQualifiedServiceName}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision.{type ChildSpecification}
import mist
import web/context.{Context}
import web/router

pub fn supervised(
  dispatcher: Name(DispatcherServiceMessage),
  service_dictionary: Dict(FullyQualifiedServiceName, DispatchInfo),
) -> ChildSpecification(supervisor.Supervisor) {
  supervision.worker(fn() { start(dispatcher, service_dictionary) })
}

fn start(
  dispatcher: Name(DispatcherServiceMessage),
  service_dictionary: Dict(FullyQualifiedServiceName, DispatchInfo),
) {
  let context = Context(dispatcher:, service_dictionary:)
  let handler = router.handle_request(_, context)

  let assert Ok(_) =
    handler
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(3000)
    |> mist.start()
}
