defmodule PortfolioManager.Rag.Tools.GetRepoContext do
  @moduledoc """
  Tool for getting detailed context about a repository.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "get_repo_context"

  @impl true
  def description do
    "Get detailed context for a repository including notes, decisions, " <>
      "relationships, and metadata. Use this when you need comprehensive " <>
      "information about a specific repo."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        repo_id: %{
          type: "string",
          description: "The repository ID to get context for"
        }
      },
      required: ["repo_id"]
    }
  end

  @impl true
  def execute(%{"repo_id" => repo_id}, context) do
    portfolio = Map.fetch!(context, :portfolio)

    case PortfolioManager.get_context(portfolio, repo_id) do
      {:ok, ctx} ->
        relationships = PortfolioManager.get_relationships(portfolio, repo_id)

        {:ok,
         %{
           repo_id: repo_id,
           repo: format_repo(ctx.repo),
           notes: ctx.notes,
           decisions: ctx.decisions,
           todos: ctx.todos,
           relationships: Enum.map(relationships, &format_relationship/1),
           port_info: ctx.port,
           updated_at: ctx.updated_at
         }}

      {:error, :not_found} ->
        {:error, "Repository '#{repo_id}' not found in portfolio"}
    end
  end

  defp format_repo(repo) do
    %{
      id: repo.id,
      name: repo.name,
      path: repo.path,
      type: repo.type,
      language: repo.language,
      status: repo.status,
      remote_url: repo.remote_url,
      tags: repo.tags
    }
  end

  defp format_relationship(rel) do
    %{
      from: rel.from,
      to: rel.to,
      type: rel.type,
      notes: rel.notes
    }
  end
end
