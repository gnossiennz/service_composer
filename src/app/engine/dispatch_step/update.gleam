//// Updates a recipe based on the result type of the service call

import app/types/recipe.{
  type Arguments, type ComposableStep, type Recipe, type Substitutions, Argument,
  ComposableStep, Recipe, SerializedValue, Substitution,
}
import app/types/service.{type ServiceReference}
import app/types/service_call.{
  type DispatcherReturn, type ServiceState, DispatcherReturnServiceCall,
  ServiceReturnRequest, ServiceReturnResult,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type MaybeSubstitutedRecipe {
  MaybeSubstitutedRecipe(substituted: Bool, recipe: Recipe)
}

type MaybeSubstitutedStep {
  MaybeSubstitutedStep(substituted: Bool, step: ComposableStep)
}

// fn decrec(step: ComposableStep) -> String {
//   step |> recipe_step_encoder.encode()
// }

// fn decrecl(steps: List(ComposableStep)) -> List(String) {
//   steps
//   |> list.map(fn(step) { step |> recipe_step_encoder.encode() })
// }

/// Update the recipe based on the service response type
/// Returns the updated recipe and a flag set to true if a substitution occurred
pub fn maybe_update_recipe(
  recipe: Recipe,
  dispatcher_return: DispatcherReturn,
) -> Result(MaybeSubstitutedRecipe, String) {
  // check that the instance has no errors
  use recipe <- result.try(recipe_is_okay(recipe))

  let MaybeSubstitutedStep(substituted:, step:) =
    maybe_rollup_recipe(dispatcher_return, recipe.root, [recipe.root])

  let updated_recipe = update_recipe(original_recipe: recipe, new_root: step)

  Ok(MaybeSubstitutedRecipe(substituted:, recipe: updated_recipe))
}

fn maybe_rollup_recipe(
  dispatcher_return: DispatcherReturn,
  current_step: ComposableStep,
  path: List(ComposableStep),
) -> MaybeSubstitutedStep {
  // Preconditions:
  // when the substitutions are all resolved then we remove the substitutions list
  // therefore the substitutions list is always either None or some non-empty list

  case current_step.substitutions {
    None -> {
      // this is a leaf node, the current (executing) step in the recipe
      // process the service response in the context of this step
      let maybe_updated_step =
        dispatcher_return
        |> process_service_response(path, current_step)

      maybe_updated_step
    }

    Some(substitutions_list) -> {
      // this is not a leaf node; drill further
      // assert: the substitutions list must be non-empty (because empty lists are removed)
      let assert Ok(sub) = list.first(substitutions_list)
      let Substitution(_name, step:) = sub

      maybe_rollup_recipe(dispatcher_return, step, [step, ..path])
    }
  }
}

fn process_service_response(
  dispatcher_return: DispatcherReturn,
  path: List(ComposableStep),
  current_step: ComposableStep,
) -> MaybeSubstitutedStep {
  // update the step according to the service response:
  //  for a request type, add the service-updated arguments to the step
  //  for an error type, return the step with no changes
  //  for a result type, substitute the child step result into the parent
  //    i.e. remove the substitution and add the result to the parent arguments

  case dispatcher_return {
    DispatcherReturnServiceCall(_recipe_instance_id, service_state) ->
      process_dispatch_return(service_state, path, current_step)
    _ -> MaybeSubstitutedStep(substituted: False, step: current_step)
  }
}

fn process_dispatch_return(
  service_state: ServiceState,
  path: List(ComposableStep),
  current_step: ComposableStep,
) {
  case service_state.service_return {
    ServiceReturnResult(result) -> {
      rollup_result(
        MaybeSubstitutedStep(substituted: False, step: current_step),
        path,
        result,
        service_state.service_state,
      )
    }
    ServiceReturnRequest(_request) -> {
      let new_root =
        rollup_request(current_step, path, service_state.service_state)

      MaybeSubstitutedStep(substituted: False, step: new_root)
    }
  }
}

fn rollup_request(
  root: ComposableStep,
  path: List(ComposableStep),
  updated_arguments: Option(Arguments),
) -> ComposableStep {
  // update the current step with the arguments
  // and propagate the updated steps to the root

  // echo #("rollup_request: ", decrec(root), decrecl(path), updated_arguments)

  // base case: list is empty
  // recursive case:
  //  - head is a leaf node (which has no substitutions)
  //  - or an intermediate node: create a new ComposableStep and rollup
  case path {
    [] -> root

    // match a leaf node at first level (and then update the argument state)
    [ComposableStep(_service, _arguments, substitutions: None)] -> {
      let updated_step =
        update_current_step(root.service, updated_arguments, root.substitutions)

      rollup_request(updated_step, [], updated_arguments)
    }

    // match a deeper leaf node (and then update the argument state)
    [ComposableStep(_service, _arguments, substitutions: None), ..rest] -> {
      let updated_step =
        update_current_step(root.service, updated_arguments, root.substitutions)

      rollup_request(updated_step, rest, updated_arguments)
    }

    // match any step with children
    [parent_step, ..rest] -> {
      let new_root = replace_first_child(parent_step, root)

      rollup_request(new_root, rest, updated_arguments)
    }
  }
}

fn rollup_result(
  root: MaybeSubstitutedStep,
  path: List(ComposableStep),
  result: String,
  updated_arguments: Option(Arguments),
) -> MaybeSubstitutedStep {
  // the head of path is the leaf node that just returned a result
  // replace the first substitution of each head up to the root
  // this first substitution will always exist as it is on the path

  // base case: list is empty
  // recursive case:
  //  - head is a leaf node (which has no substitutions)
  //  - or an intermediate node: create a new ComposableStep and rollup
  case path {
    [] -> root

    // match a leaf node at first level (and then update the argument state)
    [ComposableStep(_service, _arguments, substitutions: None)] -> {
      let MaybeSubstitutedStep(substituted:, step:) = root
      let updated_step =
        MaybeSubstitutedStep(
          substituted:,
          step: update_current_step(
            step.service,
            updated_arguments,
            step.substitutions,
          ),
        )

      rollup_result(updated_step, [], result, updated_arguments)
    }

    // match a deeper leaf node (skip this; we already have the result)
    [ComposableStep(_service, _arguments, substitutions: None), ..rest] ->
      rollup_result(root, rest, result, updated_arguments)

    // match a parent whose first substitution is a leaf node
    [
      ComposableStep(
        _service,
        _arguments,
        substitutions: Some([
          Substitution(
            _name,
            step: ComposableStep(_service, _arguments, substitutions: None),
          ),
          ..
        ]),
      ) as parent_step,
      ..rest
    ] -> {
      let new_root =
        MaybeSubstitutedStep(
          substituted: True,
          step: rollup_to_parent_step(parent_step, result),
        )

      rollup_result(new_root, rest, result, updated_arguments)
    }

    // match any other step with children
    [parent_step, ..rest] -> {
      let MaybeSubstitutedStep(substituted:, step:) = root
      let new_root =
        MaybeSubstitutedStep(
          substituted:,
          step: replace_first_child(parent_step, step),
        )

      rollup_result(new_root, rest, result, updated_arguments)
    }
  }
}

fn replace_first_child(
  parent_step: ComposableStep,
  replacement_child: ComposableStep,
) -> ComposableStep {
  let assert ComposableStep(
    service:,
    arguments:,
    substitutions: Some(substitutions),
  ) = parent_step

  let assert Ok(first_substitution) = list.first(substitutions)
  let Substitution(name, _step) = first_substitution
  let remaining_substitutions =
    substitutions |> list.rest() |> result.unwrap([])

  ComposableStep(
    service: service,
    arguments: arguments,
    substitutions: Some([
      Substitution(name:, step: replacement_child),
      ..remaining_substitutions
    ]),
  )
}

fn update_current_step(
  service: ServiceReference,
  updated_arguments: Option(Arguments),
  substitutions: Option(Substitutions),
) -> ComposableStep {
  ComposableStep(service:, arguments: updated_arguments, substitutions:)
}

fn rollup_to_parent_step(
  parent_step: ComposableStep,
  result: String,
) -> ComposableStep {
  // remove the first child and rollup the result
  // the update procedure is:
  //  - remove the first substitution
  //  - add an argument of the same name to arguments

  // the child step is always the first substitution
  // there must be at least one substitution for rollup
  let substitutions = parent_step.substitutions |> option.unwrap([])
  let assert Ok(first_substitution) = substitutions |> list.first()
  let remaining_substitutions = case substitutions |> list.rest() {
    Ok([]) -> None
    Ok(subs) -> Some(subs)
    Error(_) -> None
  }

  let arguments = parent_step.arguments |> option.unwrap([])

  ComposableStep(
    service: parent_step.service,
    arguments: Some([
      Argument(name: first_substitution.name, value: SerializedValue(result)),
      ..arguments
    ]),
    substitutions: remaining_substitutions,
  )
}

fn recipe_is_okay(recipe: Recipe) -> Result(Recipe, String) {
  case recipe {
    Recipe(id: _, iid: _, description: _, root: _, error: None) -> Ok(recipe)
    Recipe(id: _, iid: _, description: _, root: _, error: Some(_)) ->
      Error("Error in recipe")
  }
}

fn update_recipe(
  original_recipe original_recipe: Recipe,
  new_root new_root: ComposableStep,
) -> Recipe {
  let Recipe(id:, iid:, description:, root: _, error: _) = original_recipe

  Recipe(id:, iid:, description:, root: new_root, error: None)
}
