import gleam/bit_array
import gleam/dict
import gleam/option.{None}
import gleam/result
import gleeunit
import gleeunit/should
import recipe/create.{make_recipe}

const recipe_instance_id = "test instance id"

const services = [
  #("calc", "com.examples.service_composer:calc"),
  #("other", "com.examples.service_composer:other"),
]

pub fn main() {
  gleeunit.main()
}

pub fn simple_recipe_test() {
  "calc" |> check_recipe()
}

pub fn simple_recipe_with_args_test() {
  "calc operator:+ operand1:33" |> check_recipe()
}

pub fn two_step_recipe_with_args_test() {
  "calc operator:* operand:7 operand:(other operator:+ operand:3)"
  |> check_recipe()
}

fn check_recipe(recipe_desc: String) -> Nil {
  let services_dict = services |> dict.from_list()

  recipe_instance_id
  |> make_recipe(recipe_desc, services_dict)
  |> should.be_ok()
  |> fn(recipe) {
    recipe.description |> should.equal(None)
    recipe.error |> should.equal(None)
    recipe.id
    |> decode_tempate_id()
    |> should.be_ok()
    |> should.equal(recipe_desc)
  }
}

fn decode_tempate_id(id: String) -> Result(String, Nil) {
  id
  |> bit_array.base64_decode()
  |> result.try(fn(bits) { bit_array.to_string(bits) })
}
