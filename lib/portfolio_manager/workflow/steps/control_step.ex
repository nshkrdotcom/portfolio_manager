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
    condition = get_input(inputs, "condition")
    cases = get_input(inputs, "cases")
    abort_message = get_input(inputs, "abort_message")
    handle_condition_type(cases, condition, inputs, context, opts, abort_message)
  end

  defp handle_condition_type(cases, condition, _inputs, context, _opts, _abort_message)
       when is_map(cases) do
    value = Context.resolve_inputs(context, condition)
    selected = lookup_case(cases, value)
    resolved = Context.resolve_inputs(context, selected)
    {:ok, context, %{value: resolved}}
  end

  defp handle_condition_type(_cases, condition, inputs, context, opts, abort_message) do
    result = evaluate_bool_condition(condition, context)
    execute_condition_branch(result, inputs, context, opts, abort_message)
  end

  defp lookup_case(cases, value) do
    Map.get(cases, value) ||
      Map.get(cases, to_string(value)) ||
      Map.get(cases, to_string(value) |> String.to_atom())
  end

  defp evaluate_bool_condition(condition, _context) when is_boolean(condition), do: condition

  defp evaluate_bool_condition(condition, context) when is_binary(condition),
    do: Context.evaluate_condition(context, condition)

  defp evaluate_bool_condition(_condition, _context), do: false

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))

  defp execute_condition_branch(true, inputs, context, opts, _abort_message) do
    execute_branch(Map.get(inputs, "on_true") || Map.get(inputs, :on_true), context, opts)
  end

  defp execute_condition_branch(false, inputs, context, opts, abort_message) do
    on_false = Map.get(inputs, "on_false") || Map.get(inputs, :on_false)
    execute_false_branch(on_false, context, opts, abort_message)
  end

  defp execute_false_branch(on_false, _context, _opts, abort_message)
       when on_false in ["abort", :abort] do
    {:error, abort_message || "Aborted"}
  end

  defp execute_false_branch(on_false, context, opts, _abort_message) do
    execute_branch(on_false, context, opts)
  end

  defp handle_loop(inputs, context, opts) do
    items = Map.get(inputs, "items") || Map.get(inputs, :items) || []
    step_def = Map.get(inputs, "step") || Map.get(inputs, :step)

    items = Context.resolve_inputs(context, items)

    if is_list(items) and is_map(step_def) do
      {ctx, results} =
        Enum.reduce(items, {context, []}, fn item, {ctx, acc} ->
          execute_loop_iteration(item, step_def, ctx, acc, opts)
        end)

      {:ok, ctx, %{results: results}}
    else
      {:error, "loop requires items list and step definition"}
    end
  end

  defp execute_loop_iteration(item, step_def, ctx, acc, opts) do
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
