# Pipeline Workflow Example
#
# This example demonstrates DAG-based pipeline orchestration.
#
# Run with: mix run examples/pipeline_workflow.exs

import PortfolioManager.Pipeline

IO.puts("=== Pipeline Workflow Example ===\n")

# Attach telemetry handler to see pipeline progress
:telemetry.attach(
  "pipeline-example",
  [:portfolio_manager, :pipeline, :step_complete],
  fn _event, _measurements, metadata, _config ->
    IO.puts("  [OK] Step completed: #{metadata.step}")
  end,
  nil
)

:telemetry.attach(
  "pipeline-example-start",
  [:portfolio_manager, :pipeline, :step_start],
  fn _event, _measurements, metadata, _config ->
    IO.puts("  [..] Starting step: #{metadata.step}")
  end,
  nil
)

# Simple arithmetic pipeline
IO.puts("--- Pipeline 1: Simple Arithmetic ---\n")

result1 =
  run(:arithmetic, %{value: 10}) do
    step(:double, fn input -> input.value * 2 end)
    step(:add_five, fn input -> input.deps.double + 5 end, depends_on: [:double])

    step(:square, fn input -> input.deps.add_five * input.deps.add_five end,
      depends_on: [:add_five]
    )
  end

case result1 do
  {:ok, results} ->
    IO.puts("\nResults:")
    IO.puts("  Input: 10")
    IO.puts("  After double: #{results.double}")
    IO.puts("  After add_five: #{results.add_five}")
    IO.puts("  After square: #{results.square}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# File processing pipeline
IO.puts("--- Pipeline 2: File Processing ---\n")

result2 =
  run(:file_processing, %{directory: "lib"}) do
    step(:list_files, fn input ->
      Path.wildcard(Path.join(input.directory, "**/*.ex"))
      |> Enum.take(5)
    end)

    step(
      :count_files,
      fn input ->
        length(input.deps.list_files)
      end,
      depends_on: [:list_files]
    )

    step(
      :read_sizes,
      fn input ->
        Enum.map(input.deps.list_files, fn path ->
          case File.stat(path) do
            {:ok, stat} -> {path, stat.size}
            _ -> {path, 0}
          end
        end)
      end,
      depends_on: [:list_files]
    )

    step(
      :total_size,
      fn input ->
        input.deps.read_sizes
        |> Enum.map(fn {_, size} -> size end)
        |> Enum.sum()
      end,
      depends_on: [:read_sizes]
    )

    step(
      :summary,
      fn input ->
        %{
          file_count: input.deps.count_files,
          total_bytes: input.deps.total_size,
          average_size: div(input.deps.total_size, max(input.deps.count_files, 1))
        }
      end,
      depends_on: [:count_files, :total_size]
    )
  end

case result2 do
  {:ok, results} ->
    IO.puts("\nSummary:")
    IO.puts("  Files found: #{results.summary.file_count}")
    IO.puts("  Total size: #{results.summary.total_bytes} bytes")
    IO.puts("  Average size: #{results.summary.average_size} bytes")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# Pipeline with timeout
IO.puts("--- Pipeline 3: Timeout Handling ---\n")

result3 =
  run(:timeout_test, %{}) do
    step(:fast, fn _ -> "quick result" end, timeout: 5000)

    step(
      :slower,
      fn _ ->
        Process.sleep(100)
        "slower result"
      end,
      depends_on: [:fast],
      timeout: 5000
    )
  end

case result3 do
  {:ok, results} ->
    IO.puts("\nBoth steps completed:")
    IO.puts("  Fast: #{results.fast}")
    IO.puts("  Slower: #{results.slower}")

  {:error, {:timeout, step}} ->
    IO.puts("Step #{step} timed out")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

# Cleanup telemetry handlers
:telemetry.detach("pipeline-example")
:telemetry.detach("pipeline-example-start")

IO.puts("\n=== Example Complete ===")
