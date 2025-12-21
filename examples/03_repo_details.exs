# Example 03: Getting Repository Details
#
# This example demonstrates:
# - Getting a specific repo by ID
# - Getting full context for a repo
# - Exploring repo metadata
#
# Run with: mix run examples/03_repo_details.exs

IO.puts("""
================================================================================
Example 03: Repository Details
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Get list of repos to pick one
repos = PortfolioManager.list_repos(portfolio)

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

# Pick the first repo
repo = hd(repos)
IO.puts("Examining repository: #{repo.id}")
IO.puts("")

# Get basic repo info
IO.puts("--- Basic Info ---")

case PortfolioManager.get_repo(portfolio, repo.id) do
  {:ok, r} ->
    IO.puts("  ID:       #{r.id}")
    IO.puts("  Name:     #{r.name}")
    IO.puts("  Path:     #{r.path}")
    IO.puts("  Type:     #{r.type}")
    IO.puts("  Language: #{r.language}")
    IO.puts("  Status:   #{r.status}")
    IO.puts("  Remote:   #{r.remote_url || "none"}")
    IO.puts("  Tags:     #{inspect(r.tags || [])}")

  {:error, :not_found} ->
    IO.puts("  Repository not found!")
end

# Get full context
IO.puts("\n--- Full Context ---")

case PortfolioManager.get_context(portfolio, repo.id) do
  {:ok, context} ->
    IO.puts("  Repo ID:    #{context.repo.id}")
    IO.puts("  Notes:      #{String.length(context.notes || "") |> then(&"#{&1} chars")}")
    IO.puts("  Decisions:  #{length(context.decisions || [])}")
    IO.puts("  Todos:      #{length(context.todos || [])}")
    IO.puts("  Updated:    #{context.repo.updated_at || "never"}")

    if context.repo.port do
      IO.puts("\n  Port Info:")
      IO.puts("    Upstream: #{context.repo.port[:upstream_url] || "unknown"}")
      IO.puts("    Language: #{context.repo.port[:upstream_language] || "unknown"}")
      IO.puts("    Coverage: #{context.repo.port[:coverage] || "unknown"}")
    end

    if context.notes && String.length(context.notes) > 0 do
      IO.puts("\n  Notes preview:")

      context.notes
      |> String.split("\n")
      |> Enum.take(3)
      |> Enum.each(fn line ->
        IO.puts("    #{line}")
      end)
    end

  {:error, :not_found} ->
    IO.puts("  Context not yet created for this repo.")
    IO.puts("  (Run example 04 or 05 to create context)")

  {:error, reason} ->
    IO.puts("  Error getting context: #{inspect(reason)}")
end

# Show a few more repos
if length(repos) > 1 do
  IO.puts("\n--- Other Repositories ---")

  repos
  |> Enum.drop(1)
  |> Enum.take(5)
  |> Enum.each(fn r ->
    IO.puts("  #{r.id}")
    IO.puts("    #{r.type} | #{r.language} | #{r.status}")
  end)
end

IO.puts("""

================================================================================
Example 03 Complete!
================================================================================
Demonstrated getting repo details and context.
""")
