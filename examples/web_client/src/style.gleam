import sketch/css
import sketch/css/length.{px}

pub fn header_style() {
  css.class([
    css.display("flex"),
    css.align_items("center"),
    css.justify_content("space-around"),
  ])
}

pub fn top_level_container_style() {
  css.class([
    css.display("flex"),
    css.align_items("center"),
    css.justify_content("space-around"),
  ])
}

pub fn main_style() {
  css.class([
    css.display("flex"),
    css.flex_direction("column"),
  ])
}

pub fn recipes_style() {
  css.class([
    css.display("flex"),
    css.align_items("center"),
    css.justify_content("space-around"),
  ])
}

pub fn recipes_child_style() {
  css.class([
    css.margin(length.px(10)),
    css.display("flex"),
    css.flex_direction("column"),
    css.flex("auto"),
    css.max_width(length.percent(50)),
  ])
}

pub fn interactions_style() {
  css.class([
    css.display("flex"),
    css.flex_direction("row"),
    css.align_items("center"),
    css.justify_content("space-around"),
    css.overflow_x("auto"),
  ])
}

pub fn interactions_instance_style() {
  css.class([
    css.height(length.px(400)),
    css.overflow_y("auto"),
    css.margin(length.em(1.0)),
    css.font_family("Arial"),
    css.flex("0 0 400px"),
    css.box_shadow("5px 5px 10px rgba(0, 0, 0, 0.5)"),
  ])
}

pub fn model_viewer_style() {
  css.class([
    css.display("flex"),
    css.flex_direction("column"),
    css.align_items("center"),
    css.justify_content("space-around"),
  ])
}

pub fn model_viewer_item_style() {
  css.class([
    css.padding(length.px(10)),
    css.width(length.percent(50)),
  ])
}

pub fn model_viewer_block_element_style() {
  css.class([
    css.border("solid thin black"),
    css.background_color("lightgrey"),
    css.margin(length.px(10)),
    css.padding(length.px(10)),
    css.width(length.percent(100)),
  ])
}

pub fn model_viewer_single_element_style() {
  css.class([
    css.padding(length.px(10)),
    css.width(length.percent(100)),
  ])
}

pub fn model_viewer_block_style() {
  css.class([
    css.margin(length.px(20)),
    css.padding(length.px(10)),
    css.width(length.percent(80)),
  ])
}

pub fn model_viewer_item_label_style() {
  css.class([
    css.font_weight("bold"),
    css.color("white"),
    css.background("grey"),
    css.margin(length.px(4)),
    css.padding(length.px(4)),
  ])
}

pub fn model_viewer_item_value_style() {
  css.class([css.margin(length.px(4))])
}

pub fn model_viewer_button_style() {
  css.class([css.margin(length.px(4))])
}

pub fn interaction_row_style() {
  css.class([
    css.display("flex"),
    css.flex_flow("row wrap"),
    css.font_size(px(24)),
    css.padding(length.px(8)),
  ])
}

pub fn interaction_row_input_style() {
  // for interaction row input controls (select or input elements)
  css.class([
    css.flex("auto"),
    css.max_width(length.percent(50)),
    css.padding(length.px(2)),
  ])
}

pub fn interaction_row_button_style() {
  css.class([
    css.width(length.em(5.0)),
    css.padding(length.px(2)),
  ])
}

pub fn recipe_list_option_style() {
  css.class([
    css.display("flex"),
    css.flex_flow("row wrap"),
  ])
}

pub fn recipe_list_option_child_style() {
  css.class([
    css.flex("fit-content"),
  ])
}

pub fn notifications_style() {
  css.class([
    css.margin(length.px(8)),
    css.padding(length.px(4)),
    css.display("flex"),
    css.flex_flow("column"),
  ])
}

pub fn notifications_title_style() {
  css.class([
    css.font_style("italic"),
  ])
}

pub fn notifications_item_style() {
  css.class([
    css.flex_basis("fit-content"),
    css.padding(length.px(4)),
    css.marker([
      css.font_size(length.em(1.2)),
    ]),
  ])
}

pub fn recipe_evolution_style() {
  css.class([
    css.margin(length.px(8)),
    css.padding(length.px(4)),
    css.display("flex"),
    css.flex_flow("column"),
  ])
}

pub fn recipe_evolution_span_style() {
  css.class([
    css.margin(length.px(5)),
    css.padding(length.px(5)),
    css.border("lightskyblue solid 1px"),
  ])
}

pub fn result_style() {
  css.class([
    css.background("lightgrey"),
    css.font_size(px(16)),
    css.margin(length.px(8)),
    css.padding(length.px(5)),
  ])
}
