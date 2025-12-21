defmodule PortfolioManager.Rag.Tools.FindRelationships do
  @moduledoc """
  Tool for finding relationships between repositories.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "find_relationships"

  @impl true
  def description do
    "Find relationships for a repository. Shows how repos connect via " <>
      "dependencies, ports, forks, and other relationship types."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        repo_id: %{
          type: "string",
          description: "The repository ID to find relationships for"
        }
      },
      required: ["repo_id"]
    }
  end

  @impl true
  def execute(%{"repo_id" => repo_id}, context) do
    portfolio = Map.fetch!(context, :portfolio)

    case PortfolioManager.get_repo(portfolio, repo_id) do
      {:ok, _repo} ->
        relationships = PortfolioManager.get_relationships(portfolio, repo_id)

        formatted =
          relationships
          |> Enum.map(fn rel ->
            %{
              from: rel.from,
              to: rel.to,
              type: rel.type,
              direction: if(rel.from == repo_id, do: :outgoing, else: :incoming),
              notes: rel.notes
            }
          end)

        {:ok,
         %{
           repo_id: repo_id,
           count: length(formatted),
           relationships: formatted
         }}

      {:error, :not_found} ->
        {:error, "Repository '#{repo_id}' not found"}
    end
  end
end
