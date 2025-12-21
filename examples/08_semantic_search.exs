# Example 08: Semantic Search
#
# This example demonstrates:
# - Vector-based semantic search
# - Finding conceptually similar repos
# - Understanding similarity scores
#
# REQUIRES: GOOGLE_API_KEY environment variable
#
# Run with: mix run examples/08_semantic_search.exs

IO.puts("""
================================================================================
Example 08: Semantic Search
================================================================================
""")

# Check for API key
unless System.get_env("GOOGLE_API_KEY") do
  IO.puts("""
  ⚠️  GOOGLE_API_KEY not set!

  Semantic search requires a Gemini API key for embeddings.
  Set it with: export GOOGLE_API_KEY="your-api-key"

  Skipping semantic search examples.
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
IO.puts("Portfolio has #{length(repos)} repositories")

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

# Helper to display semantic search results
display_results = fn query, results ->
  IO.puts("\n--- Semantic Search: \"#{query}\" ---")

  if length(results) == 0 do
    IO.puts("  No results (try lowering min_score or adding more context to repos)")
  else
    IO.puts("  Found #{length(results)} result(s)")

    Enum.each(results, fn result ->
      score_pct = Float.round(result.score * 100, 1)
      IO.puts("    #{result.repo_id} (#{score_pct}% match)")
      IO.puts("      Type: #{result.type}, Language: #{result.language}")

      if result.snippet do
        snippet = String.slice(result.snippet, 0, 80)
        IO.puts("      \"#{snippet}...\"")
      end
    end)
  end
end

# Semantic search queries
queries = [
  "error handling and fault tolerance",
  "API client library",
  "web application framework",
  "data processing pipeline",
  "testing utilities"
]

IO.puts("\nRunning semantic searches...")
IO.puts("(This calls the Gemini API to generate embeddings)")

Enum.each(queries, fn query ->
  IO.puts("\nSearching: #{query}")

  try do
    results =
      PortfolioManager.semantic_search(portfolio, query,
        limit: 5,
        # Lower threshold for demo
        min_score: 0.3
      )

    display_results.(query, results)
  rescue
    e ->
      IO.puts("  Error: #{inspect(e)}")
  end
end)

IO.puts("""

How Semantic Search Works:
  1. Your query is converted to a vector embedding
  2. Each repo's content is also embedded
  3. Cosine similarity finds the closest matches
  4. Results are ranked by similarity score (0.0 - 1.0)

Tips for better results:
  - Add notes and decisions to repos (examples 04, 05)
  - Use descriptive tags
  - Set purpose fields

================================================================================
Example 08 Complete!
================================================================================
""")
