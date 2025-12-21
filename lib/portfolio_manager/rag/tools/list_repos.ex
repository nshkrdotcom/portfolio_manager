defmodule PortfolioManager.Rag.Tools.ListRepos do
  @moduledoc """
  Tool for listing repositories with filters.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "list_repos"

  @impl true
  def description do
    "List repositories in the portfolio with optional filters. " <>
      "Can filter by status (active, stale, archived), type (library, application, port, fork), " <>
      "or language (elixir, python, etc.)."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        status: %{
          type: "string",
          description: "Filter by status: active, stale, archived, or unknown"
        },
        type: %{
          type: "string",
          description:
            "Filter by type: library, application, port, fork, experiment, template, config, docs"
        },
        language: %{
          type: "string",
          description: "Filter by language: elixir, python, javascript, etc."
        }
      },
      required: []
    }
  end

  @impl true
  def execute(args, context) do
    portfolio = Map.fetch!(context, :portfolio)

    opts =
      args
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), parse_value(v)} end)
      |> Enum.filter(fn {_k, v} -> v != nil end)

    repos =
      PortfolioManager.list_repos(portfolio, opts)
      |> Enum.map(&format_repo/1)

    {:ok,
     %{
       filters: opts,
       count: length(repos),
       repos: repos
     }}
  end

  defp parse_value(v) when is_binary(v) do
    try do
      String.to_existing_atom(v)
    rescue
      ArgumentError -> v
    end
  end

  defp parse_value(v), do: v

  defp format_repo(repo) do
    %{
      id: repo.id,
      name: repo.name,
      type: repo.type,
      language: repo.language,
      status: repo.status
    }
  end
end
