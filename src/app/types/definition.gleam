//// Types that define Service argument and return values

import gleam/option.{type Option, None, Some}

/// The argument and return types for a service call
pub type ServiceInfo {
  ServiceInfo(arguments: List(ArgumentTypeInfo), returns: ServiceReturnType)
}

pub type ArgumentTypeInfo {
  ArgumentTypeInfo(argument_name: String, type_info: EntityType)
}

/// Specifies the expected type of a requested value
// This is the underlying value type being represented by a serialized representation
// A resource may be local or remote and has a URL and mimetype
// see recipe.ArgumentValue for the serialized representation of these types
pub type EntityType {
  Resource(Reference)
  Scalar(NumberEntity)
  Bytes(TextEntity)
}

pub type ServiceReturnType {
  ServiceReturnType(
    type_info: EntityType,
    passing_convention: ServiceReturnTypePassingConvention,
  )
}

// The returned value from a service call may be passed by value or by reference
// If passed by reference then the service composer may need to insert an intervening
// composable step in the recipe that retrieves the referred value
pub type ServiceReturnTypePassingConvention {
  ServiceReturnTypePassByValue
  ServiceReturnTypePassByReference
}

//******************************************************************
// Resource types
//******************************************************************

pub fn local_file(mime_type: String) -> EntityType {
  Resource(LocalReference(mime_type:))
}

pub type Reference {
  LocalReference(mime_type: String)
  // other non-local resource references such as an S3 bucket
}

//******************************************************************
// Number types
//******************************************************************

pub fn any_number() -> EntityType {
  Scalar(NumberEntity(base: BaseNumberIntOrFloat, specialization: None))
}

pub fn positive_number() -> EntityType {
  Scalar(NumberEntity(
    base: BaseNumberIntOrFloat,
    specialization: Some(RestrictedNumberNamed(NumberRangePositive)),
  ))
}

pub type BaseNumber {
  BaseNumberIntOrFloat
  BaseNumberInt
  BaseNumberFloat
}

pub type RestrictedNumber {
  RestrictedNumberExplicit(values: List(Int))
  RestrictedNumberRange(start: Int, end: Int)
  RestrictedNumberNamed(name: NumberRange)
}

pub type NumberRange {
  NumberRangePositive
  NumberRangeNegative
}

pub type NumberEntity {
  NumberEntity(base: BaseNumber, specialization: Option(RestrictedNumber))
}

//******************************************************************
// Text types
//******************************************************************

pub fn restricted_string(allowed: List(String)) -> EntityType {
  Bytes(TextEntity(
    base: BaseTextString,
    specialization: Some(RestrictedTextExplicit(allowed)),
  ))
}

pub type BaseText {
  BaseTextString
}

pub type RestrictedText {
  RestrictedTextExplicit(values: List(String))
}

pub type TextEntity {
  TextEntity(base: BaseText, specialization: Option(RestrictedText))
}
