# Example 09: Agentic Queries
#
# This example demonstrates:
# - Asking natural language questions about your portfolio
# - Agent using tools to find answers
# - Understanding tool usage in responses
#
# REQUIRES: GOOGLE_API_KEY environment variable
#
# Run with: mix run examples/09_agentic_query.exs

IO.puts("""
================================================================================
Example 09: Agentic Queries
================================================================================
""")

# Check for API key
unless System.get_env("GOOGLE_API_KEY") do
  IO.puts("""
  ⚠️  GOOGLE_API_KEY not set!

  Agentic queries require a Gemini API key.
  Set it with: export GOOGLE_API_KEY="your-api-key"

  Skipping agentic query examples.
  """)

  System.halt(0)
end

IO.puts("✓ GOOGLE_API_KEY detected")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Check we have repos
repos = PortfolioManager.list_repos(portfolio)
IO.puts("Portfolio has #{length(repos)} repositories\n")

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

IO.puts("""
Available Tools for the Agent:
  - search_repos: Search repositories by query
  - get_repo_context: Get detailed info about a repo
  - list_repos: List repos with filters
  - find_relationships: Find repo connections
  - compare_repos: Compare two repositories
  - get_portfolio_stats: Get overall statistics
""")

# Helper to run a query
run_query = fn question ->
  IO.puts("\n" <> String.duplicate("─", 60))
  IO.puts("Question: #{question}")
  IO.puts(String.duplicate("─", 60))

  try do
    case PortfolioManager.query(portfolio, question) do
      {:ok, result} ->
        IO.puts("\nAnswer:")
        IO.puts(result.answer)

        if length(result.tools_used) > 0 do
          IO.puts("\nTools used: #{Enum.join(result.tools_used, ", ")}")
        end

      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
    end
  rescue
    e ->
      IO.puts("\nException: #{Exception.message(e)}")
  end
end

# Run example queries
queries = [
  "How many repositories do I have and what languages are most common?",
  "List all my Elixir projects",
  "What types of projects are in my portfolio?"
]

IO.puts("\nRunning agentic queries...")
IO.puts("(The agent will use tools to answer these questions)\n")

Enum.each(queries, fn q ->
  run_query.(q)
  # Small delay between queries
  Process.sleep(1000)
end)

# If we have specific repos, ask about them
if length(repos) > 0 do
  repo = hd(repos)
  run_query.("Tell me about the #{repo.id} repository")
end

if length(repos) > 1 do
  [repo_a, repo_b | _] = repos
  run_query.("How are #{repo_a.id} and #{repo_b.id} related?")
end

IO.puts("""


How Agentic Queries Work:
  1. Your question is sent to the LLM with available tools
  2. The agent decides which tools to use
  3. Tool results are fed back to the LLM
  4. The agent synthesizes a final answer

The agent can chain multiple tool calls to answer complex questions.

================================================================================
Example 09 Complete!
================================================================================
""")
