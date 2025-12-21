//// Test decoding of service responses that are request-type responses
//// i.e. when the service makes a request to a client for argument values

import app/types/client_request.{type RequestSpecification, RequestSpecification}
import app/types/definition.{
  BaseNumberFloat, BaseNumberInt, BaseNumberIntOrFloat, BaseTextString, Bytes,
  LocalReference, NumberEntity, NumberRangePositive, Resource,
  RestrictedNumberNamed, RestrictedNumberRange, RestrictedTextExplicit, Scalar,
  TextEntity,
}
import gleam/json.{UnableToDecode}
import gleam/option.{Some}
import gleeunit
import gleeunit/should
import serde/client/request/decoder as request_decoder
import serde/client/request/encoder as request_encoder

pub fn main() {
  gleeunit.main()
}

// ###############################################
// Entity type decoding tests
// ###############################################

pub fn explicit_range_text_test() {
  let encoded =
    "{
        \"type\":\"text\",
        \"base\":\"String\",
        \"specialization\": {
          \"type\":\"explicit\",
          \"content\": [
            \"+\", \"-\"
          ]
        }
      }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_ok()
  |> should.equal(
    Bytes(TextEntity(BaseTextString, Some(RestrictedTextExplicit(["+", "-"])))),
  )
}

pub fn explicit_range_number_test() {
  let encoded =
    "{
        \"type\":\"number\",
        \"base\":\"Int\",
        \"specialization\": {
          \"type\":\"explicit\",
          \"content\": [
            1, 2, 3, 4
          ]
        }
      }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_ok()
  |> should.equal(
    Scalar(NumberEntity(
      BaseNumberInt,
      Some(definition.RestrictedNumberExplicit([1, 2, 3, 4])),
    )),
  )
}

pub fn defined_range_number_test() {
  let encoded =
    "{
        \"type\":\"number\",
        \"base\":\"IntOrFloat\",
        \"specialization\": {
          \"type\":\"range\",
          \"content\": {
            \"start\":1,\"end\":10
          }
        }
      }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_ok()
  |> should.equal(
    Scalar(NumberEntity(
      BaseNumberIntOrFloat,
      Some(RestrictedNumberRange(1, 10)),
    )),
  )
}

pub fn named_range_number_test() {
  let encoded =
    "{
        \"type\":\"number\",
        \"base\":\"Float\",
        \"specialization\": {
          \"type\":\"named\",
          \"content\": \"Positive\"
        }
      }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_ok()
  |> should.equal(
    Scalar(NumberEntity(
      BaseNumberFloat,
      Some(RestrictedNumberNamed(NumberRangePositive)),
    )),
  )
}

pub fn unknown_specialization_number_test() {
  let encoded =
    "{
        \"type\":\"number\",
        \"base\":\"Float\",
        \"specialization\": {
          \"type\":\"unknown\",
          \"content\": \"unknown\"
        }
      }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_error()
  |> fn(error) {
    case error {
      UnableToDecode(_) -> True
      _ -> False
    }
  }
  |> should.be_true()
}

pub fn unknown_entity_type_test() {
  let encoded =
    "{
        \"type\":\"unknown\"
     }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_error()
  |> fn(error) {
    case error {
      UnableToDecode(_) -> True
      _ -> False
    }
  }
  |> should.be_true()
}

pub fn local_reference_test() {
  let encoded =
    "{
        \"type\":\"reference\",
        \"mime_type\": \"image/png\"
     }"

  encoded
  |> request_decoder.decode_entity_type()
  |> should.be_ok()
  |> should.equal(Resource(LocalReference("image/png")))
}

// ###############################################
// Request tests
// ###############################################

pub fn request_decode_operator_test() {
  let request =
    "{
            \"request\":
              {
                \"type\":\"text\",
                \"base\":\"String\",
                \"specialization\": {
                  \"type\":\"explicit\",
                  \"content\": [
                    \"+\", \"-\"
                  ]
                }
              },
            \"name\": \"operator\",
            \"required\": true,
            \"prompt\": \"The calculation operator (such as + or -)\"
        }"

  request
  |> request_decoder.decode()
  |> should.be_ok()
  |> should.equal(RequestSpecification(
    request: Bytes(TextEntity(
      BaseTextString,
      Some(RestrictedTextExplicit(["+", "-"])),
    )),
    name: "operator",
    required: True,
    prompt: "The calculation operator (such as + or -)",
  ))
}

pub fn request_decode_operand_test() {
  let request =
    "{
        \"request\": {
          \"type\": \"number\",
          \"base\": \"IntOrFloat\",
          \"specialization\": {
            \"type\": \"range\",
            \"content\": {
              \"start\": 0,
              \"end\": 10
              }
            }
         },
         \"name\": \"operand1\",
         \"required\": false,
         \"prompt\": \"The first operand\"
        }"

  request
  |> request_decoder.decode()
  |> should.be_ok()
  |> should.equal(RequestSpecification(
    request: Scalar(NumberEntity(
      BaseNumberIntOrFloat,
      Some(RestrictedNumberRange(0, 10)),
    )),
    name: "operand1",
    required: False,
    prompt: "The first operand",
  ))
}

pub fn request_decode_filepath_entity_test() {
  let request =
    "{
            \"request\": {
                \"type\":\"reference\",
                \"path\":\"a/b/c\",
                \"mime_type\": \"image/png\"
            },
            \"name\": \"file_path\",
            \"required\": false,
            \"prompt\": \"An optional file path to a PNG image file\"
       }"

  request
  |> request_decoder.decode()
  |> should.be_ok()
  |> should.equal(RequestSpecification(
    request: Resource(LocalReference("image/png")),
    name: "file_path",
    required: False,
    prompt: "An optional file path to a PNG image file",
  ))
}

// ###############################################
// Round-trip request specification serde tests
// ###############################################

pub fn round_trip_operator_explicit_range_test() {
  roundtrip_request(RequestSpecification(
    request: Bytes(TextEntity(BaseTextString, Some(RestrictedTextExplicit([])))),
    name: "operator",
    required: False,
    prompt: "The optional operator",
  ))

  roundtrip_request(RequestSpecification(
    request: Bytes(TextEntity(
      BaseTextString,
      Some(RestrictedTextExplicit(["X", "Y", "Z"])),
    )),
    name: "operator",
    required: True,
    prompt: "The required operator with values",
  ))
}

pub fn round_trip_operand_defined_range_test() {
  roundtrip_request(RequestSpecification(
    request: Scalar(NumberEntity(
      BaseNumberIntOrFloat,
      Some(RestrictedNumberRange(start: 0, end: 10)),
    )),
    name: "operand1",
    required: True,
    prompt: "The first operand must be in the specified range",
  ))
}

pub fn round_trip_operand_named_range_test() {
  roundtrip_request(RequestSpecification(
    request: Scalar(NumberEntity(
      BaseNumberInt,
      Some(RestrictedNumberNamed(NumberRangePositive)),
    )),
    name: "operand1",
    required: True,
    prompt: "The first operand must be within the named range",
  ))
}

pub fn round_trip_filepath_request_test() {
  roundtrip_request(RequestSpecification(
    request: Resource(LocalReference(mime_type: "image/png")),
    name: "file_path",
    required: True,
    prompt: "The argument must be a local reference (file path) to a PNG image",
  ))
}

fn roundtrip_request(ui_request: RequestSpecification) {
  // round-trip serialization/deserialization
  ui_request
  |> request_encoder.encode()
  |> request_decoder.decode()
  |> should.be_ok()
  |> should.equal(ui_request)
}
