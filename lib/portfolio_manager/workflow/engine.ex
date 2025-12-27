defmodule PortfolioManager.Workflow.Engine do
  @moduledoc """
  Workflow execution engine.

  Executes multi-step workflows defined in YAML files.
  """

  alias PortfolioManager.Workflow.{Context, Parser, Step}

  @doc """
  Executes a workflow by name.

  ## Options

    * `:portfolio` - Portfolio server (required)
    * `:inputs` - Workflow inputs (map)
    * `:repo_id` - Target repository ID (optional)
    * `:dry_run` - Don't execute, just show what would happen
    * `:verbose` - Show detailed output

  ## Examples

      iex> Engine.run("port-check", portfolio: portfolio, inputs: %{"repo_id" => "my-port"})
      {:ok, %{steps: 5, completed: 5, failed: 0}}

  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workflow_name, opts \\ []) do
    with {:ok, workflow} <- Parser.load(workflow_name),
         {:ok, context} <- build_context(workflow, opts) do
      execute_workflow(workflow, context, opts)
    end
  end

  @doc """
  Lists available workflows.
  """
  @spec list_workflows() :: [map()]
  def list_workflows do
    workflow_dirs()
    |> Enum.flat_map(&list_workflow_files/1)
    |> Enum.map(&load_workflow_metadata/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets information about a specific workflow.
  """
  @spec get_workflow(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_workflow(name) do
    case Parser.load(name) do
      {:ok, workflow} ->
        {:ok,
         %{
           id: workflow.id,
           name: workflow.name,
           description: workflow.description,
           steps: Enum.map(workflow.steps, &step_summary/1)
         }}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  # Private

  defp build_context(workflow, opts) do
    portfolio = Keyword.get(opts, :portfolio)
    inputs = prepare_inputs(workflow, opts)
    base_context = build_base_context(workflow.id, inputs, portfolio)

    base_context
    |> maybe_add_repo_context(portfolio, Map.get(inputs, "repo_id"))
    |> finalize_context()
  end

  defp prepare_inputs(workflow, opts) do
    inputs = normalize_inputs(Keyword.get(opts, :inputs, %{}))
    repo_id = Keyword.get(opts, :repo_id) || Map.get(inputs, "repo_id")
    inputs = if repo_id, do: Map.put_new(inputs, "repo_id", repo_id), else: inputs
    apply_input_defaults(inputs, workflow.inputs || %{})
  end

  defp build_base_context(workflow_id, inputs, portfolio) do
    %{
      workflow: workflow_id,
      started_at: DateTime.utc_now(),
      inputs: inputs,
      vars: %{
        "now" => DateTime.to_iso8601(DateTime.utc_now()),
        "portfolio_path" =>
          portfolio && PortfolioManager.Portfolio.get_storage_state(portfolio).path
      }
    }
  end

  defp maybe_add_repo_context(base_context, nil, _repo_id), do: base_context
  defp maybe_add_repo_context(base_context, _portfolio, nil), do: base_context

  defp maybe_add_repo_context(base_context, portfolio, repo_id) do
    case PortfolioManager.get_repo(portfolio, repo_id) do
      {:ok, repo} ->
        {:ok, ctx} = PortfolioManager.get_context(portfolio, repo_id)
        Map.merge(base_context, %{repo: repo, context: ctx})

      {:error, _} = error ->
        error
    end
  end

  defp finalize_context(%{} = ctx), do: {:ok, Context.new(ctx)}
  defp finalize_context({:error, _} = error), do: error

  defp execute_workflow(workflow, context, opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    verbose = Keyword.get(opts, :verbose, false)

    initial_state = %{
      steps: length(workflow.steps),
      completed: 0,
      failed: 0,
      skipped: 0,
      results: []
    }

    result =
      Enum.reduce_while(workflow.steps, {context, initial_state}, fn step, {ctx, state} ->
        if verbose, do: IO.puts("  → #{step.name}")
        execute_step(step, ctx, state, dry_run, verbose, opts)
      end)

    {final_ctx, final_state} = result
    outputs = extract_outputs(workflow.outputs || %{}, final_ctx)

    {:ok,
     final_state
     |> Map.delete(:results)
     |> Map.put(:details, final_state.results)
     |> Map.put(:outputs, outputs)}
  end

  defp execute_step(_step, ctx, state, true, verbose, _opts) do
    if verbose, do: IO.puts("    (dry run)")
    {:cont, {ctx, %{state | completed: state.completed + 1}}}
  end

  defp execute_step(step, ctx, state, false, _verbose, opts) do
    case Step.execute(step, ctx, opts) do
      {:ok, new_ctx, result} ->
        handle_step_success(step, new_ctx, state, result)

      {:skip, reason} ->
        handle_step_skip(step, ctx, state, reason)

      {:error, reason} ->
        handle_step_error(step, ctx, state, reason)
    end
  end

  defp handle_step_success(step, new_ctx, state, result) do
    updated_ctx =
      new_ctx
      |> Context.set_result(step.id, result)
      |> apply_outputs(step.id, step.outputs, result)

    new_state = %{
      state
      | completed: state.completed + 1,
        results: state.results ++ [{step.name, :ok, result}]
    }

    {:cont, {updated_ctx, new_state}}
  end

  defp handle_step_skip(step, ctx, state, reason) do
    new_state = %{
      state
      | skipped: state.skipped + 1,
        results: state.results ++ [{step.name, :skipped, reason}]
    }

    {:cont, {ctx, new_state}}
  end

  defp handle_step_error(step, ctx, state, reason) do
    continue? = step.on_failure in ["continue", :continue]

    new_state = %{
      state
      | failed: state.failed + 1,
        results: state.results ++ [{step.name, :error, reason}]
    }

    if continue?, do: {:cont, {ctx, new_state}}, else: {:halt, {ctx, new_state}}
  end

  defp apply_outputs(ctx, step_id, outputs, result) do
    outputs = outputs || %{}

    if map_size(outputs) == 0 do
      Context.set_var(ctx, to_string(step_id), result)
    else
      Enum.reduce(outputs, ctx, fn {output_key, var_name}, acc ->
        value = fetch_output_value(result, output_key)
        Context.set_var(acc, to_string(var_name), value)
      end)
    end
  end

  defp fetch_output_value(result, key) when is_map(result) do
    Map.get(result, key) || Map.get(result, to_string(key)) ||
      Map.get(result, String.to_atom(to_string(key)))
  end

  defp fetch_output_value(result, _key), do: result

  defp extract_outputs(outputs, ctx) do
    Map.new(outputs, fn {key, value} ->
      {key, Context.resolve_inputs(ctx, value)}
    end)
  end

  defp workflow_dirs do
    priv_dir = :code.priv_dir(:portfolio_manager) |> to_string()
    builtin_dir = Path.join(priv_dir, "workflows")

    user_dir =
      case System.get_env("PORTFOLIO_DIR") do
        nil -> Path.join(System.user_home!(), "portfolio/workflows")
        dir -> Path.join(dir, "workflows")
      end

    [builtin_dir, user_dir]
    |> Enum.filter(&File.dir?/1)
  end

  defp list_workflow_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".yml"))
    |> Enum.map(&Path.join(dir, &1))
  end

  defp load_workflow_metadata(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, data} ->
        workflow = Map.get(data, "workflow") || %{}

        %{
          id: Map.get(workflow, "id") || Path.basename(path, ".yml"),
          name: Map.get(workflow, "name", Path.basename(path, ".yml")),
          description: Map.get(workflow, "description", ""),
          path: path
        }

      {:error, _} ->
        nil
    end
  end

  defp step_summary(step) do
    %{
      id: step.id,
      name: step.name,
      type: step.type,
      action: step.action
    }
  end

  defp normalize_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {k, v} -> {to_string(k), v} end)
  end

  defp apply_input_defaults(inputs, definitions) when is_map(definitions) do
    Enum.reduce(definitions, inputs, fn {key, defn}, acc ->
      key = to_string(key)
      if Map.has_key?(acc, key), do: acc, else: maybe_apply_default(acc, key, defn)
    end)
  end

  defp maybe_apply_default(inputs, key, defn) do
    case Map.get(defn, "default") || Map.get(defn, :default) do
      nil -> inputs
      default -> Map.put(inputs, key, default)
    end
  end
end
