import app/types/composer.{type ResolverFunction, KeyValue}
import app/types/recipe.{Argument, FloatValue}
import app/types/service_call.{
  type DispatcherReturn, DispatcherReturnServiceCall,
}
import dot_env
import dot_env/env
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import provider/loader as provider_loader

pub fn main() {
  gleeunit.main()
}

pub fn folder_not_exist_test() {
  // attempt to load from a folder that doesn't exist
  let result =
    provider_loader.load_modules(
      [KeyValue("test", "no_such_module")],
      "no_such_folder",
    )

  result.successes |> should.equal([])
  result.failures |> should.equal([#("", "Module loader rejected folder path")])
}

pub fn module_not_found_test() {
  let module_base = get_module_base()

  // attempt to load a module that doesn't exist
  let result =
    provider_loader.load_modules(
      [KeyValue("test", "no_such_module")],
      module_base,
    )

  result.successes |> should.equal([])
  result.failures
  |> should.equal([#("test", "Module not found: no_such_module")])
}

pub fn no_resolver_function_test() {
  let module_base = get_module_base()

  // load an existing module that has no compatible resolve function
  let result =
    provider_loader.load_modules(
      [KeyValue("test", "service_composer")],
      module_base,
    )

  result.successes |> should.equal([])
  result.failures
  |> should.equal([#("test", "No resolver function on service_composer")])
}

pub fn known_providers_should_load_test() {
  // load some compatible provider modules
  // and test call the resolver functions
  let folder_path = "build/dev/erlang/service_composer/ebin"
  let module_names = [
    KeyValue("sqrt_id", "service_providers@sqrt"),
    KeyValue("calc_id", "service_providers@calc"),
  ]

  let result = provider_loader.load_modules(module_names, folder_path)
  // Normally the service_id is used to lookup the service name
  // (i.e. the name of the actor that wraps the required resolver function)
  // As this is just a local lookup we can just use the keys defined above
  let provider_dictionary =
    result.successes
    |> list.map(fn(key_serviceid_resolver) {
      let #(key, _service_id, resolver) = key_serviceid_resolver
      #(key, resolver)
    })
    |> dict.from_list()

  call_resolver(provider_dictionary, "sqrt_id")
  |> check_has_response()
  |> should.be_true()
  call_resolver(provider_dictionary, "calc_id")
  |> check_has_response()
  |> should.be_true()
  call_resolver(provider_dictionary, "no_such_module_id")
  |> check_has_response()
  |> should.be_false()
}

fn get_module_base() {
  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.load()

  let assert Ok(service_provider_base) = env.get_string("SERVICE_PROVIDER_BASE")

  service_provider_base
}

fn check_has_response(result: Option(DispatcherReturn)) -> Bool {
  case result {
    Some(return) -> check_is_expected_response(return)
    None -> False
  }
}

fn check_is_expected_response(dispatcher_return: DispatcherReturn) -> Bool {
  case dispatcher_return {
    DispatcherReturnServiceCall(_, _) -> True
    _ -> False
  }
}

fn call_resolver(
  resolver_dict: Dict(String, ResolverFunction),
  key: String,
) -> Option(DispatcherReturn) {
  case dict.has_key(resolver_dict, key) {
    True -> {
      let assert Ok(resolver) = dict.get(resolver_dict, key)
      let result =
        resolver("123", None, [Argument(name: "arg", value: FloatValue(4.0))])
      Some(result)
    }
    False -> None
  }
}
