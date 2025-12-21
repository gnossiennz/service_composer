//// Deserialize client request specifications for logging of requests
//// See tests for an example

import app/types/client_request.{type RequestSpecification, RequestSpecification}
import app/types/definition.{
  type EntityType, type NumberEntity, type Reference, type RestrictedNumber,
  type RestrictedText, type TextEntity, LocalReference, NumberEntity, TextEntity,
}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}

pub fn decode(
  json_string: String,
) -> Result(RequestSpecification, json.DecodeError) {
  let decoder = get_request_specification_decoder()

  json.parse(from: json_string, using: decoder)
}

// For testing only (see serde/client/request/request_test)
pub fn decode_entity_type(
  json_string: String,
) -> Result(EntityType, json.DecodeError) {
  let entity_type_decoder = get_request_decoder()

  json.parse(from: json_string, using: entity_type_decoder)
}

// Called by service_return/decoder
pub fn get_request_specification_decoder() -> decode.Decoder(
  RequestSpecification,
) {
  use request <- decode.field("request", get_request_decoder())
  use name <- decode.field("name", decode.string)
  use required <- decode.field("required", decode.bool)
  use prompt <- decode.field("prompt", decode.string)

  decode.success(RequestSpecification(request:, name:, required:, prompt:))
}

fn get_request_decoder() -> decode.Decoder(EntityType) {
  let decode_resource = fn() {
    use reference <- decode.then(get_reference_decoder())
    decode.success(definition.Resource(reference))
  }

  let decode_number = fn() {
    use number <- decode.then(get_number_decoder())
    decode.success(definition.Scalar(number))
  }

  let decode_text = fn() {
    use txt <- decode.then(get_text_decoder())
    decode.success(definition.Bytes(txt))
  }

  use entity_type <- decode.field("type", decode.string)
  case entity_type {
    "reference" -> decode_resource()
    "number" -> decode_number()
    "text" -> decode_text()
    _ ->
      decode.failure(
        definition.Scalar(NumberEntity(definition.BaseNumberInt, None)),
        "EntityType",
      )
  }
}

fn get_reference_decoder() -> decode.Decoder(Reference) {
  use mime_type <- decode.field("mime_type", decode.string)

  decode.success(LocalReference(mime_type:))
}

fn get_number_decoder() -> decode.Decoder(NumberEntity) {
  let number_base_decoder = {
    use decoded_string <- decode.then(decode.string)
    case decoded_string {
      "IntOrFloat" -> decode.success(definition.BaseNumberIntOrFloat)
      "Int" -> decode.success(definition.BaseNumberInt)
      "Float" -> decode.success(definition.BaseNumberFloat)
      _ -> decode.failure(definition.BaseNumberIntOrFloat, "BaseNumber")
    }
  }

  use base <- decode.field("base", number_base_decoder)
  use specialization <- decode.then(get_restricted_number_decoder())

  decode.success(NumberEntity(base:, specialization:))
}

fn get_text_decoder() -> decode.Decoder(TextEntity) {
  let text_base_decoder = {
    use decoded_string <- decode.then(decode.string)
    case decoded_string {
      "String" -> decode.success(definition.BaseTextString)
      _ -> decode.failure(definition.BaseTextString, "BaseText")
    }
  }

  use base <- decode.field("base", text_base_decoder)
  use specialization <- decode.then(get_restricted_text_decoder())

  decode.success(TextEntity(base:, specialization:))
}

fn get_restricted_number_decoder() -> decode.Decoder(Option(RestrictedNumber)) {
  let number_explicit_decoder = {
    use explicit_type <- decode.field("type", decode.string)

    case explicit_type {
      "explicit" -> {
        use content <- decode.field("content", decode.list(decode.int))

        decode.success(definition.RestrictedNumberExplicit(content))
      }
      _ ->
        decode.failure(
          definition.RestrictedNumberExplicit([]),
          "RestrictedNumberExplicit",
        )
    }
  }

  let number_range_decoder = {
    let range_decoder = {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)

      decode.success(#(start, end))
    }

    use range_type <- decode.field("type", decode.string)

    case range_type {
      "range" -> {
        use #(start, end) <- decode.field("content", range_decoder)

        decode.success(definition.RestrictedNumberRange(start:, end:))
      }
      _ ->
        decode.failure(
          definition.RestrictedNumberRange(0, 0),
          "RestrictedNumberRange",
        )
    }
  }

  let number_named_decoder = {
    let named_decoder = {
      use number_range <- decode.then(decode.string)
      case number_range {
        "Positive" -> decode.success(definition.NumberRangePositive)
        "Negative" -> decode.success(definition.NumberRangeNegative)
        _ ->
          decode.failure(
            definition.NumberRangeNegative,
            "RestrictedNumberNamed",
          )
      }
    }

    use named_type <- decode.field("type", decode.string)

    case named_type {
      "named" -> {
        use name <- decode.field("content", named_decoder)

        decode.success(definition.RestrictedNumberNamed(name))
      }
      _ ->
        decode.failure(
          definition.RestrictedNumberNamed(definition.NumberRangeNegative),
          "RestrictedNumberNamed",
        )
    }
  }

  use maybe_restricted_number <- decode.optional_field(
    "specialization",
    None,
    decode.optional(
      decode.one_of(number_explicit_decoder, [
        number_named_decoder,
        number_range_decoder,
      ]),
    ),
  )

  decode.success(maybe_restricted_number)
}

fn get_restricted_text_decoder() -> decode.Decoder(Option(RestrictedText)) {
  let text_explicit_decoder = {
    use explicit_type <- decode.field("type", decode.string)

    case explicit_type {
      "explicit" -> {
        use content <- decode.field("content", decode.list(decode.string))

        decode.success(definition.RestrictedTextExplicit(content))
      }
      _ ->
        decode.failure(
          definition.RestrictedTextExplicit([]),
          "RestrictedTextExplicit",
        )
    }
  }

  use maybe_restricted_text <- decode.optional_field(
    "specialization",
    None,
    decode.optional(text_explicit_decoder),
  )

  decode.success(maybe_restricted_text)
}
