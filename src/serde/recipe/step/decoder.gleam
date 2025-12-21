//// Deserialize a recipe step
//// A recipe step has a hierarchical structure
//// that may be composed of many embedded sub-steps

import app/types/recipe.{
  type Argument, type ComposableStep, type RecipeParseError, type Substitution,
  type TokenT, Argument, Colon, ComposableStep, InternalParseError, Name,
  OtherError, SerializedValue, ServiceName, Substitution, SubstitutionEnd,
  SubstitutionStart, Value,
}
import app/types/service.{
  type FullyQualifiedServiceName, type ServiceName, make_service_reference,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import nibble.{DeadEnd, do, return}
import nibble/lexer.{NoMatchFound}

type LexerMode {
  NormalParsing
  ArgumentParsing
}

type SubstitutableArgument {
  SimpleArgument(Argument)
  SubstitutedArgument(Substitution)
}

type SubstitutableValue {
  SimpleValue(String)
  SubstitutedValue(ComposableStep)
}

/// Decode a recipe step description
/// input: the recipe description
/// services_dict: a dictionary that maps short versions to long versions of service names
pub fn decode(
  input: String,
  services_dict: dict.Dict(ServiceName, FullyQualifiedServiceName),
) -> Result(ComposableStep, String) {
  // parse a recipe description such as:
  // "calc operator:* operand:7 operand:(calc operator:+ operand:3)"

  let lexer = {
    fn(mode) {
      case mode {
        NormalParsing -> get_normal_mode_matchers(services_dict)
        ArgumentParsing -> get_argument_mode_matchers()
      }
    }
    |> lexer.advanced()
  }

  let parser = {
    use fully_qualified_service_name <- do(service_parser(services_dict))
    use args <- do(arguments_parser(substitution_parser(services_dict)))

    case make_step(fully_qualified_service_name, args) {
      Some(step) -> return(SubstitutedValue(step))
      None -> nibble.throw("Failed parsing service reference")
    }
  }

  case lexer.run_advanced(input, NormalParsing, lexer) {
    Ok(tokens) ->
      case nibble.run(tokens, parser) {
        Ok(SubstitutedValue(step)) -> Ok(step)
        Ok(SimpleValue(str)) ->
          Error(OtherError(str) |> recipe_parse_error_to_string())
        Error(dead_ends) ->
          Error(
            InternalParseError(dead_ends)
            |> recipe_parse_error_to_string(),
          )
      }
    Error(error) -> {
      let NoMatchFound(row:, col:, lexeme:) = error
      let description =
        "Tokenizer error: no match found for lexeme: "
        <> lexeme
        <> " at ("
        <> int.to_string(row)
        <> ", "
        <> int.to_string(col)
        <> ")"
      Error(OtherError(description) |> recipe_parse_error_to_string())
    }
  }
}

fn get_normal_mode_matchers(services_dict: dict.Dict(String, String)) {
  services_dict
  |> dict.to_list()
  |> list.map(fn(key_id_token) {
    // match anything in this list of service names (exact match)
    // key: the name of the service e.g. calc
    // id: the service reference unique ID
    let #(key, _id) = key_id_token
    lexer.token(key, ServiceName(key))
  })
  |> list.append([
    lexer.into(
      // anything that is not a number, whitespace, colon, hash or parentheses
      // starts an argument identifier (continued by any non-whitespace)
      lexer.identifier("[^0-9\\s:#\\(\\)]", "[^\\s:]", set.new(), Name),
      fn(_mode) { ArgumentParsing },
    ),
    lexer.token(")", SubstitutionEnd),
    lexer.whitespace(Nil) |> lexer.ignore,
  ])
}

fn get_argument_mode_matchers() {
  [
    lexer.token(":", Colon),
    lexer.into(lexer.token("(", SubstitutionStart), fn(_mode) { NormalParsing }),
    lexer.into(
      lexer.identifier("[^\\s\\)]", "[^\\s\\)]", set.new(), Value),
      fn(_mode) { NormalParsing },
    ),
  ]
}

fn servicename_parser() {
  use tok <- nibble.take_map("expected a service name")
  case tok {
    ServiceName(name) -> Some(name)
    _ -> None
  }
}

fn name_parser() {
  use tok <- nibble.take_map("expected an argument name")
  case tok {
    Name(name) -> Some(name)
    _ -> None
  }
}

fn value_parser() {
  use tok <- nibble.take_map("expected an argument value")
  case tok {
    Value(value) -> Some(SimpleValue(value))
    _ -> None
  }
}

fn service_parser(services_dict) {
  use servicename <- do(servicename_parser())

  // the services dictionary maps service short names to fully qualified names
  let maybe_fully_qualified_name = services_dict |> dict.get(servicename)

  case maybe_fully_qualified_name {
    Ok(fully_qualified_name) -> return(fully_qualified_name)
    Error(_) -> nibble.fail("Service ID lookup failed")
  }
}

fn argument_parser(
  lazy_substitution_parser: nibble.Parser(SubstitutableValue, TokenT, a),
) {
  use name <- do(name_parser())
  use _ <- do(nibble.token(Colon))
  use value <- do(nibble.one_of([lazy_substitution_parser, value_parser()]))

  case value {
    SimpleValue(value) ->
      return(SimpleArgument(Argument(name, SerializedValue(value))))
    SubstitutedValue(substitution) ->
      return(SubstitutedArgument(Substitution(name, substitution)))
  }
}

fn arguments_parser(
  lazy_substitution_parser: nibble.Parser(SubstitutableValue, TokenT, a),
) {
  use args <- do(
    nibble.optional(nibble.many1(argument_parser(lazy_substitution_parser))),
  )

  return(args)
}

fn substitution_parser(services_dict) {
  use _ <- do(nibble.token(SubstitutionStart))
  use fully_qualified_service_name <- do(service_parser(services_dict))
  use args <- do(arguments_parser(substitution_parser(services_dict)))
  use _ <- do(nibble.token(SubstitutionEnd))

  case make_step(fully_qualified_service_name, args) {
    Some(step) -> return(SubstitutedValue(step))
    None -> nibble.throw("Failed parsing service reference")
  }
}

fn make_step(
  fully_qualified_service_name: String,
  args: Option(List(SubstitutableArgument)),
) -> Option(ComposableStep) {
  let #(resolved, substituted) =
    option.unwrap(args, [])
    |> list.fold(#([], []), fn(acc, arg) {
      let #(resolved, substituted) = acc
      case arg {
        SimpleArgument(arg) -> #([arg, ..resolved], substituted)
        SubstitutedArgument(arg) -> #(resolved, [arg, ..substituted])
      }
    })

  let wrap = fn(args: List(a)) {
    case args {
      [] -> None
      _ -> Some(args |> list.reverse())
    }
  }

  // Making a ServiceReference from a fully qualified service name will always succeed
  // when decoding service refs created using the recipe encoder
  case make_service_reference(fully_qualified_service_name) {
    Ok(service_reference) ->
      Some(ComposableStep(
        service: service_reference,
        arguments: wrap(resolved),
        substitutions: wrap(substituted),
      ))
    Error(Nil) -> None
  }
}

fn recipe_parse_error_to_string(parse_error: RecipeParseError) -> String {
  case parse_error {
    InternalParseError(dead_ends) -> {
      case dead_ends {
        [] -> ""
        [DeadEnd(_, problem, _), ..] -> nibble_error_to_string(problem)
      }
    }
    OtherError(err) -> err
  }
}

pub fn nibble_error_to_string(nibble_error: nibble.Error(TokenT)) -> String {
  case nibble_error {
    nibble.BadParser(str) -> str
    nibble.Custom(str) -> str
    nibble.EndOfInput -> "EndOfInput"
    nibble.Expected(str, got: tok) ->
      "Expected(" <> str <> "), got: " <> token_type_to_string(tok)
    nibble.Unexpected(tok) -> "Unexpected token: " <> token_type_to_string(tok)
  }
}

fn token_type_to_string(token: TokenT) -> String {
  case token {
    ServiceName(_) -> "ServiceName"
    Name(name) -> "Name(" <> name <> ")"
    Colon -> "Colon"
    Value(value) -> "Value(" <> value <> ")"
    SubstitutionStart -> "SubstitutionStart"
    SubstitutionEnd -> "SubstitutionEnd"
  }
}
