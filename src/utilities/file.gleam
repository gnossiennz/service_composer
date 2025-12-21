import app/types/composer.{type KeyValue, KeyValue}
import gleam/erlang/atom.{type Atom}
import gleam/result

@external(erlang, "Elixir.FileUtility", "get_base_name")
fn get_base_name_pair(
  file_path: String,
  file_extension: String,
) -> #(String, String)

@external(erlang, "Elixir.FileUtility", "get_beam_files")
fn get_beam_files_in_folder(folder_path: String) -> Result(List(String), Atom)

/// Return the base name of the specified file with and without the file extension
pub fn get_base_name(file_path: String, file_extension: String) -> KeyValue {
  file_path
  |> get_base_name_pair(file_extension)
  |> fn(pair) { KeyValue(pair.0, pair.1) }
}

/// Return a list of BEAM files in the specified directory
pub fn get_beam_files(folder_path: String) -> Result(List(String), String) {
  folder_path
  |> get_beam_files_in_folder()
  |> result.map_error(fn(err) {
    case atom.to_string(err) {
      "not_exists" -> "The folder specified by the given path does not exist"
      "is_not_dir" -> "The path is not a folder"
      err -> err
    }
  })
}
