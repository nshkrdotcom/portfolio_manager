# Example 11: Full Workflow
#
# This example demonstrates a complete workflow:
# - Initialize portfolio
# - Scan and discover repos
# - Enrich with context
# - Create relationships
# - Search and query
#
# Run with: mix run examples/11_full_workflow.exs

IO.puts("""
================================================================================
Example 11: Full Workflow
================================================================================

This example demonstrates a complete portfolio management workflow.
""")

# Configuration
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples_full")
scan_dirs = [".", "~/projects"]
has_api_key = System.get_env("GOOGLE_API_KEY") != nil

IO.puts("Configuration:")
IO.puts("  Portfolio: #{portfolio_path}")
IO.puts("  Scan dirs: #{inspect(scan_dirs)}")
IO.puts("  API key:   #{if has_api_key, do: "✓ set", else: "✗ not set"}")
IO.puts("")

# ============================================================================
# Step 1: Initialize
# ============================================================================
IO.puts("=" |> String.duplicate(60))
IO.puts("Step 1: Initialize Portfolio")
IO.puts("=" |> String.duplicate(60))

# Clean up
if File.exists?(portfolio_path) do
  IO.puts("  Removing existing portfolio...")
  File.rm_rf!(portfolio_path)
end

IO.puts("  Creating portfolio...")
{:ok, portfolio} = PortfolioManager.init(portfolio_path)
IO.puts("  ✓ Portfolio initialized at #{portfolio_path}")

# ============================================================================
# Step 2: Scan for Repositories
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Step 2: Scan for Repositories")
IO.puts("=" |> String.duplicate(60))

existing_dirs =
  Enum.filter(scan_dirs, fn dir ->
    expanded = Path.expand(dir)
    File.exists?(expanded) && File.dir?(expanded)
  end)

IO.puts("  Scanning: #{inspect(existing_dirs)}")

{:ok, discovered} = PortfolioManager.scan(portfolio, existing_dirs)
IO.puts("  ✓ Discovered #{length(discovered)} repositories")

if length(discovered) > 0 do
  IO.puts("\n  Sample repos:")

  discovered
  |> Enum.take(5)
  |> Enum.each(fn repo ->
    IO.puts("    - #{repo.id} (#{repo.language || "?"}/#{repo.type})")
  end)
end

# ============================================================================
# Step 3: Enrich Context
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Step 3: Enrich Repository Context")
IO.puts("=" |> String.duplicate(60))

if length(discovered) > 0 do
  repo = hd(discovered)
  IO.puts("  Enriching: #{repo.id}")

  # Update metadata
  PortfolioManager.update_context(portfolio, repo.id, %{
    purpose: "Primary project for Portfolio Manager examples",
    tags: ["example", "primary", "elixir"]
  })

  IO.puts("    ✓ Updated metadata")

  # Add notes
  PortfolioManager.add_note(portfolio, repo.id, """
  This repository was used in the Portfolio Manager full workflow example.
  Scanned on #{Date.utc_today()}.
  """)

  IO.puts("    ✓ Added notes")

  # Add decision
  PortfolioManager.add_decision(
    portfolio,
    repo.id,
    "Use for examples",
    "Selected as primary example repository for demonstrations."
  )

  IO.puts("    ✓ Added decision")
else
  IO.puts("  (No repos to enrich)")
end

# ============================================================================
# Step 4: Create Relationships
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Step 4: Create Relationships")
IO.puts("=" |> String.duplicate(60))

if length(discovered) >= 2 do
  [repo_a, repo_b | _] = discovered

  {:ok, _} =
    PortfolioManager.add_relationship(
      portfolio,
      repo_a.id,
      repo_b.id,
      :related_to
    )

  IO.puts("  ✓ Created relationship: #{repo_a.id} -> #{repo_b.id}")

  rels = PortfolioManager.get_relationships(portfolio, repo_a.id)
  IO.puts("  #{repo_a.id} has #{length(rels)} relationship(s)")
else
  IO.puts("  (Need 2+ repos for relationships)")
end

# ============================================================================
# Step 5: Search and Query
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Step 5: Search and Query")
IO.puts("=" |> String.duplicate(60))

# Text search
IO.puts("\n  Text search for 'elixir':")
text_results = PortfolioManager.search(portfolio, "elixir")
IO.puts("    Found #{length(text_results)} results")

# Semantic search (if API key available)
if has_api_key do
  IO.puts("\n  Semantic search for 'project management':")

  try do
    semantic_results =
      PortfolioManager.semantic_search(
        portfolio,
        "project management",
        limit: 3
      )

    IO.puts("    Found #{length(semantic_results)} results")
  rescue
    e -> IO.puts("    Error: #{Exception.message(e)}")
  end

  # Agentic query
  IO.puts("\n  Agentic query: 'What types of projects do I have?'")

  try do
    case PortfolioManager.query(portfolio, "What types of projects do I have?") do
      {:ok, result} ->
        answer = String.slice(result.answer, 0, 200)
        IO.puts("    Answer: #{answer}...")
        IO.puts("    Tools used: #{Enum.join(result.tools_used, ", ")}")

      {:error, reason} ->
        IO.puts("    Error: #{inspect(reason)}")
    end
  rescue
    e -> IO.puts("    Error: #{Exception.message(e)}")
  end
else
  IO.puts("\n  (Skipping semantic/agentic features - no API key)")
end

# ============================================================================
# Step 6: Save and Status
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Step 6: Save and Status")
IO.puts("=" |> String.duplicate(60))

# Get status
status = PortfolioManager.status(portfolio)
IO.puts("\n  Portfolio Status:")
IO.puts("    Total repos: #{status.total}")

if map_size(status.by_language || %{}) > 0 do
  IO.puts("    By language:")

  Enum.each(status.by_language, fn {lang, count} ->
    IO.puts("      #{lang}: #{count}")
  end)
end

if map_size(status.by_type || %{}) > 0 do
  IO.puts("    By type:")

  Enum.each(status.by_type, fn {type, count} ->
    IO.puts("      #{type}: #{count}")
  end)
end

# Save
:ok = PortfolioManager.sync(portfolio)
IO.puts("\n  ✓ Portfolio saved")

IO.puts("""

================================================================================
Example 11: Full Workflow Complete!
================================================================================

Summary:
  ✓ Initialized portfolio at #{portfolio_path}
  ✓ Discovered #{length(discovered)} repositories
  ✓ Enriched with context, notes, and decisions
  ✓ Created relationships between repos
  ✓ Searched using text#{if has_api_key, do: ", semantic, and agentic queries", else: ""}
  ✓ Saved portfolio state

Your portfolio is ready to use!
""")
