defmodule PortfolioManager.Workflow.Steps.ContextStep do
  @moduledoc """
  Context step handlers for workflows.
  """

  alias PortfolioManager.Domain.Context, as: DomainContext
  alias PortfolioManager.Domain.Repo, as: DomainRepo
  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    portfolio = Keyword.get(opts, :portfolio)
    dispatch_action(action, inputs, portfolio, context)
  end

  defp dispatch_action("get_repo_context", inputs, portfolio, context) do
    repo_id = get_input(inputs, "repo_id")
    get_repo_context(portfolio, repo_id, context)
  end

  defp dispatch_action("get_related_context", inputs, portfolio, context) do
    repo_id = get_input(inputs, "repo_id")
    depth = get_input(inputs, "depth") || 1
    get_related_context(portfolio, repo_id, depth, context)
  end

  defp dispatch_action("get_portfolio_context", _inputs, portfolio, context) do
    get_portfolio_context(portfolio, context)
  end

  defp dispatch_action("search_context", inputs, portfolio, context) do
    query = get_input(inputs, "query")
    search_context(portfolio, query, context)
  end

  defp dispatch_action("aggregate", inputs, _portfolio, context) do
    field = get_input(inputs, "field")
    repos = get_input(inputs, "repos") || []
    aggregate(field, repos, context)
  end

  defp dispatch_action("validate_relationships", _inputs, _portfolio, context) do
    {:ok, context, %{issues: []}}
  end

  defp dispatch_action("set_var", inputs, _portfolio, context) do
    key = get_input(inputs, "key")
    value = get_input(inputs, "value")
    new_ctx = Context.set_var(context, to_string(key), value)
    {:ok, new_ctx, %{value: value}}
  end

  defp dispatch_action(action, _inputs, _portfolio, _context) do
    {:error, "Unknown context action: #{action}"}
  end

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))

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
        related_ids = extract_related_ids(portfolio, repo_id)

        related_contexts = fetch_related_contexts(portfolio, related_ids)

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

  defp extract_related_ids(portfolio, repo_id) do
    PortfolioManager.get_relationships(portfolio, repo_id)
    |> Enum.map(fn rel -> if rel.from == repo_id, do: rel.to, else: rel.from end)
    |> Enum.uniq()
  end

  defp fetch_related_contexts(portfolio, related_ids) do
    Enum.flat_map(related_ids, fn id ->
      case PortfolioManager.get_context(portfolio, id) do
        {:ok, ctx} -> [DomainContext.to_map(ctx)]
        _ -> []
      end
    end)
  end

  defp fetch_relationships(portfolio) do
    state = PortfolioManager.Portfolio.get_state(portfolio)
    state.registry.relationships
  end
end
