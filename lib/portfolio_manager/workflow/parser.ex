defmodule PortfolioManager.Workflow.Parser do
  @moduledoc """
  Parses workflow definitions from YAML files.
  """

  @doc """
  Loads a workflow by name.

  Searches for the workflow in:
  1. Built-in workflows (priv/workflows/)
  2. User workflows (~/portfolio/workflows/ or $PORTFOLIO_DIR/workflows/)
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(name) do
    case find_workflow_file(name) do
      {:ok, path} -> parse_file(path)
      {:error, _} = error -> error
    end
  end

  @doc """
  Parses a workflow from a file path.
  """
  @spec parse_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, data} -> parse_workflow(data, path)
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Parses a workflow from a string.
  """
  @spec parse_string(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_string(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, data} -> parse_workflow(data, nil)
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Normalizes a step definition map.
  """
  @spec normalize_step(map(), non_neg_integer() | nil) :: map()
  def normalize_step(data, idx \\ nil) when is_map(data) do
    id = get_field(data, "id") || default_step_id(idx)

    %{
      id: id,
      name: get_field(data, "name") || id,
      type: normalize_type(get_field(data, "type")),
      action: get_field(data, "action"),
      provider: get_field(data, "provider"),
      inputs: get_field(data, "inputs") || %{},
      outputs: get_field(data, "outputs") || %{},
      on_failure: get_field(data, "on_failure") || "stop",
      timeout: get_field(data, "timeout") || 60_000
    }
  end

  defp get_field(data, key), do: Map.get(data, key) || Map.get(data, String.to_atom(key))

  # Private

  defp find_workflow_file(name) do
    filename = if String.ends_with?(name, ".yml"), do: name, else: "#{name}.yml"

    workflow_dirs()
    |> Enum.map(&Path.join(&1, filename))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  defp workflow_dirs do
    priv_dir =
      case :code.priv_dir(:portfolio_manager) do
        {:error, _} -> "priv"
        dir -> to_string(dir)
      end

    builtin_dir = Path.join(priv_dir, "workflows")

    user_dir =
      case System.get_env("PORTFOLIO_DIR") do
        nil -> Path.join(System.user_home!(), "portfolio/workflows")
        dir -> Path.join(dir, "workflows")
      end

    [builtin_dir, user_dir]
  end

  defp parse_workflow(data, source_path) do
    workflow_data = Map.get(data, "workflow") || %{}

    id =
      Map.get(workflow_data, "id") ||
        Map.get(workflow_data, "name") ||
        (source_path && Path.basename(source_path, ".yml"))

    workflow = %{
      id: id,
      name: Map.get(workflow_data, "name", id),
      description: Map.get(workflow_data, "description", ""),
      version: Map.get(workflow_data, "version", "1.0.0"),
      schema_version: Map.get(data, "schema_version", 1),
      target: Map.get(workflow_data, "target"),
      target_filter: Map.get(workflow_data, "target_filter") || %{},
      inputs: Map.get(workflow_data, "inputs") || %{},
      outputs: Map.get(workflow_data, "outputs") || %{},
      steps: parse_steps(Map.get(workflow_data, "steps", [])),
      source: source_path
    }

    validate_workflow(workflow)
  end

  defp parse_steps(steps) when is_list(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step_data, idx} -> normalize_step(step_data, idx) end)
  end

  defp parse_steps(_), do: []

  defp validate_workflow(workflow) do
    cond do
      is_nil(workflow.id) or workflow.id == "" ->
        {:error, :id_required}

      Enum.empty?(workflow.steps) ->
        {:error, :steps_required}

      true ->
        {:ok, workflow}
    end
  end

  defp default_step_id(nil), do: "step_1"
  defp default_step_id(idx), do: "step_#{idx + 1}"

  defp normalize_type(nil), do: :unknown
  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type(type) when is_binary(type), do: String.to_atom(type)
end
