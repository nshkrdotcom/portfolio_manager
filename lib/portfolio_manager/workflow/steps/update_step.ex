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
    dispatch_action(action, portfolio, inputs, context)
  end

  defp dispatch_action("update_context", portfolio, inputs, context) do
    update_context(portfolio, inputs, context)
  end

  defp dispatch_action("add_relationship", portfolio, inputs, context) do
    add_relationship(portfolio, inputs, context)
  end

  defp dispatch_action("create_decision", portfolio, inputs, context) do
    create_decision(portfolio, inputs, context)
  end

  defp dispatch_action(action, _portfolio, _inputs, _context) do
    {:error, "Unknown update action: #{action}"}
  end

  defp update_context(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp update_context(portfolio, inputs, context) do
    repo_id = get_input(inputs, "repo_id") || (context.repo && context.repo.id)
    updates = get_input(inputs, "updates") || %{}

    case PortfolioManager.update_context(portfolio, repo_id, updates) do
      {:ok, _} -> {:ok, context, %{repo_id: repo_id, updates: updates}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_relationship(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp add_relationship(portfolio, inputs, context) do
    rel = get_input(inputs, "relationship") || %{}
    from = get_rel_field(rel, "from") || (context.repo && context.repo.id)
    to = get_rel_field(rel, "to")
    type = get_rel_field(rel, "type") || "related_to"

    case PortfolioManager.add_relationship(portfolio, from, to, String.to_atom(type)) do
      {:ok, _} -> {:ok, context, %{from: from, to: to, type: type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_decision(nil, _inputs, _context), do: {:error, "Portfolio not available"}

  defp create_decision(portfolio, inputs, context) do
    repo_id = get_input(inputs, "repo_id") || (context.repo && context.repo.id)
    decision = get_input(inputs, "decision") || %{}
    title = get_rel_field(decision, "title") || "Decision"
    content = get_rel_field(decision, "content") || ""

    case PortfolioManager.add_decision(portfolio, repo_id, title, content) do
      {:ok, _} -> {:ok, context, %{repo_id: repo_id, title: title}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))
  defp get_rel_field(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))
end
