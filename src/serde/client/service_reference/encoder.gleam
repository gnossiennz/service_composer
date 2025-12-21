import app/types/service.{type ServiceReference}
import gleam/json

pub fn encode(service_reference: ServiceReference) -> String {
  service_reference
  |> encode_fragment()
  |> json.to_string
}

pub fn encode_fragment(service_reference: ServiceReference) -> json.Json {
  json.object([
    #("name", json.string(service_reference.name)),
    #("path", json.string(service_reference.path)),
  ])
}
