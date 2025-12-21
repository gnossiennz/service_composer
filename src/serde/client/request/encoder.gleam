//// Serialize client request specifications for sending to a client

import app/types/client_request.{type RequestSpecification, RequestSpecification}
import app/types/definition.{
  type BaseNumber, type BaseText, type EntityType, type NumberEntity,
  type NumberRange, type Reference, type RestrictedNumber, type RestrictedText,
  type TextEntity, Bytes, NumberEntity, Resource, Scalar, TextEntity,
}
import gleam/json
import gleam/option.{type Option}

pub fn encode(request: RequestSpecification) -> String {
  request
  |> encode_fragment()
  |> json.to_string
}

/// Return a JSON fragment that describes a request specification
pub fn encode_fragment(request: RequestSpecification) -> json.Json {
  // Used by the ServiceReturn encoder to compose the final JSON document
  case request {
    RequestSpecification(request:, name:, required:, prompt:) ->
      encode_parts(request, name, required, prompt)
  }
}

fn encode_parts(
  request: EntityType,
  name: String,
  required: Bool,
  prompt: String,
) -> json.Json {
  json.object([
    serialize_request_type(request),
    #("name", json.string(name)),
    #("required", json.bool(required)),
    #("prompt", json.string(prompt)),
  ])
}

fn serialize_request_type(request: EntityType) -> #(String, json.Json) {
  let json = case request {
    Resource(reference) -> serialize_resource(reference)
    Scalar(number) -> serialize_number(number)
    Bytes(txt) -> serialize_text(txt)
  }

  #("request", json)
}

fn serialize_resource(reference: Reference) -> json.Json {
  case reference {
    definition.LocalReference(mime_type:) -> {
      json.object([
        #("type", json.string("reference")),
        #("mime_type", json.string(mime_type)),
      ])
    }
  }
}

fn serialize_number(number: NumberEntity) -> json.Json {
  let NumberEntity(base:, specialization:) = number

  json.object([
    #("type", json.string("number")),
    #("base", serialize_number_base(base)),
    #("specialization", serialize_number_specialization(specialization)),
  ])
}

fn serialize_number_base(base: BaseNumber) -> json.Json {
  case base {
    definition.BaseNumberIntOrFloat -> json.string("IntOrFloat")
    definition.BaseNumberInt -> json.string("Int")
    definition.BaseNumberFloat -> json.string("Float")
  }
}

fn serialize_number_specialization(
  specialization: Option(RestrictedNumber),
) -> json.Json {
  let serialize_number_range = fn(name: NumberRange) -> json.Json {
    case name {
      definition.NumberRangePositive -> json.string("Positive")
      definition.NumberRangeNegative -> json.string("Negative")
    }
  }

  specialization
  |> option.map(fn(restriction) {
    case restriction {
      definition.RestrictedNumberExplicit(values:) ->
        json.object([
          #("type", json.string("explicit")),
          #("content", json.array(values, of: json.int)),
        ])
      definition.RestrictedNumberRange(start:, end:) ->
        json.object([
          #("type", json.string("range")),
          #(
            "content",
            json.object([#("start", json.int(start)), #("end", json.int(end))]),
          ),
        ])
      definition.RestrictedNumberNamed(name:) ->
        json.object([
          #("type", json.string("named")),
          #("content", serialize_number_range(name)),
        ])
    }
  })
  |> option.unwrap(json.null())
}

fn serialize_text(txt: TextEntity) -> json.Json {
  let TextEntity(base:, specialization:) = txt

  json.object([
    #("type", json.string("text")),
    #("base", base |> serialize_text_base()),
    #("specialization", specialization |> serialize_text_specialization()),
  ])
}

fn serialize_text_base(base: BaseText) -> json.Json {
  case base {
    definition.BaseTextString -> json.string("String")
  }
}

fn serialize_text_specialization(
  specialization: Option(RestrictedText),
) -> json.Json {
  specialization
  |> option.map(fn(restriction) {
    case restriction {
      definition.RestrictedTextExplicit(values:) ->
        json.object([
          #("type", json.string("explicit")),
          #("content", json.array(values, of: json.string)),
        ])
    }
  })
  |> option.unwrap(json.null())
}
