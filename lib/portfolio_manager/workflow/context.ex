defmodule PortfolioManager.Workflow.Context do
  @moduledoc """
  Execution context for workflows.

  Maintains state that flows between workflow steps.
  """

  @type t :: %__MODULE__{
          workflow: String.t(),
          started_at: DateTime.t(),
          vars: map(),
          repo: map() | nil,
          context: map() | nil,
          results: map(),
          env: map()
        }

  defstruct [
    :workflow,
    :started_at,
    vars: %{},
    repo: nil,
    context: nil,
    results: %{},
    env: %{}
  ]

  @doc """
  Creates a new workflow context.
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) do
    %__MODULE__{
      workflow: Map.get(attrs, :workflow),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      vars: Map.get(attrs, :vars, %{}),
      repo: Map.get(attrs, :repo),
      context: Map.get(attrs, :context),
      results: %{},
      env: build_env(attrs)
    }
  end

  @doc """
  Sets a variable in the context.
  """
  @spec set_var(t(), String.t(), term()) :: t()
  def set_var(%__MODULE__{} = ctx, key, value) do
    %{ctx | vars: Map.put(ctx.vars, key, value)}
  end

  @doc """
  Gets a variable from the context.
  """
  @spec get_var(t(), String.t(), term()) :: term()
  def get_var(%__MODULE__{} = ctx, key, default \\ nil) do
    Map.get(ctx.vars, key, default)
  end

  @doc """
  Sets the result of a step.
  """
  @spec set_result(t(), String.t(), term()) :: t()
  def set_result(%__MODULE__{} = ctx, step_name, result) do
    %{ctx | results: Map.put(ctx.results, step_name, result)}
  end

  @doc """
  Gets the result of a step.
  """
  @spec get_result(t(), String.t()) :: term() | nil
  def get_result(%__MODULE__{} = ctx, step_name) do
    Map.get(ctx.results, step_name)
  end

  @doc """
  Interpolates variables in a string.

  Replaces `{{var}}` patterns with their values from context.
  """
  @spec interpolate(t(), String.t()) :: String.t()
  def interpolate(%__MODULE__{} = ctx, template) when is_binary(template) do
    Regex.replace(~r/\{\{(\w+(?:\.\w+)*)\}\}/, template, fn _, key ->
      resolve_key(ctx, key) |> to_string()
    end)
  end

  def interpolate(_ctx, value), do: value

  @doc """
  Resolves a dotted key path from the context.
  """
  @spec resolve_key(t(), String.t()) :: term() | nil
  def resolve_key(%__MODULE__{} = ctx, key) do
    parts = String.split(key, ".")

    case parts do
      ["repo" | rest] -> get_nested(ctx.repo, rest)
      ["context" | rest] -> get_nested(ctx.context, rest)
      ["results" | rest] -> get_nested(ctx.results, rest)
      ["env" | rest] -> get_nested(ctx.env, rest)
      [var] -> Map.get(ctx.vars, var)
      path -> get_nested(ctx.vars, path)
    end
  end

  @doc """
  Evaluates a condition expression.
  """
  @spec evaluate_condition(t(), String.t()) :: boolean()
  def evaluate_condition(%__MODULE__{} = ctx, condition) when is_binary(condition) do
    # Simple condition evaluation
    # Supports: "var == value", "var != value", "var", "!var"
    cond do
      String.contains?(condition, "==") ->
        [left, right] = String.split(condition, "==", parts: 2)
        resolve_key(ctx, String.trim(left)) == parse_value(String.trim(right))

      String.contains?(condition, "!=") ->
        [left, right] = String.split(condition, "!=", parts: 2)
        resolve_key(ctx, String.trim(left)) != parse_value(String.trim(right))

      String.starts_with?(condition, "!") ->
        key = String.trim_leading(condition, "!")
        !truthy?(resolve_key(ctx, String.trim(key)))

      true ->
        truthy?(resolve_key(ctx, String.trim(condition)))
    end
  end

  def evaluate_condition(_ctx, nil), do: true
  def evaluate_condition(_ctx, _), do: true

  # Private

  defp build_env(attrs) do
    base = %{
      "HOME" => System.user_home!(),
      "USER" => System.get_env("USER", ""),
      "PWD" => File.cwd!()
    }

    repo = Map.get(attrs, :repo)

    if repo do
      Map.merge(base, %{
        "REPO_ID" => repo.id,
        "REPO_PATH" => repo.path,
        "REPO_NAME" => repo.name
      })
    else
      base
    end
  end

  defp get_nested(nil, _), do: nil
  defp get_nested(value, []), do: value

  defp get_nested(struct, [key | rest]) when is_struct(struct) and is_binary(key) do
    value = Map.get(struct, String.to_atom(key))
    get_nested(value, rest)
  end

  defp get_nested(map, [key | rest]) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))
    get_nested(value, rest)
  end

  defp get_nested(_, _), do: nil

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value("nil"), do: nil
  defp parse_value("null"), do: nil

  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> String.trim(value, "\"")
    end
  end

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(""), do: false
  defp truthy?(0), do: false
  defp truthy?([]), do: false
  defp truthy?(_), do: true
end
