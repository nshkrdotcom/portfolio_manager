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
    workflow = Map.get(inputs, "workflow") || Map.get(inputs, :workflow)
    repo_id = Map.get(inputs, "repo_id") || Map.get(inputs, :repo_id)
    repo_ids = Map.get(inputs, "repo_ids") || Map.get(inputs, :repo_ids)

    base_inputs =
      inputs
      |> Map.drop(["workflow", :workflow, "repo_id", :repo_id, "repo_ids", :repo_ids])

    cond do
      is_list(repo_ids) ->
        results =
          Enum.map(repo_ids, fn id ->
            Engine.run(workflow, Keyword.merge(opts, inputs: Map.put(base_inputs, "repo_id", id)))
          end)

        {:ok, context, %{results: results}}

      repo_id ->
        case Engine.run(
               workflow,
               Keyword.merge(opts, inputs: Map.put(base_inputs, "repo_id", repo_id))
             ) do
          {:ok, result} -> {:ok, context, %{result: result}}
          {:error, reason} -> {:error, reason}
        end

      true ->
        case Engine.run(workflow, Keyword.merge(opts, inputs: base_inputs)) do
          {:ok, result} -> {:ok, context, %{result: result}}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
