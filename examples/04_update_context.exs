# Example 04: Updating Repository Context
#
# This example demonstrates:
# - Updating repo metadata (type, purpose, tags)
# - Setting port information for ported repos
# - Modifying repo status
#
# Run with: mix run examples/04_update_context.exs

IO.puts("""
================================================================================
Example 04: Updating Repository Context
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Get a repo to update
repos = PortfolioManager.list_repos(portfolio)

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

repo = hd(repos)
IO.puts("Updating repository: #{repo.id}")

# Show current state
IO.puts("\n--- Before Update ---")

case PortfolioManager.get_context(portfolio, repo.id) do
  {:ok, before_ctx} ->
    IO.puts("  Type:    #{before_ctx.repo.type}")
    IO.puts("  Status:  #{before_ctx.repo.status}")
    IO.puts("  Tags:    #{inspect(before_ctx.repo.tags || [])}")

  {:error, :not_found} ->
    IO.puts("  (No context yet - will be created)")
    IO.puts("  Type:    #{repo.type}")
    IO.puts("  Status:  #{repo.status}")
    IO.puts("  Tags:    #{inspect(repo.tags || [])}")
end

# Update the context
IO.puts("\n--- Updating Context ---")

updates = %{
  type: :library,
  purpose: "Example repository for demonstrating Portfolio Manager",
  tags: ["example", "demo", "portfolio-manager"]
}

IO.puts("  Applying updates: #{inspect(updates)}")

case PortfolioManager.update_context(portfolio, repo.id, updates) do
  {:ok, updated_ctx} ->
    IO.puts("  ✓ Context updated successfully")

    IO.puts("\n--- After Update ---")
    IO.puts("  Type:    #{updated_ctx.repo.type}")
    IO.puts("  Purpose: #{Map.get(updated_ctx, :purpose, "not set")}")
    IO.puts("  Tags:    #{inspect(updated_ctx.repo.tags || [])}")

  {:error, reason} ->
    IO.puts("  ✗ Error: #{inspect(reason)}")
end

# Example: Mark a repo as a port (if we have multiple repos)
if length(repos) > 1 do
  port_repo = Enum.at(repos, 1)
  IO.puts("\n--- Setting Port Information ---")
  IO.puts("Repository: #{port_repo.id}")

  port_updates = %{
    type: :port,
    port: %{
      upstream_url: "https://github.com/example/upstream",
      upstream_language: "python",
      coverage: "partial"
    }
  }

  case PortfolioManager.update_context(portfolio, port_repo.id, port_updates) do
    {:ok, ctx} ->
      IO.puts("  ✓ Port information set")
      IO.puts("  Type: #{ctx.repo.type}")

      if ctx.port do
        IO.puts("  Upstream: #{ctx.port[:upstream_url]}")
      end

    {:error, reason} ->
      IO.puts("  ✗ Error: #{inspect(reason)}")
  end
end

# Save changes
IO.puts("\nSaving portfolio...")
:ok = PortfolioManager.sync(portfolio)
IO.puts("  ✓ Changes saved")

IO.puts("""

================================================================================
Example 04 Complete!
================================================================================
Demonstrated updating repository context and metadata.
""")
