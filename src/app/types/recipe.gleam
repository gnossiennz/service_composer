//// Recipe types that describe a sequence or hierarchy of steps
//// that perform a composed action across service providers

import app/types/service.{type ServiceReference}
import gleam/option.{type Option}
import nibble

// ###################################################
// Recipe parsing types
// ###################################################

// Types used for parsing a recipe description (a human-readable but
// compact representation of the recipe steps)
// e.g. calc operator:+ operand1:3 operand2:5
// describes a single-step recipe for adding two integers
// using the 'calc' service provider
pub type TokenT {
  ServiceName(String)
  Name(String)
  Colon
  Value(String)
  SubstitutionStart
  SubstitutionEnd
}

pub type RecipeParseError {
  InternalParseError(List(nibble.DeadEnd(TokenT, Nil)))
  OtherError(String)
}

// ###################################################
// Recipe types
// ###################################################

// A recipe ID is currently a base64 encoded version of the recipe description
// It is shared across all recipes with the same recipe description
pub type RecipeID =
  String

// A recipe instance ID is unique to a running instance of a recipe
pub type RecipeInstanceID =
  String

pub type RecipeError {
  RecipeError(error: String, detail: Option(String))
}

// An instance is derived from a template but has an additional instance ID
pub type Recipe {
  Recipe(
    id: RecipeID,
    iid: RecipeInstanceID,
    description: Option(String),
    root: ComposableStep,
    error: Option(RecipeError),
  )
}

pub type ComposableStep {
  ComposableStep(
    // run_immediately: Bool,  // or add to ready or executing queues
    // run_on_child_request: Bool, // if true then look at 'arguments' to fulfill that request
    service: ServiceReference,
    arguments: Option(Arguments),
    substitutions: Option(Substitutions),
  )
}

pub type Substitution {
  Substitution(
    // parameter_reference: ParameterReference,
    name: String,
    step: ComposableStep,
  )
}

pub type Substitutions =
  List(Substitution)

// ###################################################
// Argument types
// ###################################################

pub type Argument {
  Argument(name: String, value: ArgumentValue)
}

pub type Arguments =
  List(Argument)

pub type ArgumentValue {
  NoArgument
  // NoArgument is a possible response to an optional argument
  SerializedValue(repr: String)
  IntValue(repr: Int)
  FloatValue(repr: Float)
  StringValue(repr: String)
  // ResourceValue(url: String, mime_type: String)
}
