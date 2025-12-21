//// Types used to uniquely define or describe a service provider

import gleam/result
import gleam/string
import gleam/string_tree

// ###################################################
// Service types
// ###################################################

pub type ServiceName =
  String

pub type ServicePath =
  String

pub type FullyQualifiedServiceName =
  String

/// The ServiceReference is used for service lookup and is also sent to the client
/// e.g. when sending service requests (for arguments) to the client
pub type ServiceReference {
  ServiceReference(
    // the name of the service e.g. calc
    name: ServiceName,
    // a unique path that becomes part of the name e.g. com.examples.service_composer
    path: ServicePath,
  )
}

/// Represent the service reference as a string for use as a dictionary key
pub fn make_service_name(
  service_reference: ServiceReference,
) -> FullyQualifiedServiceName {
  // The ServiceReference is ultimately a concatenation of the path and name
  // e.g. com.examples.service_composer:calc
  // however, it is useful to keep the two component parts separate
  [service_reference.path, ":", service_reference.name]
  |> string_tree.from_strings()
  |> string_tree.to_string()
}

/// Create a service reference from a fully qualified name
/// such as a service reference key
pub fn make_service_reference(
  fully_qualified_service_name: FullyQualifiedServiceName,
) -> Result(ServiceReference, Nil) {
  fully_qualified_service_name
  |> string.split_once(":")
  |> result.map(fn(parts) { ServiceReference(path: parts.0, name: parts.1) })
}

/// A ServiceDescription is exported from each service provider module
pub type ServiceDescription {
  ServiceDescription(
    reference: ServiceReference,
    // a human or LLM readable description of the service
    description: String,
  )
}
