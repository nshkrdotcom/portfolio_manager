defmodule PortfolioManager.Workflow.Parser do
  @moduledoc """
  Parses workflow definitions from YAML files.
  """

  @doc """
  Loads a workflow by name.

  Searches for the workflow in:
  1. Built-in workflows (priv/workflows/)
  2. User workflows (~/.portfolio/workflows/ or $PORTFOLIO_DIR/workflows/)
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
        nil -> Path.join(System.user_home!(), ".portfolio/workflows")
        dir -> Path.join(dir, "workflows")
      end

    [builtin_dir, user_dir]
  end

  defp parse_workflow(data, source_path) do
    name = Map.get(data, "name") || (source_path && Path.basename(source_path, ".yml"))

    workflow = %{
      name: name,
      description: Map.get(data, "description", ""),
      version: Map.get(data, "version", "1.0"),
      vars: parse_vars(Map.get(data, "vars", %{})),
      steps: parse_steps(Map.get(data, "steps", [])),
      on_error: Map.get(data, "on_error", "stop"),
      source: source_path
    }

    validate_workflow(workflow)
  end

  defp parse_vars(vars) when is_map(vars), do: vars
  defp parse_vars(_), do: %{}

  defp parse_steps(steps) when is_list(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step_data, idx} -> parse_step(step_data, idx) end)
  end

  defp parse_steps(_), do: []

  defp parse_step(data, idx) when is_map(data) do
    type = detect_step_type(data)

    %{
      name: Map.get(data, "name", "step_#{idx + 1}"),
      type: type,
      description: Map.get(data, "description"),
      config: parse_step_config(type, data),
      when: parse_condition(Map.get(data, "when")),
      continue_on_error: Map.get(data, "continue_on_error", false),
      timeout: Map.get(data, "timeout", 60_000)
    }
  end

  defp detect_step_type(data) do
    cond do
      Map.has_key?(data, "git") -> :git
      Map.has_key?(data, "shell") -> :shell
      Map.has_key?(data, "agent") -> :agent
      Map.has_key?(data, "file") -> :file
      Map.has_key?(data, "context") -> :context
      Map.has_key?(data, "update") -> :update
      true -> :unknown
    end
  end

  defp parse_step_config(:git, data), do: Map.get(data, "git")
  defp parse_step_config(:shell, data), do: Map.get(data, "shell")
  defp parse_step_config(:agent, data), do: Map.get(data, "agent")
  defp parse_step_config(:file, data), do: Map.get(data, "file")
  defp parse_step_config(:context, data), do: Map.get(data, "context")
  defp parse_step_config(:update, data), do: Map.get(data, "update")
  defp parse_step_config(_, _), do: %{}

  defp parse_condition(nil), do: nil
  defp parse_condition(condition) when is_binary(condition), do: condition
  defp parse_condition(_), do: nil

  defp validate_workflow(workflow) do
    cond do
      is_nil(workflow.name) or workflow.name == "" ->
        {:error, :name_required}

      Enum.empty?(workflow.steps) ->
        {:error, :steps_required}

      true ->
        {:ok, workflow}
    end
  end
end
