//// Types used in defining the service provider contract
//// and loading service provider modules

import app/types/recipe.{type Argument, type Arguments}
import app/types/service.{type ServiceDescription}
import app/types/service_call.{type DispatcherReturn}
import gleam/option.{type Option}

pub type KeyValue {
  KeyValue(key: String, value: String)
}

pub type ResolverFunction =
  fn(String, Option(Argument), Arguments) -> DispatcherReturn

pub type ModuleLoader {
  ModuleLoader(
    successes: List(#(String, ServiceDescription, ResolverFunction)),
    failures: List(#(String, String)),
  )
}
