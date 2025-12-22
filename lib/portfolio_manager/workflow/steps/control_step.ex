defmodule PortfolioManager.Workflow.Steps.ControlStep do
  @moduledoc """
  Control flow steps (condition, loop, abort).
  """

  alias PortfolioManager.Workflow.{Context, Parser, Step}

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}

    case action do
      "condition" -> handle_condition(inputs, context, opts)
      "loop" -> handle_loop(inputs, context, opts)
      "abort" -> {:error, Map.get(inputs, "message") || "Aborted"}
      _ -> {:error, "Unknown control action: #{action}"}
    end
  end

  defp handle_condition(inputs, context, opts) do
    condition = Map.get(inputs, "condition") || Map.get(inputs, :condition)
    cases = Map.get(inputs, "cases") || Map.get(inputs, :cases)
    abort_message = Map.get(inputs, "abort_message") || Map.get(inputs, :abort_message)

    if is_map(cases) do
      value = Context.resolve_inputs(context, condition)

      selected =
        Map.get(cases, value) ||
          Map.get(cases, to_string(value)) ||
          Map.get(cases, to_string(value) |> String.to_atom())

      resolved = Context.resolve_inputs(context, selected)
      {:ok, context, %{value: resolved}}
    else
      result =
        cond do
          is_boolean(condition) -> condition
          is_binary(condition) -> Context.evaluate_condition(context, condition)
          true -> false
        end

      if result do
        execute_branch(Map.get(inputs, "on_true") || Map.get(inputs, :on_true), context, opts)
      else
        on_false = Map.get(inputs, "on_false") || Map.get(inputs, :on_false)

        if on_false in ["abort", :abort] do
          {:error, abort_message || "Aborted"}
        else
          execute_branch(on_false, context, opts)
        end
      end
    end
  end

  defp handle_loop(inputs, context, opts) do
    items = Map.get(inputs, "items") || Map.get(inputs, :items) || []
    step_def = Map.get(inputs, "step") || Map.get(inputs, :step)

    items = Context.resolve_inputs(context, items)

    if is_list(items) and is_map(step_def) do
      {ctx, results} =
        Enum.reduce(items, {context, []}, fn item, {ctx, acc} ->
          ctx = Context.set_var(ctx, "item", item)
          step = Parser.normalize_step(step_def)

          case Step.execute(step, ctx, opts) do
            {:ok, new_ctx, result} ->
              updated =
                new_ctx
                |> Context.set_result(step.id, result)
                |> apply_outputs(step.outputs, result)

              {updated, acc ++ [result]}

            {:error, reason} ->
              {ctx, acc ++ [%{error: reason}]}

            {:skip, _} ->
              {ctx, acc}
          end
        end)

      {:ok, ctx, %{results: results}}
    else
      {:error, "loop requires items list and step definition"}
    end
  end

  defp execute_branch(nil, context, _opts), do: {:ok, context, %{condition: :no_op}}

  defp execute_branch(steps, context, opts) when is_list(steps) do
    Enum.reduce_while(steps, {:ok, context, nil}, fn step_def, {:ok, ctx, _} ->
      step = Parser.normalize_step(step_def)

      case Step.execute(step, ctx, opts) do
        {:ok, new_ctx, result} ->
          updated =
            new_ctx
            |> Context.set_result(step.id, result)
            |> apply_outputs(step.outputs, result)

          {:cont, {:ok, updated, result}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        {:skip, _} ->
          {:cont, {:ok, ctx, nil}}
      end
    end)
  end

  defp execute_branch(step_def, context, opts) when is_map(step_def) do
    execute_branch([step_def], context, opts)
  end

  defp apply_outputs(ctx, outputs, result) do
    outputs = outputs || %{}

    if map_size(outputs) == 0 do
      ctx
    else
      Enum.reduce(outputs, ctx, fn {output_key, var_name}, acc ->
        value = fetch_output_value(result, output_key)
        Context.set_var(acc, to_string(var_name), value)
      end)
    end
  end

  defp fetch_output_value(result, key) when is_map(result) do
    Map.get(result, key) || Map.get(result, to_string(key)) ||
      Map.get(result, String.to_atom(to_string(key)))
  end

  defp fetch_output_value(result, _key), do: result
end
