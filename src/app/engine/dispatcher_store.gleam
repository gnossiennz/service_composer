//// A genserver actor that acts as a simple KV store
//// for recipe instances and provider service results

// consider using a package such as carpenter (an ETS store) instead
// waiting for carpenter to be updated for latest gleam otp???
import app/types/recipe.{type Recipe, type RecipeInstanceID}
import app/types/service_call.{
  type ClientRecipeState, type ServiceCallResponse, type ServiceState,
  DispatcherReturnRecipeState, DispatcherReturnServiceCall, ServiceCallResponse,
}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import serde/recipe/step/encoder as recipe_step_encoder

pub type RecipeExecutionStatus {
  Pending
  Requesting(service_state: ServiceState)
  Resubmitting
  Completing(service_state: ServiceState)
  Suspending(last_response: Option(ServiceCallResponse))
}

pub type RecipeStatisticsKey {
  DispatchAcknowledgeKey
  // the number of 'add step' acknowledgements from service providers for this recipe
  ServiceResultKey
  // the number of step results returned by the service providers
  ClientRequestKey
  // the number of client requests returned by the service providers
  ClientResponseKey
  // the number of client responses forwarded to the service providers
}

pub type RecipeStatistics {
  RecipeStatistics(dictionary: Dict(RecipeStatisticsKey, Int))
}

pub type StatsRecord {
  StatsRecord(
    client_request: Int,
    client_response: Int,
    dispatch_ack: Int,
    service_result: Int,
  )
}

pub type RecipeState {
  RecipeState(
    recipe: Recipe,
    status: RecipeExecutionStatus,
    stats: RecipeStatistics,
  )
}

pub type ActorState {
  ActorState(
    recipes: Dict(RecipeInstanceID, RecipeState),
    listeners: Dict(RecipeInstanceID, Subject(ServiceCallResponse)),
  )
}

pub type DispatcherStoreMessage {
  // Tell the actor to stop
  Shutdown

  // Add a new recipe instance to the store
  // Or replace the recipe with the specified ID with an updated recipe and response
  AddOrUpdateRecipe(recipe: Recipe, status: RecipeExecutionStatus)

  // Add one to each statistic for a recipe
  IncrementDispatchAcknowledgement(instance_id: RecipeInstanceID)
  IncrementServiceResult(instance_id: RecipeInstanceID)
  IncrementClientRequest(instance_id: RecipeInstanceID)
  IncrementClientResponse(instance_id: RecipeInstanceID)

  // Delete the specified recipe
  DeleteRecipe(instance_id: RecipeInstanceID)

  // Retrieve the specified recipe
  GetRecipe(
    instance_id: RecipeInstanceID,
    reply_with: Subject(Result(RecipeState, String)),
  )

  // Register a listening actor
  // normally this is a Glisten Actor (e.g. a Mist web socket process)
  RegisterListener(
    sender: Subject(ServiceCallResponse),
    instance_id: RecipeInstanceID,
  )
}

pub fn start() -> Result(
  actor.Started(Subject(DispatcherStoreMessage)),
  actor.StartError,
) {
  ActorState(recipes: dict.new(), listeners: dict.new())
  |> actor.new()
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn handle_message(
  state: ActorState,
  message: DispatcherStoreMessage,
) -> actor.Next(ActorState, DispatcherStoreMessage) {
  case message {
    Shutdown -> actor.stop()

    // Store or update a recipe instance or recipe error
    AddOrUpdateRecipe(recipe, status) -> {
      let updated_recipes =
        state.recipes
        |> dict.upsert(recipe.iid, fn(maybe_recipe_state) {
          case maybe_recipe_state {
            Some(RecipeState(recipe: _, status: _, stats:)) -> {
              // updating recipe and status only
              RecipeState(recipe:, status:, stats:)
            }
            None ->
              RecipeState(recipe:, status: Pending, stats: initialize_stats())
          }
        })

      // update any listeners for this recipe instance
      maybe_update_listeners(state.listeners, recipe, status)

      actor.continue(ActorState(..state, recipes: updated_recipes))
    }

    IncrementDispatchAcknowledgement(instance_id) -> {
      let updater = stats_updater_fn(DispatchAcknowledgeKey)
      let new_state = update_state(state, instance_id, updater)

      actor.continue(new_state)
    }

    IncrementServiceResult(instance_id) -> {
      let updater = stats_updater_fn(ServiceResultKey)
      let new_state = update_state(state, instance_id, updater)

      actor.continue(new_state)
    }

    IncrementClientRequest(instance_id) -> {
      let updater = stats_updater_fn(ClientRequestKey)
      let new_state = update_state(state, instance_id, updater)

      actor.continue(new_state)
    }

    IncrementClientResponse(instance_id) -> {
      let updater = stats_updater_fn(ClientResponseKey)
      let new_state = update_state(state, instance_id, updater)

      actor.continue(new_state)
    }

    DeleteRecipe(instance_id) -> {
      let updated_recipes =
        state.recipes
        |> dict.delete(instance_id)

      actor.continue(ActorState(..state, recipes: updated_recipes))
    }

    GetRecipe(instance_id, reply_with) -> {
      let retrieved = lookup_recipe(state.recipes, instance_id)
      process.send(reply_with, retrieved)

      actor.continue(state)
    }

    RegisterListener(sender, instance_id) -> {
      let updated_listeners =
        state.listeners |> dict.insert(instance_id, sender)

      actor.continue(ActorState(..state, listeners: updated_listeners))
    }
  }
}

pub fn recipe_stats_as_record(stats: RecipeStatistics) -> StatsRecord {
  let get = fn(key) {
    let assert Ok(value) = dict.get(stats.dictionary, key)
    value
  }

  StatsRecord(
    client_request: get(ClientRequestKey),
    client_response: get(ClientResponseKey),
    dispatch_ack: get(DispatchAcknowledgeKey),
    service_result: get(ServiceResultKey),
  )
}

fn maybe_update_listeners(
  listeners: Dict(RecipeInstanceID, Subject(ServiceCallResponse)),
  recipe: Recipe,
  status: RecipeExecutionStatus,
) -> Nil {
  let updater = case status {
    Pending -> make_recipe_state_response(_, service_call.Pending)
    Requesting(service_state) -> make_service_call_response(_, service_state)
    Resubmitting -> make_recipe_state_response(_, service_call.Stepping)
    Completing(service_state) -> make_service_call_response(_, service_state)
    Suspending(_last_response) -> make_recipe_state_response(
      _,
      service_call.Suspending,
    )
  }

  recipe
  |> update_listeners_with(updater, listeners)
}

fn make_service_call_response(
  recipe: Recipe,
  service_state: ServiceState,
) -> ServiceCallResponse {
  let recipe_desc = recipe_step_encoder.encode(recipe.root)

  ServiceCallResponse(
    recipe_id: recipe.id,
    recipe_desc:,
    dispatcher_return: DispatcherReturnServiceCall(
      recipe_instance_id: recipe.iid,
      service_state:,
    ),
  )
}

fn make_recipe_state_response(
  recipe: Recipe,
  recipe_state: ClientRecipeState,
) -> ServiceCallResponse {
  let recipe_desc = recipe_step_encoder.encode(recipe.root)

  ServiceCallResponse(
    recipe_id: recipe.id,
    recipe_desc:,
    dispatcher_return: DispatcherReturnRecipeState(
      recipe_instance_id: recipe.iid,
      recipe_state:,
    ),
  )
}

fn update_listeners_with(
  recipe: Recipe,
  response_maker: fn(Recipe) -> ServiceCallResponse,
  listeners: Dict(RecipeInstanceID, Subject(ServiceCallResponse)),
) -> Nil {
  recipe
  |> response_maker()
  |> update_listeners(listeners)
}

fn update_listeners(
  response: service_call.ServiceCallResponse,
  listeners: Dict(RecipeInstanceID, Subject(ServiceCallResponse)),
) -> Nil {
  case dict.get(listeners, response.dispatcher_return.recipe_instance_id) {
    Ok(listener) -> process.send(listener, response)
    Error(Nil) -> Nil
  }
}

fn lookup_recipe(
  recipes: Dict(RecipeInstanceID, RecipeState),
  instance_id: RecipeInstanceID,
) -> Result(RecipeState, String) {
  recipes
  |> dict.get(instance_id)
  |> result.map_error(fn(_) { "Key does not exist" })
}

fn initialize_stats() {
  [
    #(DispatchAcknowledgeKey, 0),
    #(ServiceResultKey, 0),
    #(ClientRequestKey, 0),
    #(ClientResponseKey, 0),
  ]
  |> dict.from_list()
  |> RecipeStatistics()
}

fn update_state(
  state: ActorState,
  instance_id: RecipeInstanceID,
  updater: fn(RecipeState) -> RecipeState,
) {
  let updated_recipes = case dict.has_key(state.recipes, instance_id) {
    True -> update_recipe_state(state.recipes, instance_id, updater)
    False -> state.recipes
  }

  ActorState(..state, recipes: updated_recipes)
}

fn update_recipe_state(
  recipes: Dict(RecipeInstanceID, RecipeState),
  instance_id: RecipeInstanceID,
  updater: fn(RecipeState) -> RecipeState,
) -> Dict(RecipeInstanceID, RecipeState) {
  // look up a KNOWN recipe and update the state using the updater function
  let assert Ok(recipe_state) = dict.get(recipes, instance_id)

  recipes
  |> dict.insert(instance_id, updater(recipe_state))
}

fn stats_updater_fn(key: RecipeStatisticsKey) -> fn(RecipeState) -> RecipeState {
  fn(recipe_state: RecipeState) {
    let updated_stats = increment_key(key, recipe_state.stats.dictionary)

    RecipeState(..recipe_state, stats: updated_stats)
  }
}

fn increment_key(
  key: RecipeStatisticsKey,
  stats_dictionary: Dict(RecipeStatisticsKey, Int),
) -> RecipeStatistics {
  let assert Ok(value) = dict.get(stats_dictionary, key)

  stats_dictionary
  |> dict.insert(key, value + 1)
  |> RecipeStatistics()
}
