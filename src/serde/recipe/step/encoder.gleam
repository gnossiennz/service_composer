import app/types/recipe.{type Argument, type ComposableStep}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string_tree.{type StringTree}
import serde/argument/value as argument_value

// Example: "calc operator:* operand:7 operand:(calc operator:+ operand:3)"

pub fn encode(root: ComposableStep) -> String {
  string_tree.new()
  |> encode_impl(root)
  |> string_tree.to_string()
}

fn encode_impl(accumulator: StringTree, root: ComposableStep) -> StringTree {
  let current =
    accumulator
    |> string_tree.append(root.service.name)
    |> append_arguments(root.arguments)

  case root.substitutions {
    None -> current
    Some(substitutions) -> {
      substitutions
      |> list.fold(current, fn(acc, substitution) {
        acc
        |> string_tree.append_tree(
          string_tree.from_strings([" ", substitution.name, ":("]),
        )
        |> encode_impl(substitution.step)
        |> string_tree.append(")")
      })
    }
  }
}

fn append_arguments(
  accumulator: StringTree,
  arguments: Option(List(Argument)),
) -> StringTree {
  case arguments {
    Some(arguments) -> {
      arguments
      |> list.fold(accumulator, fn(acc, argument) {
        acc
        |> string_tree.append(" ")
        |> append_argument(argument)
      })
    }
    None -> accumulator
  }
}

fn append_argument(accumulator: StringTree, argument: Argument) -> StringTree {
  accumulator
  |> string_tree.append(argument.name)
  |> string_tree.append(":")
  |> string_tree.append(argument_value.argument_value_to_string(argument.value))
}
