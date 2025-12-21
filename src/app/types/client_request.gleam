//// Request types issued by a provider service for requesting an argument

import app/types/definition.{type EntityType}

pub type ProviderServiceArgumentName =
  String

pub type RequestSpecification {
  RequestSpecification(
    request: EntityType,
    name: ProviderServiceArgumentName,
    required: Bool,
    // prompt: either a user (UI) prompt or an LLM prompt
    prompt: String,
  )
}
