defmodule PortfolioManager.Workflow.Steps.ContextStep do
  @moduledoc """
  Context step handlers for workflows.
  """

  alias PortfolioManager.Workflow.Context
  alias PortfolioManager.Domain.Context, as: DomainContext
  alias PortfolioManager.Domain.Repo, as: DomainRepo

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    portfolio = Keyword.get(opts, :portfolio)

    case action do
      "get_repo_context" ->
        repo_id = Map.get(inputs, "repo_id") || Map.get(inputs, :repo_id)
        get_repo_context(portfolio, repo_id, context)

      "get_related_context" ->
        repo_id = Map.get(inputs, "repo_id") || Map.get(inputs, :repo_id)
        depth = Map.get(inputs, "depth") || Map.get(inputs, :depth) || 1
        get_related_context(portfolio, repo_id, depth, context)

      "get_portfolio_context" ->
        get_portfolio_context(portfolio, context)

      "search_context" ->
        query = Map.get(inputs, "query") || Map.get(inputs, :query)
        search_context(portfolio, query, context)

      "aggregate" ->
        field = Map.get(inputs, "field") || Map.get(inputs, :field)
        repos = Map.get(inputs, "repos") || Map.get(inputs, :repos) || []
        aggregate(field, repos, context)

      "validate_relationships" ->
        {:ok, context, %{issues: []}}

      "set_var" ->
        key = Map.get(inputs, "key") || Map.get(inputs, :key)
        value = Map.get(inputs, "value") || Map.get(inputs, :value)
        new_ctx = Context.set_var(context, to_string(key), value)
        {:ok, new_ctx, %{value: value}}

      _ ->
        {:error, "Unknown context action: #{action}"}
    end
  end

  defp get_repo_context(nil, _repo_id, _context), do: {:error, "Portfolio not available"}
  defp get_repo_context(_portfolio, nil, _context), do: {:error, "repo_id required"}

  defp get_repo_context(portfolio, repo_id, context) do
    case PortfolioManager.get_context(portfolio, repo_id) do
      {:ok, repo_context} ->
        result = %{context: DomainContext.to_map(repo_context)}
        {:ok, context, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_related_context(nil, _repo_id, _depth, _context),
    do: {:error, "Portfolio not available"}

  defp get_related_context(_portfolio, nil, _depth, _context),
    do: {:error, "repo_id required"}

  defp get_related_context(portfolio, repo_id, _depth, context) do
    case PortfolioManager.get_context(portfolio, repo_id) do
      {:ok, repo_context} ->
        related_ids =
          PortfolioManager.get_relationships(portfolio, repo_id)
          |> Enum.map(fn rel -> if rel.from == repo_id, do: rel.to, else: rel.from end)
          |> Enum.uniq()

        related_contexts =
          related_ids
          |> Enum.flat_map(fn id ->
            case PortfolioManager.get_context(portfolio, id) do
              {:ok, ctx} -> [DomainContext.to_map(ctx)]
              _ -> []
            end
          end)

        result = %{
          repo: DomainContext.to_map(repo_context),
          related_repos: related_contexts
        }

        {:ok, context, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_portfolio_context(nil, _context), do: {:error, "Portfolio not available"}

  defp get_portfolio_context(portfolio, context) do
    repos =
      PortfolioManager.list_repos(portfolio)
      |> Enum.map(&DomainRepo.to_map/1)

    relationships = fetch_relationships(portfolio)

    {:ok, context, %{repos: repos, relationships: relationships}}
  end

  defp search_context(nil, _query, _context), do: {:error, "Portfolio not available"}
  defp search_context(_portfolio, nil, _context), do: {:error, "query required"}

  defp search_context(portfolio, query, context) do
    repos =
      PortfolioManager.search(portfolio, query)
      |> Enum.map(&DomainRepo.to_map/1)

    {:ok, context, %{repos: repos}}
  end

  defp aggregate(nil, _repos, _context), do: {:error, "field required"}

  defp aggregate(field, repos, context) do
    values =
      repos
      |> Enum.flat_map(fn repo ->
        value = Map.get(repo, field) || Map.get(repo, to_string(field))

        cond do
          is_list(value) -> value
          is_nil(value) -> []
          true -> [value]
        end
      end)

    {:ok, context, %{values: values}}
  end

  defp fetch_relationships(portfolio) do
    state = PortfolioManager.Portfolio.get_state(portfolio)
    state.registry.relationships
  end
end
