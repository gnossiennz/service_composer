//// Types used by callers of the dispatcher service

import app/engine/dispatcher.{type DispatcherServiceMessage}
import app/types/dispatch.{type DispatchInfo}
import app/types/service.{type FullyQualifiedServiceName}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name}

pub type CallerInfo {
  CallerInfo(
    dispatcher: Name(DispatcherServiceMessage),
    service_dictionary: Dict(FullyQualifiedServiceName, DispatchInfo),
  )
}
