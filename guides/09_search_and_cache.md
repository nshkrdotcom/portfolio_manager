# Search and Cache

Portfolio Manager supports text search, semantic search, and optional SQLite
caching for large portfolios.

## Text search

Use the CLI:

```bash
mix portfolio.search authentication
mix portfolio.search "data pipeline" --field=notes
mix portfolio.search "^auth" --regex
```

Or the API:

```elixir
results = PortfolioManager.search(portfolio, "authentication")
```

Search defaults to repo id, name, purpose, and tags. Use `--field` to scope it.

## Semantic search

Semantic search embeds content and ranks by similarity:

```elixir
results = PortfolioManager.semantic_search(portfolio, "error handling patterns",
  limit: 5,
  min_score: 0.6
)
```

This requires your RAG provider to be configured (for example, `GOOGLE_API_KEY`).

## Agentic queries

For richer tool-based reasoning:

```elixir
{:ok, result} = PortfolioManager.query(portfolio, "Which repos are stale?")
IO.puts(result.answer)
```

## SQLite cache (optional)

Enable `exqlite` to use the cache. The index lives in:

```
.portfolio/cache/index.db
```

Build or refresh the index:

```elixir
:ok = PortfolioManager.Cache.SQLite.build_index(portfolio)
```

Start a cache process:

```elixir
{:ok, cache} = PortfolioManager.Cache.SQLite.start_link(portfolio_path: "~/portfolio")
{:ok, results} = PortfolioManager.Cache.SQLite.search(cache, "authentication")
{:ok, filtered} = PortfolioManager.Cache.SQLite.filter(cache, language: "elixir")
```

If the index exists, Portfolio Manager will refresh it during sync operations.
