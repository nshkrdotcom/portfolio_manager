# Pipeline Guide

The Pipeline module provides DAG-based workflow orchestration with caching for multi-step processing.

## Overview

`PortfolioManager.Pipeline` allows you to define workflows as directed acyclic graphs (DAGs) of steps. Each step can depend on others, and the pipeline ensures they execute in the correct order.

Features:
- **Dependency resolution** - Steps execute only when dependencies complete
- **Caching** - Results are cached to avoid re-computation
- **Timeouts** - Individual step timeout control
- **Telemetry** - Events for monitoring pipeline execution

## Basic Usage

```elixir
import PortfolioManager.Pipeline

result = run(:my_pipeline, %{input: "data"}) do
  step :first, fn input -> input.input <> "_processed" end
  step :second, fn input -> String.upcase(input.deps.first) end, depends_on: [:first]
end

# {:ok, %{first: "data_processed", second: "DATA_PROCESSED"}}
```

## Defining Steps

Each step receives an input map containing:
- All keys from the initial context
- `deps`: A map of results from dependent steps

```elixir
step :my_step, fn input ->
  # Access context
  context_value = input.my_key

  # Access dependency results
  previous_result = input.deps.other_step

  # Return result
  {:ok, computed_value}
end
```

## Step Options

```elixir
step :name, &function/1,
  depends_on: [:step1, :step2],  # Dependencies
  timeout: 30_000,               # Timeout in ms (default: 60_000)
  cache: true                    # Cache result (default: true)
```

## Dependencies

Steps are executed in topological order based on their dependencies:

```elixir
run(:ordered, %{}) do
  step :a, fn _ -> 1 end
  step :b, fn input -> input.deps.a + 1 end, depends_on: [:a]
  step :c, fn input -> input.deps.b + 1 end, depends_on: [:b]
  step :d, fn input -> input.deps.a + input.deps.c end, depends_on: [:a, :c]
end

# Execution order: a -> b -> c -> d
# Result: %{a: 1, b: 2, c: 3, d: 4}
```

## Caching

By default, step results are cached based on:
- Step name
- Hash of the input context

This means running the same pipeline with the same context will reuse cached results.

```elixir
# Disable caching for a step
step :volatile, fn _ -> DateTime.utc_now() end, cache: false
```

## Error Handling

If a step fails, the pipeline halts and returns the error:

```elixir
case run(:pipeline, %{}) do
  {:ok, results} ->
    IO.inspect(results)

  {:error, {:timeout, step_name}} ->
    IO.puts("Step #{step_name} timed out")

  {:error, reason} ->
    IO.puts("Pipeline failed: #{inspect(reason)}")
end
```

## Telemetry Events

The pipeline emits telemetry events you can attach handlers to:

```elixir
# Step started
[:portfolio_manager, :pipeline, :step_start]
# Metadata: %{pipeline: name, step: step_name}

# Step completed
[:portfolio_manager, :pipeline, :step_complete]
# Metadata: %{pipeline: name, step: step_name}

# Step failed
[:portfolio_manager, :pipeline, :step_error]
# Metadata: %{pipeline: name, step: step_name, error: reason}
```

Example handler:

```elixir
:telemetry.attach(
  "pipeline-logger",
  [:portfolio_manager, :pipeline, :step_complete],
  fn _event, _measurements, metadata, _config ->
    IO.puts("Completed step: #{metadata.step}")
  end,
  nil
)
```

## Real-World Example

```elixir
import PortfolioManager.Pipeline

run(:code_analysis, %{repo_path: "/path/to/repo"}) do
  step :scan_files, fn input ->
    files = Path.wildcard(Path.join(input.repo_path, "**/*.ex"))
    {:ok, files}
  end

  step :parse_modules, fn input ->
    modules = Enum.map(input.deps.scan_files, &parse_module/1)
    {:ok, modules}
  end, depends_on: [:scan_files]

  step :extract_functions, fn input ->
    functions = Enum.flat_map(input.deps.parse_modules, &extract_functions/1)
    {:ok, functions}
  end, depends_on: [:parse_modules]

  step :build_graph, fn input ->
    graph = build_call_graph(input.deps.extract_functions)
    {:ok, graph}
  end, depends_on: [:extract_functions]

  step :generate_report, fn input ->
    report = format_report(input.deps.build_graph)
    {:ok, report}
  end, depends_on: [:build_graph]
end
```

## Parallel Execution

Steps without dependencies between them can potentially run in parallel. Currently, the pipeline executes steps sequentially, but the topological ordering ensures independent steps are identified.

## Best Practices

1. **Keep steps focused** - Each step should do one thing well
2. **Use meaningful names** - Step names appear in errors and telemetry
3. **Set appropriate timeouts** - Adjust based on expected step duration
4. **Enable caching wisely** - Disable for steps with side effects
5. **Handle errors gracefully** - Steps can return `{:error, reason}`
