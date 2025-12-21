defmodule PortfolioManager.Rag.Tools.CompareRepos do
  @moduledoc """
  Tool for comparing two repositories.
  """

  @behaviour Rag.Agent.Tool

  @impl true
  def name, do: "compare_repos"

  @impl true
  def description do
    "Compare two repositories to find differences and similarities. " <>
      "Useful for comparing a port to its upstream, or related projects."
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        repo_a: %{
          type: "string",
          description: "First repository ID"
        },
        repo_b: %{
          type: "string",
          description: "Second repository ID"
        }
      },
      required: ["repo_a", "repo_b"]
    }
  end

  @impl true
  def execute(%{"repo_a" => repo_a, "repo_b" => repo_b}, context) do
    portfolio = Map.fetch!(context, :portfolio)

    with {:ok, ctx_a} <- PortfolioManager.get_context(portfolio, repo_a),
         {:ok, ctx_b} <- PortfolioManager.get_context(portfolio, repo_b) do
      comparison = build_comparison(ctx_a, ctx_b)
      {:ok, comparison}
    else
      {:error, :not_found} ->
        {:error, "One or both repositories not found"}
    end
  end

  defp build_comparison(ctx_a, ctx_b) do
    repo_a = ctx_a.repo
    repo_b = ctx_b.repo

    %{
      repos: %{
        a: %{id: repo_a.id, name: repo_a.name, type: repo_a.type, language: repo_a.language},
        b: %{id: repo_b.id, name: repo_b.name, type: repo_b.type, language: repo_b.language}
      },
      same_language: repo_a.language == repo_b.language,
      same_type: repo_a.type == repo_b.type,
      comparison: %{
        types: %{a: repo_a.type, b: repo_b.type},
        languages: %{a: repo_a.language, b: repo_b.language},
        statuses: %{a: repo_a.status, b: repo_b.status}
      },
      port_relationship: detect_port_relationship(ctx_a, ctx_b),
      notes: %{
        a: ctx_a.notes,
        b: ctx_b.notes
      }
    }
  end

  defp detect_port_relationship(ctx_a, ctx_b) do
    cond do
      ctx_a.port && ctx_a.port[:upstream_url] ->
        %{type: :a_is_port_of_upstream, upstream_url: ctx_a.port.upstream_url}

      ctx_b.port && ctx_b.port[:upstream_url] ->
        %{type: :b_is_port_of_upstream, upstream_url: ctx_b.port.upstream_url}

      true ->
        nil
    end
  end
end
