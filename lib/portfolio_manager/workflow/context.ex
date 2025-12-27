defmodule PortfolioManager.Workflow.Context do
  @moduledoc """
  Execution context for workflows.

  Maintains state that flows between workflow steps.
  """

  @type t :: %__MODULE__{
          workflow: String.t(),
          started_at: DateTime.t(),
          inputs: map(),
          vars: map(),
          repo: map() | nil,
          context: map() | nil,
          results: map(),
          env: map()
        }

  defstruct [
    :workflow,
    :started_at,
    inputs: %{},
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
      inputs: Map.get(attrs, :inputs, %{}),
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
      resolve_key(ctx, key) |> format_value()
    end)
  end

  def interpolate(_ctx, value), do: value

  @doc """
  Resolves input values recursively, handling $refs and templates.
  """
  @spec resolve_inputs(t(), term()) :: term()
  def resolve_inputs(%__MODULE__{} = ctx, value) when is_binary(value) do
    if String.starts_with?(value, "$") do
      resolve_key(ctx, String.trim_leading(value, "$"))
    else
      interpolate(ctx, value)
    end
  end

  def resolve_inputs(%__MODULE__{} = ctx, value) when is_list(value) do
    Enum.map(value, &resolve_inputs(ctx, &1))
  end

  def resolve_inputs(%__MODULE__{} = ctx, value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, resolve_inputs(ctx, v)} end)
  end

  def resolve_inputs(_ctx, value), do: value

  @doc """
  Resolves a dotted key path from the context.
  """
  @spec resolve_key(t(), String.t()) :: term() | nil
  def resolve_key(%__MODULE__{} = ctx, key) do
    parts = String.split(key, ".")

    case parts do
      ["inputs" | rest] -> get_nested(ctx.inputs, rest)
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
    evaluate_condition_impl(ctx, condition)
  end

  def evaluate_condition(_ctx, nil), do: true
  def evaluate_condition(_ctx, _), do: true

  defp evaluate_condition_impl(ctx, condition) do
    {operator, left, right} = parse_condition(condition)
    apply_operator(ctx, operator, left, right)
  end

  # Operators ordered by specificity (multi-char before single-char)
  @binary_operators [
    {" in ", :in},
    {"==", :==},
    {"!=", :!=},
    {">=", :>=},
    {"<=", :<=},
    {">", :>},
    {"<", :<}
  ]

  defp parse_condition(condition) do
    case find_binary_operator(condition) do
      {operator, left, right} -> {operator, left, right}
      nil -> parse_unary_condition(condition)
    end
  end

  defp find_binary_operator(condition) do
    Enum.find_value(@binary_operators, fn {delimiter, operator} ->
      if String.contains?(condition, delimiter) do
        [left, right] = String.split(condition, delimiter, parts: 2)
        {operator, String.trim(left), String.trim(right)}
      end
    end)
  end

  defp parse_unary_condition("!" <> rest), do: {:not, String.trim(rest), nil}
  defp parse_unary_condition(condition), do: {:truthy, String.trim(condition), nil}

  defp apply_operator(ctx, :in, left, right) do
    value = parse_value(left)
    collection = resolve_value(ctx, right)
    is_list(collection) and value in collection
  end

  defp apply_operator(ctx, :==, left, right) do
    resolve_value(ctx, left) == parse_value(right)
  end

  defp apply_operator(ctx, :!=, left, right) do
    resolve_value(ctx, left) != parse_value(right)
  end

  defp apply_operator(ctx, op, left, right) when op in [:>=, :<=, :>, :<] do
    compare_numbers(resolve_value(ctx, left), parse_value(right), op)
  end

  defp apply_operator(ctx, :not, left, _right) do
    !truthy?(resolve_value(ctx, left))
  end

  defp apply_operator(ctx, :truthy, left, _right) do
    truthy?(resolve_value(ctx, left))
  end

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
    value = String.trim(value)

    value =
      if String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
        String.trim(value, "\"")
      else
        value
      end

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

  defp resolve_value(ctx, value) do
    if String.starts_with?(value, "$") do
      case resolve_key(ctx, String.trim_leading(value, "$")) do
        atom when is_atom(atom) -> to_string(atom)
        other -> other
      end
    else
      parse_value(value)
    end
  end

  defp compare_numbers(left, right, op) when is_number(left) and is_number(right) do
    case op do
      :> -> left > right
      :>= -> left >= right
      :< -> left < right
      :<= -> left <= right
    end
  end

  defp compare_numbers(_, _, _), do: false

  defp format_value(nil), do: ""
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_list(value), do: inspect(value)
  defp format_value(value) when is_map(value), do: inspect(value)
  defp format_value(value), do: to_string(value)
end
