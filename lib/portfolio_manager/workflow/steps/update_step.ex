defmodule PortfolioManager.Workflow.Steps.UpdateStep do
  @moduledoc """
  Portfolio update step.

  Updates repository context in the portfolio.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes an update step.

  ## Config Options

    * `fields` - Map of fields to update on the repo context
    * `note` - Note to add
    * `decision` - Decision to add (map with title and content)
    * `status` - New status for the repo
    * `tags` - Tags to set or add

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    config = step.config
    portfolio = Keyword.get(opts, :portfolio)

    repo_id =
      cond do
        context.repo -> context.repo.id
        Context.get_var(context, "repo_id") -> Context.get_var(context, "repo_id")
        true -> nil
      end

    cond do
      is_nil(portfolio) ->
        {:error, "Portfolio not available for update step"}

      is_nil(repo_id) ->
        {:error, "No repository ID available for update step"}

      true ->
        execute_update(config, repo_id, portfolio, context, step.name)
    end
  end

  defp execute_update(config, repo_id, portfolio, context, step_name) do
    updates = build_updates(config, context)
    note = Map.get(config, "note")
    decision = Map.get(config, "decision")

    results = []

    # Apply field updates
    {results, context} =
      if map_size(updates) > 0 do
        case PortfolioManager.update_context(portfolio, repo_id, updates) do
          {:ok, _} -> {results ++ [:fields_updated], context}
          {:error, reason} -> {results ++ [{:error, :fields, reason}], context}
        end
      else
        {results, context}
      end

    # Add note
    {results, context} =
      if note do
        interpolated = Context.interpolate(context, note)

        case PortfolioManager.add_note(portfolio, repo_id, interpolated) do
          {:ok, _} -> {results ++ [:note_added], context}
          {:error, reason} -> {results ++ [{:error, :note, reason}], context}
        end
      else
        {results, context}
      end

    # Add decision
    {results, context} =
      if decision do
        title = Context.interpolate(context, Map.get(decision, "title", ""))
        content = Context.interpolate(context, Map.get(decision, "content", ""))

        case PortfolioManager.add_decision(portfolio, repo_id, title, content) do
          {:ok, _} -> {results ++ [:decision_added], context}
          {:error, reason} -> {results ++ [{:error, :decision, reason}], context}
        end
      else
        {results, context}
      end

    # Sync changes
    PortfolioManager.sync(portfolio)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(errors) do
      result = %{repo_id: repo_id, updates: results}
      new_ctx = Context.set_result(context, step_name, result)
      {:ok, new_ctx, result}
    else
      {:error, "Update failed: #{inspect(errors)}"}
    end
  end

  defp build_updates(config, context) do
    updates = %{}

    updates =
      case Map.get(config, "status") do
        nil -> updates
        status -> Map.put(updates, :status, String.to_atom(status))
      end

    updates =
      case Map.get(config, "type") do
        nil -> updates
        type -> Map.put(updates, :type, String.to_atom(type))
      end

    updates =
      case Map.get(config, "purpose") do
        nil -> updates
        purpose -> Map.put(updates, :purpose, Context.interpolate(context, purpose))
      end

    updates =
      case Map.get(config, "tags") do
        nil -> updates
        tags when is_list(tags) -> Map.put(updates, :tags, tags)
        tags when is_binary(tags) -> Map.put(updates, :tags, String.split(tags, ","))
      end

    updates =
      case Map.get(config, "priority") do
        nil -> updates
        priority -> Map.put(updates, :priority, String.to_atom(priority))
      end

    # Handle custom fields
    fields = Map.get(config, "fields", %{})

    Enum.reduce(fields, updates, fn {key, value}, acc ->
      interpolated =
        if is_binary(value), do: Context.interpolate(context, value), else: value

      Map.put(acc, String.to_atom(key), interpolated)
    end)
  end
end
