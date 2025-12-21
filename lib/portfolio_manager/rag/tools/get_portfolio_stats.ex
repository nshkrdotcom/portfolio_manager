defmodule PortfolioManager.Rag.Tools.GetPortfolioStats do
  @moduledoc """
  Tool for getting portfolio statistics.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "get_portfolio_stats"

  @impl true
  def description do
    "Get overall portfolio statistics including total repos, " <>
      "breakdown by status, type, and language."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{},
      required: []
    }
  end

  @impl true
  def execute(_args, context) do
    portfolio = Map.fetch!(context, :portfolio)
    stats = PortfolioManager.status(portfolio)

    {:ok,
     %{
       total: stats.total,
       by_status: stats.by_status,
       by_type: stats.by_type,
       by_language: stats.by_language
     }}
  end
end
