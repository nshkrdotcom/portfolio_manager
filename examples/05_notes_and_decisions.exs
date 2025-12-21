# Example 05: Notes and Architectural Decisions
#
# This example demonstrates:
# - Adding notes to a repository
# - Recording architectural decisions
# - Building up project context over time
#
# Run with: mix run examples/05_notes_and_decisions.exs

IO.puts("""
================================================================================
Example 05: Notes and Architectural Decisions
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Get a repo to add notes to
repos = PortfolioManager.list_repos(portfolio)

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

repo = hd(repos)
IO.puts("Adding notes to: #{repo.id}")

# Add a note
IO.puts("\n--- Adding Note ---")

note_content = """
Reviewed this repository on #{Date.utc_today()}.

Key observations:
- Well-structured codebase
- Good test coverage
- Documentation could be improved

Next steps:
- Add more inline documentation
- Consider extracting shared utilities
"""

case PortfolioManager.add_note(portfolio, repo.id, note_content) do
  {:ok, ctx} ->
    IO.puts("  ✓ Note added")
    IO.puts("  Notes length: #{String.length(ctx.notes || "")} chars")

  {:error, reason} ->
    IO.puts("  ✗ Error: #{inspect(reason)}")
end

# Add architectural decisions
IO.puts("\n--- Adding Architectural Decisions ---")

decisions = [
  {
    "Use GenServer for state management",
    "Use GenServer for managing portfolio state. OTP supervision provides fault tolerance, state is naturally encapsulated, and it is easy to add caching and persistence."
  },
  {
    "YAML for storage format",
    "Use YAML files for data storage. YAML is human-readable, version-controllable, and works well with git. No database setup required."
  },
  {
    "Hexagonal architecture",
    "Adopt hexagonal (ports and adapters) architecture. Ports define behaviors (Storage, Git, Detection), adapters implement them (YAMLStorage, LocalGit). Enables clean separation and easy testing."
  }
]

Enum.each(decisions, fn {title, content} ->
  IO.puts("\n  Decision: #{title}")

  case PortfolioManager.add_decision(portfolio, repo.id, title, content) do
    {:ok, ctx} ->
      IO.puts("    ✓ Added (total decisions: #{length(ctx.decisions || [])})")

    {:error, reason} ->
      IO.puts("    ✗ Error: #{inspect(reason)}")
  end
end)

# Show final state
IO.puts("\n--- Repository Context Summary ---")

case PortfolioManager.get_context(portfolio, repo.id) do
  {:ok, ctx} ->
    IO.puts("  Notes: #{String.length(ctx.notes || "")} characters")
    IO.puts("  Decisions: #{length(ctx.decisions || [])}")

    if length(ctx.decisions || []) > 0 do
      IO.puts("\n  Decision titles:")

      Enum.each(ctx.decisions, fn d ->
        IO.puts("    - #{d.title}")
      end)
    end

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Save changes
IO.puts("\nSaving portfolio...")
:ok = PortfolioManager.sync(portfolio)
IO.puts("  ✓ Changes saved")

IO.puts("""

================================================================================
Example 05 Complete!
================================================================================
Demonstrated adding notes and architectural decisions.
""")
