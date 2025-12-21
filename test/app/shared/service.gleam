import app/engine/dispatcher.{type DispatcherServiceMessage, QueryServices}
import gleam/erlang/process.{type Name}

pub fn query_services(
  dispatcher_name: Name(DispatcherServiceMessage),
) -> List(String) {
  dispatcher_name
  |> process.named_subject()
  |> process.call(50, QueryServices)
}
