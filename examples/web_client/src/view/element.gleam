import app/types/recipe.{type RecipeInstanceID}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute
import lustre/element.{type Element, text}
import lustre/event.{on_click, on_input}
import sketch/lustre/element/html as sketch_element
import style
import types/message.{type Msg, UserSelectedRecipe, UserSubmittedRecipe}
import types/model.{
  type Model, type RecipeEvolution, type RecipeInteractionInstance,
  RecipeEvolution,
}

// ###############################################
// Top-level elements
// ###############################################

pub fn show_recipe_list(model: Model) -> List(Element(Msg)) {
  [
    sketch_element.div(style.recipes_child_style(), [], [
      sketch_element.select_(
        [
          attribute.size("5"),
          on_input(UserSelectedRecipe),
        ],
        model.recipe_list
          |> option.map(fn(recipe_list) {
            recipe_list
            |> list.map(fn(recipe_entry) {
              sketch_element.option(
                style.recipe_list_option_style(),
                [attribute.value(recipe_entry.specification)],
                [
                  sketch_element.span(
                    style.recipe_list_option_child_style(),
                    [],
                    [
                      text(recipe_entry.specification),
                    ],
                  ),
                  sketch_element.span(
                    style.recipe_list_option_child_style(),
                    [],
                    [
                      text(recipe_entry.description),
                    ],
                  ),
                ],
              )
            })
          })
          |> option.unwrap([]),
      ),
      make_recipe_submit_button(model),
    ]),
  ]
}

pub fn make_recipe_submit_button(model: Model) -> Element(Msg) {
  // allow only this number of instances
  let is_disabled =
    model.selected_recipe |> option.is_none()
    || dict.size(model.instance_dict) >= 4

  sketch_element.button_(
    [on_click(UserSubmittedRecipe), attribute.disabled(is_disabled)],
    [text("Submit")],
  )
}

// ###############################################
// Per-instance elements
// ###############################################

pub fn show_recipe(
  instance_id: RecipeInstanceID,
  instance: RecipeInteractionInstance,
) -> Element(Msg) {
  let show_history = fn(history: RecipeEvolution) -> List(Element(Msg)) {
    [
      sketch_element.span(style.recipe_evolution_span_style(), [], [
        text(history.recipe_instance_id),
      ]),
      sketch_element.span(style.recipe_evolution_span_style(), [], [
        text(history.recipe_desc),
      ]),
    ]
  }

  let children =
    case instance.recipe_evolution {
      [] -> RecipeEvolution(instance_id, instance.recipe_info.template)
      [first, ..] -> first
    }
    |> show_history()

  sketch_element.div(style.recipe_evolution_style(), [], children)
}

pub fn maybe_show_result(
  existing_elements: List(Element(Msg)),
  instance: RecipeInteractionInstance,
) -> List(Element(Msg)) {
  case instance.result {
    Some(result) -> {
      existing_elements
      |> list.append(
        sketch_element.div(style.result_style(), [], [
          text("Final result: " <> result),
        ])
        |> list.wrap(),
      )
    }
    None -> existing_elements
  }
}

pub fn show_instance_notifications(
  instance: RecipeInteractionInstance,
) -> Element(Msg) {
  show_notifications("Notifications", instance.notifications)
}

// ###############################################
// Utility functions
// ###############################################

fn show_notifications(title: String, notifications: List(String)) {
  sketch_element.div(style.notifications_style(), [], [
    sketch_element.span(style.notifications_title_style(), [], [
      text(title),
    ]),
    sketch_element.ul(
      style.notifications_style(),
      [],
      notifications
        |> list.reverse()
        |> list.map(fn(item) {
          sketch_element.li(style.notifications_item_style(), [], [text(item)])
        }),
    ),
  ])
}
