import app/types/caller.{CallerInfo}
import gleam/erlang/process
import gleam/otp/static_supervisor as sup
import service_composer
import web/start_web

pub fn main() {
  let assert Ok(CallerInfo(dispatcher: named_dispatcher, service_dictionary:)) =
    service_composer.start_dispatcher()

  let assert Ok(_supervisor_started) =
    sup.new(sup.OneForOne)
    |> sup.add(start_web.supervised(named_dispatcher, service_dictionary))
    |> sup.start()

  // observer()

  process.sleep_forever()
}
// @external(erlang, "observer", "start")
// fn observer() -> x
