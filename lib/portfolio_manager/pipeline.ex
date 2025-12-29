defmodule PortfolioManager.Pipeline do
  @moduledoc """
  DAG-based pipeline orchestration with caching, parallel execution, and error policies.

  Pipelines allow you to define multi-step workflows with dependencies
  between steps. Steps are executed in topological order, with caching
  to avoid re-computation.

  ## Example

      import PortfolioManager.Pipeline

      run(:code_analysis, %{repo_path: "/path/to/repo"}) do
        step :scan_files, &scan_repo/1
        step :extract_entities, &extract/1, depends_on: [:scan_files]
        step :build_graph, &graph/1, depends_on: [:extract_entities]
        step :generate_summary, &summarize/1, depends_on: [:build_graph]
      end

  ## Parallel Execution

  Steps with no dependencies on each other can run in parallel:

      step :fetch_users, &fetch_users/1, parallel: true
      step :fetch_products, &fetch_products/1, parallel: true
      step :combine, &combine/1, depends_on: [:fetch_users, :fetch_products]

  ## Error Policies

  Configure how errors are handled:

      # Halt the pipeline on error (default)
      step :critical, &critical_op/1, on_error: :halt

      # Continue despite errors
      step :optional, &optional_op/1, on_error: :continue

      # Retry up to N times
      step :flaky, &flaky_op/1, on_error: {:retry, 3}

  ## Step Results

  Each step receives an input map containing:
  - All keys from the initial context
  - `deps`: A map of results from dependent steps

  Steps should return `{:ok, result}` or `{:error, reason}`.
  Bare return values are automatically wrapped in `{:ok, value}`.
  """

  require Logger

  @type on_error :: :halt | :continue | {:retry, pos_integer()}

  @type step :: %{
          name: atom(),
          function: fun(),
          depends_on: [atom()],
          timeout: pos_integer(),
          cache: boolean(),
          parallel: boolean(),
          on_error: on_error()
        }

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t() | nil,
          steps: [step()],
          config: map(),
          metadata: map(),
          cache_table: atom() | reference(),
          results: map()
        }

  defstruct [
    :name,
    :description,
    :cache_table,
    steps: [],
    config: %{},
    metadata: %{},
    results: %{}
  ]

  @doc """
  Define and run a pipeline.
  """
  defmacro run(name, context, do: block) do
    quote do
      pipeline = %PortfolioManager.Pipeline{
        name: unquote(name),
        steps: [],
        cache_table: :ets.new(:pipeline_cache, [:set, :public]),
        results: %{}
      }

      var!(pipeline) = pipeline
      unquote(block)

      PortfolioManager.Pipeline.execute(var!(pipeline), unquote(context))
    end
  end

  @doc """
  Add a step to the pipeline.

  ## Options

    * `:depends_on` - List of step names this step depends on
    * `:timeout` - Step timeout in milliseconds (default: 60_000)
    * `:cache` - Whether to cache step results (default: true)
    * `:parallel` - Whether this step can run in parallel (default: false)
    * `:on_error` - Error handling policy: `:halt`, `:continue`, or `{:retry, count}` (default: `:halt`)
  """
  defmacro step(name, func, opts \\ []) do
    quote do
      step = %{
        name: unquote(name),
        function: unquote(func),
        depends_on: Keyword.get(unquote(opts), :depends_on, []),
        timeout: Keyword.get(unquote(opts), :timeout, 60_000),
        cache: Keyword.get(unquote(opts), :cache, true),
        parallel: Keyword.get(unquote(opts), :parallel, false),
        on_error: Keyword.get(unquote(opts), :on_error, :halt)
      }

      var!(pipeline) = update_in(var!(pipeline).steps, &[step | &1])
    end
  end

  @doc """
  Create a new pipeline struct.

  ## Options

    * `:description` - Pipeline description
    * `:config` - Pipeline-level configuration map
    * `:metadata` - User metadata map
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      description: Keyword.get(opts, :description),
      config: Keyword.get(opts, :config, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      cache_table: :ets.new(:pipeline_cache, [:set, :public]),
      steps: [],
      results: %{}
    }
  end

  @doc """
  Add a step to an existing pipeline.
  """
  @spec add_step(t(), atom(), fun(), keyword()) :: t()
  def add_step(pipeline, name, function, opts \\ []) do
    step = %{
      name: name,
      function: function,
      depends_on: Keyword.get(opts, :depends_on, []),
      timeout: Keyword.get(opts, :timeout, 60_000),
      cache: Keyword.get(opts, :cache, true),
      parallel: Keyword.get(opts, :parallel, false),
      on_error: Keyword.get(opts, :on_error, :halt)
    }

    %{pipeline | steps: pipeline.steps ++ [step]}
  end

  @doc """
  Execute a pipeline with dependency resolution.

  Supports both sequential and parallel execution based on step configuration.
  """
  @spec execute(t(), map()) :: {:ok, map()} | {:error, term()}
  def execute(pipeline, context) do
    steps = Enum.reverse(pipeline.steps)
    execution_order = build_execution_order(steps)

    execute_groups(pipeline, execution_order, context, %{})
  end

  defp build_execution_order(steps) do
    graph = build_dependency_graph(steps)
    in_degree = calculate_in_degrees(steps, graph)

    build_groups(steps, in_degree, graph, [])
  end

  defp build_groups(steps, in_degree, graph, groups) do
    ready =
      in_degree
      |> Enum.filter(fn {_name, degree} -> degree == 0 end)
      |> Enum.map(fn {name, _} -> name end)

    case ready do
      [] when map_size(in_degree) > 0 ->
        raise "Cycle detected in pipeline dependencies"

      [] ->
        Enum.reverse(groups)

      _ ->
        ready_steps = Enum.filter(steps, fn s -> s.name in ready end)
        remaining_steps = Enum.reject(steps, fn s -> s.name in ready end)
        new_in_degree = update_in_degrees(in_degree, ready, remaining_steps)

        # Group steps that can run in parallel (default to false if not specified)
        {parallel_steps, sequential_steps} =
          Enum.split_with(ready_steps, &Map.get(&1, :parallel, false))

        new_groups =
          case {parallel_steps, sequential_steps} do
            {[], seq} -> [{:sequential, seq} | groups]
            {par, []} -> [{:parallel, par} | groups]
            {par, seq} -> [{:sequential, seq}, {:parallel, par} | groups]
          end

        build_groups(remaining_steps, new_in_degree, graph, new_groups)
    end
  end

  defp execute_groups(_pipeline, [], _context, results) do
    {:ok, results}
  end

  defp execute_groups(pipeline, [{:sequential, steps} | rest], context, results) do
    case execute_sequential(pipeline, steps, context, results) do
      {:ok, new_results} ->
        execute_groups(pipeline, rest, context, new_results)

      {:error, _} = error ->
        error
    end
  end

  defp execute_groups(pipeline, [{:parallel, steps} | rest], context, results) do
    case execute_parallel(pipeline, steps, context, results) do
      {:ok, new_results} ->
        execute_groups(pipeline, rest, context, new_results)

      {:error, _} = error ->
        error
    end
  end

  defp execute_sequential(pipeline, steps, context, results) do
    Enum.reduce_while(steps, {:ok, results}, fn step, {:ok, acc_results} ->
      emit_telemetry(:step_start, %{pipeline: pipeline.name, step: step.name})

      case execute_step_with_policy(pipeline, step, acc_results, context) do
        {:ok, result} ->
          emit_telemetry(:step_complete, %{pipeline: pipeline.name, step: step.name})
          {:cont, {:ok, Map.put(acc_results, step.name, result)}}

        {:error, reason} = error ->
          handle_step_error(pipeline, step, reason, acc_results, error)
      end
    end)
  end

  defp handle_step_error(pipeline, step, reason, acc_results, error) do
    on_error = Map.get(step, :on_error, :halt)

    case on_error do
      :continue ->
        Logger.warning("Step #{step.name} failed but continuing: #{inspect(reason)}")

        emit_telemetry(:step_error, %{
          pipeline: pipeline.name,
          step: step.name,
          error: reason,
          continued: true
        })

        {:cont, {:ok, Map.put(acc_results, step.name, {:error, reason})}}

      _ ->
        emit_telemetry(:step_error, %{pipeline: pipeline.name, step: step.name, error: reason})
        {:halt, error}
    end
  end

  defp execute_parallel(pipeline, steps, context, results) do
    tasks =
      Enum.map(steps, fn step ->
        Task.async(fn ->
          emit_telemetry(:step_start, %{pipeline: pipeline.name, step: step.name})
          result = execute_step_with_policy(pipeline, step, results, context)
          {step, result}
        end)
      end)

    # Collect results with timeouts
    max_timeout = Enum.map(steps, & &1.timeout) |> Enum.max()

    task_results =
      Task.yield_many(tasks, max_timeout + 1000)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} ->
            value

          nil ->
            _shutdown = Task.shutdown(task, :brutal_kill)
            step = Enum.find(steps, fn s -> s.name == task.ref end)
            {step, {:error, :timeout}}
        end
      end)

    # Process results
    Enum.reduce_while(task_results, {:ok, results}, fn {step, result}, {:ok, acc} ->
      on_error = Map.get(step, :on_error, :halt)

      case {result, on_error} do
        {{:ok, value}, _} ->
          emit_telemetry(:step_complete, %{pipeline: pipeline.name, step: step.name})
          {:cont, {:ok, Map.put(acc, step.name, value)}}

        {{:error, reason}, :continue} ->
          Logger.warning("Parallel step #{step.name} failed but continuing: #{inspect(reason)}")

          emit_telemetry(:step_error, %{
            pipeline: pipeline.name,
            step: step.name,
            error: reason,
            continued: true
          })

          {:cont, {:ok, Map.put(acc, step.name, {:error, reason})}}

        {{:error, reason}, _} ->
          # :halt or {:retry, n} (retry already attempted)
          emit_telemetry(:step_error, %{pipeline: pipeline.name, step: step.name, error: reason})
          {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_step_with_policy(pipeline, step, results, context) do
    case Map.get(step, :on_error, :halt) do
      {:retry, n} ->
        execute_with_retry(pipeline, step, results, context, n)

      _ ->
        execute_step(pipeline, step, results, context)
    end
  end

  defp execute_with_retry(pipeline, step, results, context, retries_left) when retries_left > 0 do
    case execute_step(pipeline, step, results, context) do
      {:ok, _} = success ->
        success

      {:error, reason} ->
        Logger.warning(
          "Step #{step.name} failed (#{retries_left} retries left): #{inspect(reason)}"
        )

        execute_with_retry(pipeline, step, results, context, retries_left - 1)
    end
  end

  defp execute_with_retry(pipeline, step, results, context, 0) do
    execute_step(pipeline, step, results, context)
  end

  defp execute_step(pipeline, step, results, context) do
    cache_key = {step.name, :erlang.phash2(context)}

    if step.cache do
      case :ets.lookup(pipeline.cache_table, cache_key) do
        [{^cache_key, cached}] ->
          Logger.debug("Cache hit for step #{step.name}")
          {:ok, cached}

        [] ->
          do_execute_step(pipeline, step, results, context, cache_key)
      end
    else
      do_execute_step(pipeline, step, results, context, nil)
    end
  end

  defp do_execute_step(pipeline, step, results, context, cache_key) do
    input = build_step_input(step, results, context)

    task = Task.async(fn -> step.function.(input) end)

    case Task.yield(task, step.timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        if cache_key, do: :ets.insert(pipeline.cache_table, {cache_key, result})
        {:ok, result}

      {:ok, {:error, _} = error} ->
        error

      {:ok, result} ->
        if cache_key, do: :ets.insert(pipeline.cache_table, {cache_key, result})
        {:ok, result}

      nil ->
        {:error, {:timeout, step.name}}
    end
  end

  defp build_step_input(step, results, context) do
    deps =
      step.depends_on
      |> Enum.map(fn dep -> {dep, Map.get(results, dep)} end)
      |> Map.new()

    Map.merge(context, %{deps: deps})
  end

  defp build_dependency_graph(steps) do
    Map.new(steps, fn step -> {step.name, step.depends_on} end)
  end

  defp calculate_in_degrees(steps, _graph) do
    initial = Map.new(steps, fn s -> {s.name, 0} end)

    Enum.reduce(steps, initial, fn step, acc ->
      Enum.reduce(step.depends_on, acc, fn _dep, a ->
        Map.update!(a, step.name, &(&1 + 1))
      end)
    end)
  end

  defp update_in_degrees(in_degree, ready, remaining_steps) do
    base_degrees = Map.drop(in_degree, ready)

    Enum.reduce(ready, base_degrees, fn name, acc ->
      decrement_dependents(acc, name, remaining_steps)
    end)
  end

  defp decrement_dependents(degrees, name, remaining_steps) do
    dependents =
      remaining_steps
      |> Enum.filter(fn s -> name in s.depends_on end)
      |> Enum.map(& &1.name)

    Enum.reduce(dependents, degrees, fn dep, acc ->
      Map.update!(acc, dep, &(&1 - 1))
    end)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_manager, :pipeline, event],
      %{time: System.monotonic_time()},
      metadata
    )
  end
end
