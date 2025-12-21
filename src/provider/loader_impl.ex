defmodule ProviderLoaderImpl do
  @moduledoc """
  Loads service provider modules from a folder
  """

  # load a list of module names and return the resolver functions
  @spec load_modules([{:key_value, binary(), binary()}], binary()) ::
          {:module_loader, list(), list()}
  def load_modules(key_module_names, path) do
    case Code.append_path(path) do
      true ->
        key_module_names
        |> Enum.map(&load_and_capture/1)
        |> collect()

      # |> IO.inspect(label: "Post collect: ")

      false ->
        {:module_loader, [], [{"", "Module loader rejected folder path"}]}
    end
  end

  @spec load_and_capture({:key_value, binary(), binary()}) ::
          {:ok, binary(),
           {:service_description, {:service_reference, binary(), binary()}, binary()}, fun()}
          | {:error, binary(), binary()}
  defp load_and_capture({:key_value, key, module_name}) do
    # return the resolve function if available
    case Code.ensure_loaded(String.to_atom(module_name)) do
      {:module, module} -> check_required_fns(key, module, module_name)
      {:error, :nofile} -> {:error, {key, "Module not found: " <> module_name}}
    end
  end

  @spec check_required_fns(binary(), module(), binary()) ::
          {:ok, binary(),
           {:service_description, {:service_reference, binary(), binary()}, binary()}, fun()}
          | {:error, binary(), binary()}
  defp check_required_fns(key, module, module_name) do
    # check that the three required functions exist in the module
    # required functions: get_service_ref/0, get_type_info/0 and resolve/3
    case Kernel.function_exported?(module, :get_service_desc, 0) &&
           Kernel.function_exported?(module, :get_type_info, 0) &&
           Kernel.function_exported?(module, :resolve, 3) do
      true -> capture_resolver_fn(key, module, module_name)
      false -> {:error, {key, "No resolver function on " <> module_name}}
    end
  end

  @spec capture_resolver_fn(binary(), module(), binary()) ::
          {:ok, binary(),
           {:service_description, {:service_reference, binary(), binary()}, binary()}, fun()}
          | {:error, binary(), binary()}
  defp capture_resolver_fn(key, module, module_name) do
    service_desc =
      module
      |> Function.capture(:get_service_desc, 0)
      |> get_service_desc()

    captured = Function.capture(module, :resolve, 3)

    case check_fn(captured) do
      :ok -> {:ok, {key, service_desc, captured}}
      :rescued -> {:error, {key, "Not compatible: " <> module_name}}
    end
  end

  defp check_fn(fun) do
    # expecting a three arity function with args:
    #   String, Option(Argument), Arguments
    # so: "", :none, []
    try do
      fun.("", :none, [])
      :ok
    rescue
      _ -> :rescued
    end
  end

  defp get_service_desc(fun) do
    {:service_description, {:service_reference, _name, _path}, _description} =
      service_desc = fun.()

    service_desc
  end

  @spec collect(
          list(
            {:ok,
             {binary(),
              {:service_description, {:service_reference, binary(), binary()}, binary()}, fun()}}
            | {:error, {binary(), binary()}}
          )
        ) ::
          {:module_loader, list(), list()}
  defp collect(items) do
    collected =
      items
      |> Enum.reduce(%{successes: [], failures: []}, &collect/2)

    {:module_loader, Map.get(collected, :successes), Map.get(collected, :failures)}
  end

  defp collect({:ok, success_tuple}, acc),
    do: Map.update!(acc, :successes, fn successes -> [success_tuple | successes] end)

  defp collect({:error, failure_tuple}, acc),
    do: Map.update!(acc, :failures, fn failures -> [failure_tuple | failures] end)
end
