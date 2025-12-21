defmodule PortfolioManager.Workflow.Steps.ContextStep do
  @moduledoc """
  Context manipulation step.

  Sets variables and modifies workflow context.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes a context step.

  ## Config Options

    * `set` - Map of variables to set
    * `unset` - List of variables to remove
    * `from` - Copy value from another context path

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    config = step.config

    new_ctx =
      context
      |> apply_set(Map.get(config, "set", %{}))
      |> apply_unset(Map.get(config, "unset", []))
      |> apply_from(Map.get(config, "from", %{}))

    result = %{vars_modified: true}
    new_ctx = Context.set_result(new_ctx, step.name, result)
    {:ok, new_ctx, result}
  end

  defp apply_set(context, vars) when is_map(vars) do
    Enum.reduce(vars, context, fn {key, value}, ctx ->
      interpolated =
        if is_binary(value) do
          Context.interpolate(ctx, value)
        else
          value
        end

      Context.set_var(ctx, to_string(key), interpolated)
    end)
  end

  defp apply_set(context, _), do: context

  defp apply_unset(context, vars) when is_list(vars) do
    new_vars =
      Enum.reduce(vars, context.vars, fn key, acc ->
        Map.delete(acc, to_string(key))
      end)

    %{context | vars: new_vars}
  end

  defp apply_unset(context, _), do: context

  defp apply_from(context, mappings) when is_map(mappings) do
    Enum.reduce(mappings, context, fn {target, source}, ctx ->
      value = Context.resolve_key(ctx, to_string(source))
      Context.set_var(ctx, to_string(target), value)
    end)
  end

  defp apply_from(context, _), do: context
end
