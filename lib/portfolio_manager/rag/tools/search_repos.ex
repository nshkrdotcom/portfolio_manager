defmodule PortfolioManager.Rag.Tools.SearchRepos do
  @moduledoc """
  Tool for searching repositories in the portfolio.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "search_repos"

  @impl true
  def description do
    "Search for repositories in the portfolio by query string. " <>
      "Searches across repo ID, name, purpose, and tags."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        query: %{
          type: "string",
          description: "The search query (e.g., 'authentication', 'elixir library')"
        }
      },
      required: ["query"]
    }
  end

  @impl true
  def execute(%{"query" => query}, context) do
    portfolio = Map.fetch!(context, :portfolio)

    results =
      PortfolioManager.search(portfolio, query)
      |> Enum.map(&format_repo/1)

    {:ok,
     %{
       query: query,
       count: length(results),
       repos: results
     }}
  end

  defp format_repo(repo) do
    %{
      id: repo.id,
      name: repo.name,
      path: repo.path,
      type: repo.type,
      language: repo.language,
      status: repo.status,
      purpose: Map.get(repo, :purpose)
    }
  end
end
