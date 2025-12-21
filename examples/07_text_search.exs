# Example 07: Text Search
#
# This example demonstrates:
# - Basic text search across repositories
# - Searching by different criteria
# - Understanding search results
#
# Run with: mix run examples/07_text_search.exs

IO.puts("""
================================================================================
Example 07: Text Search
================================================================================
""")

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

# Helper to display search results
display_results = fn query, results ->
  IO.puts("\n--- Search: \"#{query}\" ---")
  IO.puts("  Found #{length(results)} result(s)")

  results
  |> Enum.take(5)
  |> Enum.each(fn repo ->
    IO.puts("    #{repo.id}")
    IO.puts("      Type: #{repo.type}, Language: #{repo.language}")
  end)

  if length(results) > 5 do
    IO.puts("    ... and #{length(results) - 5} more")
  end
end

# Search for common terms
search_terms = [
  # Search by language
  "elixir",
  "python",
  "javascript",

  # Search by type keywords
  "library",
  "app",

  # Search by common project names
  "test",
  "api",
  "web"
]

IO.puts("\nRunning searches...")

Enum.each(search_terms, fn term ->
  results = PortfolioManager.search(portfolio, term)
  display_results.(term, results)
end)

# Search using repo names from our portfolio
IO.puts("\n--- Searching for actual repo names ---")

repos
|> Enum.take(3)
|> Enum.each(fn repo ->
  # Search for part of the repo name
  search_term = repo.name |> String.split(~r/[-_]/) |> hd()
  results = PortfolioManager.search(portfolio, search_term)
  display_results.(search_term, results)
end)

# Show what fields are searched
IO.puts("""

Note: Text search matches against:
  - Repository ID
  - Repository name
  - Purpose/description
  - Tags
""")

IO.puts("""

================================================================================
Example 07 Complete!
================================================================================
Demonstrated text-based repository search.
""")
