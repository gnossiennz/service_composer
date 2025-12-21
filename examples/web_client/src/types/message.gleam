import app/types/recipe.{type RecipeInstanceID}
import lustre_websocket.{type WebSocketEvent}

pub type Msg {
  SocketReceivedData(WebSocketEvent)
  UserSelectedRecipe(String)
  UserSubmittedRecipe
  UserUpdatedResponse(RecipeInstanceID, String)
  UserSentResponse(RecipeInstanceID)
  UserToggledModelViewerInstanceDisplay
}
