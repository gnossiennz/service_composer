import app/engine/dispatcher as dispatcher_service
import app/service_provider/provider_service
import app/types/caller.{type CallerInfo, CallerInfo}
import app/types/composer.{
  type KeyValue, type ModuleLoader, type ResolverFunction,
}
import app/types/dispatch.{type DispatchInfo, DispatchInfo}
import app/types/service.{
  type FullyQualifiedServiceName, type ServiceDescription, make_service_name,
}
import dot_env
import dot_env/env
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/static_supervisor as supervisor
import gleam/result
import provider/loader as provider_loader
import utilities/file.{get_base_name, get_beam_files}

// @external(erlang, "observer", "start")
// fn observer() -> x

pub fn main() -> Nil {
  Nil
  // let _ = start_dispatcher()
  // process.sleep_forever()
}

// Start the service composer dispatcher service
// This should be called from whatever system provides user interaction
// see examples/web for an example
pub fn start_dispatcher() -> Result(CallerInfo, String) {
  let service_provider_base = get_configured_beam_folder()

  service_provider_base
  |> start_dispatcher_impl()
  |> fn(result) {
    case result {
      Ok(_) -> io.println("Ready")
      Error(error) -> io.println("Startup failure: " <> error)
    }

    result
  }
}

pub fn start_dispatcher_impl(
  service_provider_base: String,
) -> Result(CallerInfo, String) {
  use all_beam_files <- result.try(get_beam_files(service_provider_base))

  // Map BEAM file base name to BEAM module name and load each module
  // The base name is used for traceability but not retained
  // Then start a service that wraps each module (the service providers)
  // and finally start the dispatcher service
  all_beam_files
  |> list.map(fn(file_path) { get_base_name(file_path, ".beam") })
  |> load_providers(service_provider_base)
  |> start_provider_services()
  |> start_dispatcher_supervisor()
}

fn load_providers(
  module_names: List(KeyValue),
  service_provider_base: String,
) -> ModuleLoader {
  // The module loader filters the BEAM files for those
  // that meet the required 'service provider protocol' (have three required functions)
  // Those BEAM files that pass are queried for their ServiceDescription
  io.print("Loading service providers from " <> service_provider_base <> ": ")
  let loader =
    provider_loader.load_providers(module_names, service_provider_base)
  io.println("done")

  io.println("")
  provider_loader.notify_successes(loader.successes)
  io.println("")
  provider_loader.notify_failures(loader.failures)

  loader
}

fn start_provider_services(
  loader: ModuleLoader,
) -> Result(Dict(FullyQualifiedServiceName, DispatchInfo), String) {
  let dispatch_info_resolver_list = loader.successes |> make_registered_name()
  let service_dictionary =
    dispatch_info_resolver_list |> make_service_dictionary()

  // Start all of the provider services (supervised)
  use _supervisor_start_result <- result.try(
    // Configure a supervisor to start the provider services
    // For each named resolver function, start a provider_service instance
    dispatch_info_resolver_list
    |> build_children()
    |> supervisor.start()
    |> result.map_error(fn(_start_error) { "Error starting provider services" }),
  )

  Ok(service_dictionary)
}

fn start_dispatcher_supervisor(
  children_startup_result: Result(
    Dict(FullyQualifiedServiceName, DispatchInfo),
    String,
  ),
) -> Result(CallerInfo, String) {
  use service_dictionary <- result.try(children_startup_result)

  let dispatcher_name = process.new_name("dispatcher")

  // now start the dispatcher service (supervised)
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(dispatcher_service.supervised(
    dispatcher_name,
    service_dictionary,
  ))
  |> supervisor.start()
  |> result.map(fn(_start_result) {
    CallerInfo(dispatcher: dispatcher_name, service_dictionary:)
  })
  |> result.map_error(fn(_start_error) { "Error starting provider services" })
}

fn build_children(
  resolvers: List(#(FullyQualifiedServiceName, DispatchInfo, ResolverFunction)),
) -> supervisor.Builder {
  resolvers
  |> list.fold(supervisor.new(supervisor.OneForOne), fn(builder, name_info_fn) {
    let #(_key, dispatch_info, resolver_fn) = name_info_fn

    builder
    |> supervisor.add(provider_service.supervised(
      dispatch_info.process_name,
      resolver_fn,
    ))
  })
}

fn make_registered_name(
  resolvers: List(#(String, ServiceDescription, ResolverFunction)),
) -> List(#(FullyQualifiedServiceName, DispatchInfo, ResolverFunction)) {
  resolvers
  |> list.map(fn(kv) {
    // create a registered name for each service
    // the key is just for traceability and can now be discarded
    let #(_key, service_desc, resolver_fn) = kv
    let fully_qualified_service_name = make_service_name(service_desc.reference)

    let dispatch_info =
      DispatchInfo(
        process_name: process.new_name(fully_qualified_service_name),
        description: service_desc,
      )

    #(fully_qualified_service_name, dispatch_info, resolver_fn)
  })
}

fn make_service_dictionary(
  associations: List(
    #(FullyQualifiedServiceName, DispatchInfo, ResolverFunction),
  ),
) -> Dict(FullyQualifiedServiceName, DispatchInfo) {
  associations
  |> list.map(fn(name_info_fn) {
    let #(fully_qualified_service_name, dispatch_info, _resolver_fn) =
      name_info_fn
    #(fully_qualified_service_name, dispatch_info)
  })
  |> dict.from_list()
}

fn get_configured_beam_folder() -> String {
  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(True)
  |> dot_env.load()

  let assert Ok(service_provider_base) = env.get_string("SERVICE_PROVIDER_BASE")
  service_provider_base
}
