# Example 01: Basic Portfolio Initialization
#
# This example demonstrates:
# - Initializing a new portfolio
# - Scanning directories for git repos
# - Basic portfolio status
#
# Run with: mix run examples/01_basic_init.exs

IO.puts("""
================================================================================
Example 01: Basic Portfolio Initialization
================================================================================
""")

# Configuration
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")
scan_dirs = ["~/projects", "~/work", "."]

IO.puts("Portfolio path: #{portfolio_path}")
IO.puts("Scan directories: #{inspect(scan_dirs)}")
IO.puts("")

# Clean up previous run (optional)
if File.exists?(portfolio_path) do
  IO.puts("Cleaning up previous portfolio...")
  File.rm_rf!(portfolio_path)
end

# Initialize portfolio
IO.puts("Initializing portfolio...")
{:ok, portfolio} = PortfolioManager.init(portfolio_path)
IO.puts("  ✓ Portfolio initialized")

# Scan for repositories
IO.puts("\nScanning for repositories...")

existing_dirs =
  Enum.filter(scan_dirs, fn dir ->
    expanded = Path.expand(dir)
    File.exists?(expanded) && File.dir?(expanded)
  end)

IO.puts("  Existing directories: #{inspect(existing_dirs)}")

case PortfolioManager.scan(portfolio, existing_dirs) do
  {:ok, discovered} ->
    IO.puts("  ✓ Found #{length(discovered)} repositories")

    if length(discovered) > 0 do
      IO.puts("\n  Discovered repos:")

      discovered
      |> Enum.take(10)
      |> Enum.each(fn repo ->
        IO.puts("    - #{repo.id} (#{repo.language || "unknown"})")
      end)

      if length(discovered) > 10 do
        IO.puts("    ... and #{length(discovered) - 10} more")
      end
    end

  {:error, reason} ->
    IO.puts("  ✗ Error scanning: #{inspect(reason)}")
end

# Get portfolio status
IO.puts("\nPortfolio status:")
status = PortfolioManager.status(portfolio)
IO.puts("  Total repos: #{status.total}")

if map_size(status.by_language || %{}) > 0 do
  IO.puts("  By language:")

  Enum.each(status.by_language, fn {lang, count} ->
    IO.puts("    #{lang}: #{count}")
  end)
end

if map_size(status.by_type || %{}) > 0 do
  IO.puts("  By type:")

  Enum.each(status.by_type, fn {type, count} ->
    IO.puts("    #{type}: #{count}")
  end)
end

# Save the portfolio
IO.puts("\nSaving portfolio...")
:ok = PortfolioManager.sync(portfolio)
IO.puts("  ✓ Portfolio saved to #{portfolio_path}")

IO.puts("""

================================================================================
Example 01 Complete!
================================================================================
Portfolio initialized with #{status.total} repositories.
Run the next example to explore listing and filtering.
""")
