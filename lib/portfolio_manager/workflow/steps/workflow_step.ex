defmodule PortfolioManager.Workflow.Steps.WorkflowStep do
  @moduledoc """
  Nested workflow execution step.
  """

  alias PortfolioManager.Workflow.{Context, Engine}

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}

    case action do
      "run" -> run_workflow(inputs, context, opts)
      _ -> {:error, "Unknown workflow action: #{action}"}
    end
  end

  defp run_workflow(inputs, context, opts) do
    workflow = get_input(inputs, "workflow")
    repo_id = get_input(inputs, "repo_id")
    repo_ids = get_input(inputs, "repo_ids")
    base_inputs = drop_workflow_keys(inputs)
    run_workflow_type(workflow, repo_ids, repo_id, base_inputs, context, opts)
  end

  defp run_workflow_type(workflow, repo_ids, _repo_id, base_inputs, context, opts)
       when is_list(repo_ids) do
    results =
      Enum.map(repo_ids, fn id ->
        Engine.run(workflow, Keyword.merge(opts, inputs: Map.put(base_inputs, "repo_id", id)))
      end)

    {:ok, context, %{results: results}}
  end

  defp run_workflow_type(workflow, _repo_ids, repo_id, base_inputs, context, opts)
       when not is_nil(repo_id) do
    run_single_workflow(workflow, Map.put(base_inputs, "repo_id", repo_id), context, opts)
  end

  defp run_workflow_type(workflow, _repo_ids, _repo_id, base_inputs, context, opts) do
    run_single_workflow(workflow, base_inputs, context, opts)
  end

  defp run_single_workflow(workflow, inputs, context, opts) do
    case Engine.run(workflow, Keyword.merge(opts, inputs: inputs)) do
      {:ok, result} -> {:ok, context, %{result: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp drop_workflow_keys(inputs) do
    Map.drop(inputs, ["workflow", :workflow, "repo_id", :repo_id, "repo_ids", :repo_ids])
  end

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))
end
