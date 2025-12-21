# Example 02: Listing and Filtering Repositories
#
# This example demonstrates:
# - Listing all repositories
# - Filtering by status, type, and language
# - Sorting results
#
# Run with: mix run examples/02_list_and_filter.exs

IO.puts("""
================================================================================
Example 02: Listing and Filtering Repositories
================================================================================
""")

# Initialize portfolio (reuse existing)
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

IO.puts("Loading portfolio from: #{portfolio_path}")
{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# List all repos
IO.puts("\n--- All Repositories ---")
all_repos = PortfolioManager.list_repos(portfolio)
IO.puts("Total: #{length(all_repos)}")

all_repos
|> Enum.take(5)
|> Enum.each(fn repo ->
  IO.puts("  #{repo.id}")
  IO.puts("    Type: #{repo.type}, Language: #{repo.language}, Status: #{repo.status}")
end)

if length(all_repos) > 5 do
  IO.puts("  ... and #{length(all_repos) - 5} more")
end

# Filter by status
IO.puts("\n--- Active Repositories ---")
active_repos = PortfolioManager.list_repos(portfolio, status: :active)
IO.puts("Active repos: #{length(active_repos)}")

active_repos
|> Enum.take(3)
|> Enum.each(fn repo ->
  IO.puts("  #{repo.id} (#{repo.language})")
end)

# Filter by language (if any Elixir repos)
IO.puts("\n--- Elixir Repositories ---")
elixir_repos = PortfolioManager.list_repos(portfolio, language: :elixir)
IO.puts("Elixir repos: #{length(elixir_repos)}")

elixir_repos
|> Enum.take(5)
|> Enum.each(fn repo ->
  IO.puts("  #{repo.id} - #{repo.type}")
end)

# Filter by type
IO.puts("\n--- Libraries ---")
libraries = PortfolioManager.list_repos(portfolio, type: :library)
IO.puts("Libraries: #{length(libraries)}")

libraries
|> Enum.take(5)
|> Enum.each(fn repo ->
  IO.puts("  #{repo.id}")
end)

# Combined filters
IO.puts("\n--- Active Elixir Libraries ---")

filtered =
  PortfolioManager.list_repos(portfolio,
    status: :active,
    type: :library,
    language: :elixir
  )

IO.puts("Matching repos: #{length(filtered)}")

Enum.each(filtered, fn repo ->
  IO.puts("  #{repo.id}")
end)

IO.puts("""

================================================================================
Example 02 Complete!
================================================================================
Demonstrated listing with various filters.
""")
