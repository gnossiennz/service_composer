import app/types/composer.{
  type KeyValue, type ModuleLoader, type ResolverFunction,
}
import app/types/service.{type ServiceDescription}
import gleam/io
import gleam/list

@external(erlang, "Elixir.ProviderLoaderImpl", "load_modules")
pub fn load_modules(
  module_names: List(KeyValue),
  folder_path: String,
) -> ModuleLoader

pub fn load_providers(module_names: List(KeyValue), folder_path: String) {
  load_modules(module_names, folder_path)
}

pub fn notify_successes(
  successes: List(#(String, ServiceDescription, ResolverFunction)),
) -> Nil {
  successes
  |> list.each(fn(three_tuple) {
    let #(base_name, service_description, _resolver_fn) = three_tuple
    io.println(
      "Loaded: " <> base_name <> ":" <> service_description.reference.name,
    )
  })
}

pub fn notify_failures(failures: List(#(String, String))) -> Nil {
  failures
  |> list.each(fn(kv) {
    let #(key, message) = kv
    io.println("Warning: " <> key <> ": " <> message)
  })
}
