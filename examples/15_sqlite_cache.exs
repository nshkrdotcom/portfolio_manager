# Example 15: SQLite Cache (Optional)
#
# This example demonstrates:
# - Checking if SQLite caching is available
# - Starting the cache
# - Syncing repos to cache
# - Fast indexed queries
# - Cache statistics
#
# Note: Requires optional `exqlite` dependency to be installed.
#
# Run with: mix run examples/15_sqlite_cache.exs

alias PortfolioManager.Cache.SQLite

IO.puts("""
================================================================================
Example 15: SQLite Cache (Optional Performance Enhancement)
================================================================================
""")

# Check if SQLite is available
IO.puts("--- SQLite Availability ---")
available = SQLite.available?()
IO.puts("  SQLite caching available: #{available}")

if not available do
  IO.puts("""

  SQLite caching requires the optional 'exqlite' dependency.
  Add to mix.exs:

    {:exqlite, "~> 0.23"}

  Then run: mix deps.get
  """)
end

IO.puts("")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_PATH") || "/tmp/portfolio_manager_examples"

case PortfolioManager.init(portfolio_path) do
  {:ok, portfolio} ->
    repos = PortfolioManager.list_repos(portfolio)
    IO.puts("Portfolio has #{length(repos)} repositories\n")

    if available do
      # --- Start the cache ---
      IO.puts("--- Starting SQLite Cache ---")

      case SQLite.start_link(portfolio_path: portfolio_path) do
        {:ok, cache} ->
          IO.puts("  Cache started successfully")
          IO.puts("")

          # --- Sync repos to cache ---
          IO.puts("--- Syncing Repos to Cache ---")

          case SQLite.sync(cache, repos) do
            :ok ->
              IO.puts("  Synced #{length(repos)} repos to cache")

            {:error, reason} ->
              IO.puts("  Sync failed: #{inspect(reason)}")
          end

          IO.puts("")

          # --- Sync relationships ---
          IO.puts("--- Syncing Relationships ---")

          all_relationships =
            repos
            |> Enum.flat_map(fn repo ->
              PortfolioManager.get_relationships(portfolio, repo.id)
            end)

          case SQLite.sync_relationships(cache, all_relationships) do
            :ok ->
              IO.puts("  Synced #{length(all_relationships)} relationships")

            {:error, reason} ->
              IO.puts("  Sync failed: #{inspect(reason)}")
          end

          IO.puts("")

          # --- Cache statistics ---
          IO.puts("--- Cache Statistics ---")

          case SQLite.stats(cache) do
            {:ok, stats} ->
              IO.puts("  Cached repos:         #{stats.repos}")
              IO.puts("  Cached relationships: #{stats.relationships}")

            {:error, reason} ->
              IO.puts("  Stats failed: #{inspect(reason)}")
          end

          IO.puts("")

          # --- Search via cache ---
          IO.puts("--- Search via Cache ---")

          if length(repos) > 0 do
            # Get first repo name for search
            first_repo = List.first(repos)
            search_term = String.slice(first_repo.id, 0, 4)

            IO.puts("  Searching for '#{search_term}'...")

            case SQLite.search(cache, search_term) do
              {:ok, results} ->
                IO.puts("  Found #{length(results)} result(s):")

                Enum.each(results, fn repo ->
                  IO.puts("    - #{repo.id} (#{repo.type}, #{repo.language})")
                end)

              {:error, reason} ->
                IO.puts("  Search failed: #{inspect(reason)}")
            end
          end

          IO.puts("")

          # --- Filter via cache ---
          IO.puts("--- Filter via Cache ---")

          # Filter by status
          IO.puts("  Filtering by status: :active")

          case SQLite.filter(cache, status: :active, limit: 10) do
            {:ok, results} ->
              IO.puts("  Found #{length(results)} active repos")

            {:error, reason} ->
              IO.puts("  Filter failed: #{inspect(reason)}")
          end

          # Filter by language (if we have Elixir repos)
          IO.puts("  Filtering by language: elixir")

          case SQLite.filter(cache, language: "elixir", limit: 10) do
            {:ok, results} ->
              IO.puts("  Found #{length(results)} Elixir repos")

              Enum.each(results, fn repo ->
                IO.puts("    - #{repo.id}")
              end)

            {:error, reason} ->
              IO.puts("  Filter failed: #{inspect(reason)}")
          end

          IO.puts("")

          # --- Get single repo ---
          IO.puts("--- Get Single Repo from Cache ---")

          if length(repos) > 0 do
            repo_id = List.first(repos).id

            case SQLite.get(cache, repo_id) do
              {:ok, cached_repo} ->
                IO.puts("  Retrieved: #{cached_repo.id}")
                IO.puts("    Type:     #{cached_repo.type}")
                IO.puts("    Language: #{cached_repo.language}")
                IO.puts("    Status:   #{cached_repo.status}")

              {:error, :not_found} ->
                IO.puts("  Repo not found in cache")

              {:error, reason} ->
                IO.puts("  Get failed: #{inspect(reason)}")
            end
          end

          IO.puts("")

          # --- Clear cache ---
          IO.puts("--- Clear Cache ---")
          :ok = SQLite.clear(cache)
          IO.puts("  Cache cleared")

          {:ok, stats_after} = SQLite.stats(cache)
          IO.puts("  Repos after clear: #{stats_after.repos}")

        {:error, reason} ->
          IO.puts("  Failed to start cache: #{inspect(reason)}")
      end
    else
      IO.puts("--- Demo Mode (No SQLite) ---")
      IO.puts("  The cache module gracefully handles missing exqlite.")
      IO.puts("  All cache operations return {:error, :not_available}")
      IO.puts("")

      case SQLite.start_link(portfolio_path: portfolio_path) do
        {:error, :not_available} ->
          IO.puts("  start_link returned: {:error, :not_available}")
          IO.puts("  This is expected behavior when exqlite is not installed.")

        other ->
          IO.puts("  Unexpected result: #{inspect(other)}")
      end
    end

  {:error, reason} ->
    IO.puts("Failed to initialize portfolio: #{inspect(reason)}")
    IO.puts("Run example 01 first to set up the portfolio.")
end

IO.puts("""

================================================================================
Example 15 Complete!
================================================================================
Demonstrated SQLite cache operations:
- Checking availability
- Starting cache
- Syncing repos and relationships
- Fast indexed queries (search, filter, get)
- Cache statistics and clearing

The cache is optional - Portfolio Manager works without it.
Enable for large portfolios (100+ repos) for better query performance.
""")
