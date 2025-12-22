defmodule PortfolioManager.Workflow.Steps.UpdateStep do
  @moduledoc """
  Portfolio update steps.
  """

  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    portfolio = Keyword.get(opts, :portfolio)

    case action do
      "update_context" ->
        update_context(portfolio, inputs, context)

      "add_relationship" ->
        add_relationship(portfolio, inputs, context)

      "create_decision" ->
        create_decision(portfolio, inputs, context)

      _ ->
        {:error, "Unknown update action: #{action}"}
    end
  end

  defp update_context(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp update_context(portfolio, inputs, context) do
    repo_id =
      Map.get(inputs, "repo_id") || Map.get(inputs, :repo_id) || (context.repo && context.repo.id)

    updates = Map.get(inputs, "updates") || Map.get(inputs, :updates) || %{}

    case PortfolioManager.update_context(portfolio, repo_id, updates) do
      {:ok, _} -> {:ok, context, %{repo_id: repo_id, updates: updates}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_relationship(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp add_relationship(portfolio, inputs, context) do
    rel = Map.get(inputs, "relationship") || Map.get(inputs, :relationship) || %{}
    from = Map.get(rel, "from") || Map.get(rel, :from) || (context.repo && context.repo.id)
    to = Map.get(rel, "to") || Map.get(rel, :to)
    type = Map.get(rel, "type") || Map.get(rel, :type) || "related_to"

    case PortfolioManager.add_relationship(portfolio, from, to, String.to_atom(type)) do
      {:ok, _} -> {:ok, context, %{from: from, to: to, type: type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_decision(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp create_decision(portfolio, inputs, context) do
    repo_id =
      Map.get(inputs, "repo_id") || Map.get(inputs, :repo_id) || (context.repo && context.repo.id)

    decision = Map.get(inputs, "decision") || Map.get(inputs, :decision) || %{}
    title = Map.get(decision, "title") || Map.get(decision, :title) || "Decision"
    content = Map.get(decision, "content") || Map.get(decision, :content) || ""

    case PortfolioManager.add_decision(portfolio, repo_id, title, content) do
      {:ok, _} -> {:ok, context, %{repo_id: repo_id, title: title}}
      {:error, reason} -> {:error, reason}
    end
  end
end
