# Library API

This guide summarizes the core Elixir API and extension points.

## Entry points

Initialize a portfolio:

```elixir
{:ok, portfolio} = PortfolioManager.init("~/portfolio")
{:ok, portfolio} = PortfolioManager.init() # uses PORTFOLIO_DIR or config
```

Core operations:

```elixir
PortfolioManager.list_repos(portfolio)
PortfolioManager.get_repo(portfolio, "my-app")
PortfolioManager.get_context(portfolio, "my-app")
PortfolioManager.add(portfolio, "~/projects/my-app")
PortfolioManager.remove(portfolio, "my-app")
PortfolioManager.update_context(portfolio, "my-app", %{status: :active})
PortfolioManager.add_note(portfolio, "my-app", "Release checklist updated")
PortfolioManager.add_decision(portfolio, "my-app", "ADR title", "Decision text")
PortfolioManager.add_relationship(portfolio, "a", "b", :depends_on)
```

## Views and graph

```elixir
:ok = PortfolioManager.generate_views(portfolio)

graph = PortfolioManager.Graph.build(portfolio)
IO.puts(PortfolioManager.Graph.to_ascii(graph))
```

## Workflows

```elixir
{:ok, result} = PortfolioManager.Workflow.Engine.run("health-check",
  portfolio: portfolio,
  repo_id: "my-app"
)
```

## Search and RAG

```elixir
PortfolioManager.search(portfolio, "auth")
PortfolioManager.semantic_search(portfolio, "event streaming")
PortfolioManager.query(portfolio, "Which repos are stale?")
```

## SQLite cache

```elixir
:ok = PortfolioManager.Cache.SQLite.build_index(portfolio)
{:ok, cache} = PortfolioManager.Cache.SQLite.start_link(portfolio_path: "~/portfolio")
{:ok, results} = PortfolioManager.Cache.SQLite.search(cache, "auth")
```

## Domain types

The domain layer contains the core data structures:

- `PortfolioManager.Domain.Repo`
- `PortfolioManager.Domain.Context`
- `PortfolioManager.Domain.Relationship`
- `PortfolioManager.Domain.Registry`

These are useful for serialization and adapter implementations.

## Ports and adapters

Portfolio Manager uses ports for storage, detection, and git operations. You can
override adapters in your config:

```elixir
config :portfolio_manager,
  storage_adapter: MyApp.Storage,
  detection_adapter: MyApp.Detection,
  git_adapter: MyApp.Git
```

Adapters must implement the corresponding port behaviours in:

- `PortfolioManager.Ports.Storage`
- `PortfolioManager.Ports.Detection`
- `PortfolioManager.Ports.Git`

## RAG integration

The RAG layer lives under `PortfolioManager.Rag` and includes tool integrations
for searching, comparing, and summarizing repos. Use it when you need multi-step
reasoning or custom agent flows.
