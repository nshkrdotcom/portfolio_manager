defmodule PortfolioManager.Workflow.Engine do
  @moduledoc """
  Workflow execution engine.

  Executes multi-step workflows defined in YAML files.
  Workflows can include git operations, shell commands, and agent steps.
  """

  alias PortfolioManager.Workflow.{Parser, Context, Step}

  @doc """
  Executes a workflow by name.

  ## Options

    * `:portfolio` - Portfolio server (required)
    * `:repo_id` - Target repository ID (optional)
    * `:dry_run` - Don't execute, just show what would happen
    * `:verbose` - Show detailed output

  ## Examples

      iex> Engine.run("port-check", portfolio: portfolio, repo_id: "my-port")
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
    repo_id = Keyword.get(opts, :repo_id)

    base_context = %{
      workflow: workflow.name,
      started_at: DateTime.utc_now(),
      vars: Map.get(workflow, :vars) || %{}
    }

    context =
      if repo_id do
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, repo} ->
            {:ok, ctx} = PortfolioManager.get_context(portfolio, repo_id)
            Map.merge(base_context, %{repo: repo, context: ctx})

          {:error, _} = error ->
            error
        end
      else
        base_context
      end

    case context do
      %{} = ctx -> {:ok, Context.new(ctx)}
      {:error, _} = error -> error
    end
  end

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
        if verbose do
          IO.puts("  → #{step.name}")
        end

        if dry_run do
          if verbose do
            IO.puts("    (dry run)")
          end

          {:cont, {ctx, %{state | completed: state.completed + 1}}}
        else
          case Step.execute(step, ctx, opts) do
            {:ok, new_ctx, result} ->
              new_state = %{
                state
                | completed: state.completed + 1,
                  results: state.results ++ [{step.name, :ok, result}]
              }

              {:cont, {new_ctx, new_state}}

            {:skip, reason} ->
              new_state = %{
                state
                | skipped: state.skipped + 1,
                  results: state.results ++ [{step.name, :skipped, reason}]
              }

              {:cont, {ctx, new_state}}

            {:error, reason} ->
              if step.continue_on_error do
                new_state = %{
                  state
                  | failed: state.failed + 1,
                    results: state.results ++ [{step.name, :error, reason}]
                }

                {:cont, {ctx, new_state}}
              else
                new_state = %{
                  state
                  | failed: state.failed + 1,
                    results: state.results ++ [{step.name, :error, reason}]
                }

                {:halt, {ctx, new_state}}
              end
          end
        end
      end)

    {_final_ctx, final_state} = result
    {:ok, Map.delete(final_state, :results) |> Map.put(:details, final_state.results)}
  end

  defp workflow_dirs do
    priv_dir = :code.priv_dir(:portfolio_manager) |> to_string()
    builtin_dir = Path.join(priv_dir, "workflows")

    user_dir =
      case System.get_env("PORTFOLIO_DIR") do
        nil -> Path.join(System.user_home!(), ".portfolio/workflows")
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
        %{
          name: Path.basename(path, ".yml"),
          description: Map.get(data, "description", ""),
          path: path
        }

      {:error, _} ->
        nil
    end
  end

  defp step_summary(step) do
    %{
      name: step.name,
      type: step.type,
      description: step[:description]
    }
  end
end
