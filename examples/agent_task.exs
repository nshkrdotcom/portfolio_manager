# Agent Task Example
#
# This example demonstrates the tool-using agent framework.
#
# Run with: mix run examples/agent_task.exs

IO.puts("=== Agent Task Example ===\n")

# List available tools
tools = PortfolioManager.Agent.available_tools()
IO.puts("Available tools: #{inspect(tools)}")
IO.puts("")

# Simple task with file listing
IO.puts("--- Task 1: List files in current directory ---\n")

task1 = "List all Elixir files in the lib directory"

IO.puts("Task: #{task1}")
IO.puts("Running agent...")
IO.puts("")

case PortfolioManager.Agent.run(task1, tools: [:list_files], max_iterations: 3) do
  {:ok, result} ->
    IO.puts("Result:\n#{result}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# Code analysis task
IO.puts("--- Task 2: Analyze code structure ---\n")

task2 = """
Analyze the PortfolioManager.RAG module:
1. Find its location
2. List its public functions
3. Summarize its purpose
"""

IO.puts("Task: #{String.trim(task2)}")
IO.puts("Running agent...")
IO.puts("")

case PortfolioManager.Agent.run(task2,
       tools: [:search_code, :read_file, :list_files],
       max_iterations: 5
     ) do
  {:ok, result} ->
    IO.puts("Result:\n#{result}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# Graph context task
IO.puts("--- Task 3: Get graph context ---\n")

task3 = "Find entities related to 'PortfolioManager' in the knowledge graph"

IO.puts("Task: #{task3}")
IO.puts("Running agent...")
IO.puts("")

case PortfolioManager.Agent.run(task3,
       tools: [:get_graph_context],
       max_iterations: 2
     ) do
  {:ok, result} ->
    IO.puts("Result:\n#{result}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n=== Example Complete ===")
