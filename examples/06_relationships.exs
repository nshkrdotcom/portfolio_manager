# Example 06: Repository Relationships
#
# This example demonstrates:
# - Creating relationships between repos
# - Querying relationships
# - Understanding relationship types
#
# Run with: mix run examples/06_relationships.exs

IO.puts("""
================================================================================
Example 06: Repository Relationships
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Get repos
repos = PortfolioManager.list_repos(portfolio)

if length(repos) < 2 do
  IO.puts("Note: Need at least 2 repositories for full relationship examples.")
  IO.puts("Currently have: #{length(repos)}")
  IO.puts("")
  IO.puts("To demonstrate relationships fully, scan a directory with multiple repos,")
  IO.puts("or add repos manually with: PortfolioManager.add(portfolio, path)")
  IO.puts("")

  if length(repos) == 1 do
    repo = hd(repos)
    IO.puts("Showing relationships for: #{repo.id}")
    relationships = PortfolioManager.get_relationships(portfolio, repo.id)
    IO.puts("  Relationships: #{length(relationships)}")
  end

  IO.puts("""

  ================================================================================
  Example 06 Complete! (limited - need more repos)
  ================================================================================
  """)

  System.halt(0)
end

# Explain relationship types
IO.puts("""
Relationship Types:
  :depends_on   - A depends on B (library dependency)
  :port_of      - A is a port/translation of B
  :fork_of      - A is a fork of B
  :evolved_from - A evolved/grew from B
  :related_to   - General relationship
""")

# Get first two repos
[repo_a, repo_b | rest] = repos

IO.puts("Working with repositories:")
IO.puts("  A: #{repo_a.id}")
IO.puts("  B: #{repo_b.id}")

# Create a depends_on relationship
IO.puts("\n--- Creating Relationships ---")

IO.puts("\n1. #{repo_a.id} depends_on #{repo_b.id}")

case PortfolioManager.add_relationship(portfolio, repo_a.id, repo_b.id, :depends_on) do
  {:ok, rel} ->
    IO.puts("   ✓ Created: #{rel.from} -> #{rel.to} (#{rel.type})")

  {:error, reason} ->
    IO.puts("   ✗ Error: #{inspect(reason)}")
end

# Create a related_to relationship
IO.puts("\n2. #{repo_a.id} related_to #{repo_b.id}")

case PortfolioManager.add_relationship(portfolio, repo_a.id, repo_b.id, :related_to) do
  {:ok, rel} ->
    IO.puts("   ✓ Created: #{rel.from} -> #{rel.to} (#{rel.type})")

  {:error, reason} ->
    IO.puts("   ✗ Error: #{inspect(reason)}")
end

# If we have a third repo, create more relationships
if length(rest) > 0 do
  repo_c = hd(rest)
  IO.puts("\n3. #{repo_b.id} evolved_from #{repo_c.id}")

  case PortfolioManager.add_relationship(portfolio, repo_b.id, repo_c.id, :evolved_from) do
    {:ok, rel} ->
      IO.puts("   ✓ Created: #{rel.from} -> #{rel.to} (#{rel.type})")

    {:error, reason} ->
      IO.puts("   ✗ Error: #{inspect(reason)}")
  end
end

# Query relationships for repo_a
IO.puts("\n--- Relationships for #{repo_a.id} ---")
relationships = PortfolioManager.get_relationships(portfolio, repo_a.id)

if length(relationships) == 0 do
  IO.puts("  No relationships found")
else
  IO.puts("  Found #{length(relationships)} relationship(s):")

  Enum.each(relationships, fn rel ->
    direction = if rel.from == repo_a.id, do: "->", else: "<-"
    other = if rel.from == repo_a.id, do: rel.to, else: rel.from
    IO.puts("    #{direction} #{other} (#{rel.type})")
  end)
end

# Query relationships for repo_b
IO.puts("\n--- Relationships for #{repo_b.id} ---")
relationships_b = PortfolioManager.get_relationships(portfolio, repo_b.id)

if length(relationships_b) == 0 do
  IO.puts("  No relationships found")
else
  IO.puts("  Found #{length(relationships_b)} relationship(s):")

  Enum.each(relationships_b, fn rel ->
    direction = if rel.from == repo_b.id, do: "->", else: "<-"
    other = if rel.from == repo_b.id, do: rel.to, else: rel.from
    IO.puts("    #{direction} #{other} (#{rel.type})")
  end)
end

# Save changes
IO.puts("\nSaving portfolio...")
:ok = PortfolioManager.sync(portfolio)
IO.puts("  ✓ Changes saved")

IO.puts("""

================================================================================
Example 06 Complete!
================================================================================
Demonstrated creating and querying repository relationships.
""")
