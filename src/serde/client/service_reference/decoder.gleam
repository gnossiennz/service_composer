import app/types/service.{ServiceReference}
import gleam/dynamic/decode

pub fn get_service_decoder() {
  use name <- decode.field("name", decode.string)
  use path <- decode.field("path", decode.string)

  decode.success(ServiceReference(name:, path:))
}
