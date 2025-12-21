defmodule FileUtility do
  @moduledoc """
  Functions for handling file paths and listing BEAM files
  """

  # Get the base name of the specified file with and without the file extension
  @spec get_base_name(binary(), binary()) :: {binary(), binary()}
  def get_base_name(file_path, extension) do
    {Path.basename(file_path), Path.basename(file_path, extension)}
  end

  # Get a list of BEAM files in the specified directory
  @spec get_beam_files(binary()) :: {:ok, list()} | {:error, atom()}
  def get_beam_files(folder_path) do
    with :exists <- check_exists(folder_path),
         :is_dir <- check_is_directory(folder_path) do
      required_path = Path.join(folder_path, "*.beam")

      {:ok, Path.wildcard(required_path)}
    else
      err -> {:error, err}
    end
  end

  defp check_exists(path) do
    if File.exists?(path), do: :exists, else: :not_exists
  end

  defp check_is_directory(path) do
    if File.dir?(path), do: :is_dir, else: :is_not_dir
  end
end
