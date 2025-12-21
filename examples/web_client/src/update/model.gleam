import app/types/client_request.{type RequestSpecification}
import app/types/recipe.{type Arguments, type RecipeID, type RecipeInstanceID}
import app/types/service.{type ServiceReference}
import app/types/service_call.{
  type DispatcherReturn, ClientResponseHydrationError,
  DispatcherReturnHydrationError, DispatcherReturnServiceCall,
  ServiceReturnRequest, ServiceReturnResult, ServiceState,
}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_tree.{type StringTree}
import serde/argument/value as argument_value_encoder
import serde/error/json as decode_error
import serde/wrapped/decoder as wrapped_decoder
import types/error.{WrapperDecodeError, WrapperGeneralError}
import types/interaction.{
  type CurrentInteraction, CurrentInteraction, PastInteraction,
}
import types/model.{
  type Model, type RecipeEvolution, type RecipeInteractionInstance, Model,
  RecipeEvolution, RecipeInteractionInstance,
}
import types/web_api_acknowledgement.{
  type WebAPIAcknowledgement, ReceivedClientUpdate, ReceivedNewRecipe,
  WebAPIAcknowledgement,
}
import types/web_api_wrapper.{
  type RecipeEntry, type RecipeInstanceStatistics, type WebAPIWrapper,
  ClientDeserializationError, GeneralError, WrappedAcknowledgement, WrappedError,
  WrappedRecipeList, WrappedRecipeStatistics, WrappedResponse,
}

pub fn update_user_response(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  response: String,
) -> Model {
  model
  |> update_current_interaction(instance_id, user_response_updater(response))
}

pub fn update_sent_flag(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  response_sent: Bool,
) -> Model {
  model
  |> update_current_interaction(
    instance_id,
    response_sent_flag_updater(response_sent),
  )
}

pub fn update_acknowledged_flag(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  response_acknowledged: Bool,
) -> Model {
  model
  |> update_current_interaction(
    instance_id,
    response_acknowledged_flag_updater(response_acknowledged),
  )
}

pub fn add_global_notification(model: Model, message: String) -> Model {
  Model(..model, notifications: [message, ..model.notifications])
}

pub fn add_instance_warning(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  warning: Option(String),
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    RecipeInteractionInstance(
      ..instance,
      warnings: warning
        |> option.map(fn(warning) { [warning, ..instance.warnings] })
        |> option.unwrap(instance.warnings),
    )
  })
}

pub fn handle_raw_message(model: Model, message: String) -> Model {
  message
  |> wrapped_decoder.decode()
  |> result.map(fn(wrapper) { handle_wrapper(model, wrapper) })
  |> result.try_recover(fn(err) {
    Ok(
      Model(..model, errors: [
        WrapperDecodeError(decode_error.describe_error(err)),
        ..model.errors
      ]),
    )
  })
  |> result.unwrap(model)
}

// ###################################################
// External data model update functions
// ###################################################

fn handle_wrapper(model: Model, wrapper: WebAPIWrapper) -> Model {
  case wrapper {
    WrappedResponse(dispatcher_return) ->
      handle_service_return(model, dispatcher_return)
    WrappedAcknowledgement(acknowledgement) ->
      handle_acknowledgement(model, acknowledgement)
    WrappedRecipeList(recipe_list) -> handle_recipe_list(model, recipe_list)
    WrappedRecipeStatistics(instance_stats) ->
      handle_recipe_stats(model, instance_stats)
    WrappedError(error) -> {
      case error {
        ClientDeserializationError(dispatcher_return) ->
          handle_deser_error(model, dispatcher_return)
        GeneralError(error) -> handle_general_error(model, error)
      }
    }
  }
}

fn handle_service_return(
  model: Model,
  dispatcher_return: DispatcherReturn,
) -> Model {
  case dispatcher_return {
    DispatcherReturnServiceCall(recipe_instance_id:, service_state:) -> {
      let ServiceState(service:, service_return:, service_state:, warning:) =
        service_state

      case service_return {
        ServiceReturnRequest(request:) -> {
          echo "prepare_new_interaction"
          prepare_new_interaction(
            model,
            recipe_instance_id,
            service,
            request,
            warning,
            service_state,
          )
        }
        ServiceReturnResult(result:) -> {
          finalize_interactions(
            model,
            recipe_instance_id,
            service,
            result,
            warning,
            service_state,
          )
        }
      }
    }

    _ -> model
  }
}

fn handle_acknowledgement(
  model: Model,
  acknowledgement: WebAPIAcknowledgement,
) -> Model {
  let WebAPIAcknowledgement(
    recipe_id:,
    recipe_instance_id:,
    ack_type:,
    warning:,
  ) = acknowledgement

  case ack_type {
    ReceivedClientUpdate -> {
      echo "update_current_interaction and add_warning"
      model
      |> update_acknowledged_flag(recipe_instance_id, True)
      |> add_instance_notification(
        recipe_instance_id,
        "Client update acknowledged",
      )
      |> add_instance_warning(recipe_instance_id, warning)
    }
    ReceivedNewRecipe ->
      model
      |> add_new_instance(recipe_id, recipe_instance_id)
      |> add_instance_notification(recipe_instance_id, "Recipe Submitted")
  }
}

fn add_new_instance(
  model: Model,
  recipe_id: RecipeID,
  recipe_instance_id: RecipeInstanceID,
) -> Model {
  Model(
    ..model,
    instance_dict: model.instance_dict
      |> dict.insert(
        recipe_instance_id,
        model.make_new_instance(recipe_id, recipe_instance_id),
      ),
  )
}

fn add_instance_notification(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  message: String,
) -> Model {
  perform_instance_update(
    model,
    instance_id,
    fn(instance: RecipeInteractionInstance) -> RecipeInteractionInstance {
      RecipeInteractionInstance(..instance, notifications: [
        message,
        ..instance.notifications
      ])
    },
  )
}

fn handle_recipe_list(model: Model, recipe_list: List(RecipeEntry)) -> Model {
  Model(..model, recipe_list: Some(recipe_list))
}

fn handle_recipe_stats(
  model: Model,
  instance_stats: RecipeInstanceStatistics,
) -> Model {
  model
  |> perform_instance_update(instance_stats.recipe_instance_id, fn(instance) {
    RecipeInteractionInstance(..instance, stats: [
      instance_stats.dictionary,
      ..instance.stats
    ])
  })
}

fn handle_deser_error(
  model: Model,
  dispatcher_return: DispatcherReturn,
) -> Model {
  let description = case dispatcher_return {
    DispatcherReturnHydrationError(
      recipe_instance_id:,
      error_type:,
      description:,
      client_data:,
    ) -> {
      let error_type_to_string = fn(error_type) {
        case error_type {
          ClientResponseHydrationError -> "Hydration error"
        }
      }

      string_tree.new()
      |> string_tree.append("[")
      |> string_tree.append(recipe_instance_id)
      |> string_tree.append("] ")
      |> string_tree.append(error_type |> error_type_to_string())
      |> string_tree.append(": ")
      |> string_tree.append(description)
      |> string_tree.append("(")
      |> string_tree.append(client_data)
      |> string_tree.append(")")
      |> string_tree.to_string()
    }
    _ -> "Unexpected service error"
  }

  Model(..model, errors: [WrapperDecodeError(description), ..model.errors])
}

fn handle_general_error(model: Model, error: String) -> Model {
  Model(..model, errors: [WrapperGeneralError(error), ..model.errors])
}

// ###################################################
// General model update functions
// ###################################################

fn prepare_new_interaction(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  service: ServiceReference,
  request: RequestSpecification,
  warning: Option(String),
  service_state: Option(Arguments),
) -> Model {
  model
  |> add_to_history(instance_id, service, service_state)
  |> retire_current_interaction(instance_id)
  |> add_new_interaction(instance_id, service, request)
  |> add_instance_warning(instance_id, warning)
}

fn finalize_interactions(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  service: ServiceReference,
  result: String,
  warning: Option(String),
  service_state: Option(Arguments),
) -> Model {
  model
  |> add_to_history(instance_id, service, service_state)
  |> retire_current_interaction(instance_id)
  |> reset_current_interaction(instance_id)
  |> add_result(instance_id, result)
  |> add_instance_warning(instance_id, warning)
}

fn add_to_history(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  service: ServiceReference,
  service_state: Option(Arguments),
) -> Model {
  let add_arguments = fn(builder: StringTree, args: Arguments) -> StringTree {
    args
    |> list.fold(builder, fn(acc, arg) {
      let arg_desc =
        " "
        <> arg.name
        <> ":"
        <> argument_value_encoder.argument_value_to_string(arg.value)

      string_tree.append(acc, arg_desc)
    })
  }
  let make_recipe_desc = fn(
    instance_id: String,
    service: ServiceReference,
    args,
  ) -> RecipeEvolution {
    let recipe_desc =
      string_tree.new()
      |> string_tree.append(service.name)
      |> add_arguments(args)
      |> string_tree.to_string()

    RecipeEvolution(instance_id, recipe_desc)
  }

  case service_state {
    Some(argument_state) -> {
      model
      |> perform_instance_update(instance_id, fn(instance) {
        RecipeInteractionInstance(..instance, recipe_evolution: [
          instance_id |> make_recipe_desc(service, argument_state),
          ..instance.recipe_evolution
        ])
      })
    }
    None -> model
  }
}

fn retire_current_interaction(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    RecipeInteractionInstance(
      ..instance,
      past_interactions: instance.current_interaction
        |> option.map(fn(interaction) {
          let response = interaction.response |> option.lazy_unwrap(fn() { "" })
          let past_interaction =
            PastInteraction(
              instance.recipe_info.recipe_instance_id,
              interaction.request.name,
              response,
            )

          [past_interaction, ..instance.past_interactions]
        })
        |> option.unwrap(instance.past_interactions),
    )
  })
}

fn add_new_interaction(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  service: ServiceReference,
  request: RequestSpecification,
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    RecipeInteractionInstance(
      ..instance,
      current_interaction: Some(CurrentInteraction(
        service:,
        request:,
        response: None,
        response_sent: False,
        response_acknowledged: False,
      )),
    )
  })
}

fn reset_current_interaction(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    RecipeInteractionInstance(..instance, current_interaction: None)
  })
}

fn add_result(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  result: String,
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    RecipeInteractionInstance(..instance, result: Some(result))
  })
}

// ###################################################
// Interaction updater functions
// ###################################################

fn update_current_interaction(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  updater: fn(CurrentInteraction) -> CurrentInteraction,
) -> Model {
  model
  |> perform_instance_update(instance_id, fn(instance) {
    case instance.current_interaction {
      Some(current) -> {
        RecipeInteractionInstance(
          ..instance,
          current_interaction: current |> updater() |> Some(),
        )
      }
      None -> instance
    }
  })
}

fn user_response_updater(
  response: String,
) -> fn(CurrentInteraction) -> CurrentInteraction {
  fn(interaction: CurrentInteraction) {
    CurrentInteraction(..interaction, response: Some(response))
  }
}

fn response_sent_flag_updater(
  response_sent: Bool,
) -> fn(CurrentInteraction) -> CurrentInteraction {
  fn(interaction) { CurrentInteraction(..interaction, response_sent:) }
}

fn response_acknowledged_flag_updater(
  response_acknowledged: Bool,
) -> fn(CurrentInteraction) -> CurrentInteraction {
  fn(interaction) { CurrentInteraction(..interaction, response_acknowledged:) }
}

fn perform_instance_update(
  model: Model,
  instance_id: recipe.RecipeInstanceID,
  updater: fn(RecipeInteractionInstance) -> RecipeInteractionInstance,
) -> Model {
  let updated_dict =
    model.instance_dict
    |> dict.get(instance_id)
    |> result.map(fn(instance) {
      dict.insert(model.instance_dict, instance_id, updater(instance))
    })
    |> result.lazy_unwrap(fn() { model.instance_dict })

  Model(..model, instance_dict: updated_dict)
}
