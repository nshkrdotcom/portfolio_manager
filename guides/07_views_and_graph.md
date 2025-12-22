# Views and Graph

Portfolio Manager generates computed views for quick scanning and a relationship
graph for deeper analysis.

## Computed views

Views are written to `views/` in the portfolio repo:

- `by-status.yml`
- `by-type.yml`
- `by-language.yml`
- `stale-repos.yml`
- `port-status.yml`

Generate them via the API or CLI:

```elixir
:ok = PortfolioManager.generate_views(portfolio)
```

```bash
mix portfolio.sync --views
```

### Stale logic

The stale view uses a mix of status and activity:

- `status == stale` is always included.
- `status == active` with `commit_count_30d == 0` is included.
- If commit counts are missing, `last_commit` age is compared to the threshold.

### Port status fields

The port view includes:

- `upstream`
- `upstream_version`
- `synced_version`
- `commits_behind`
- `status` (up_to_date, needs_sync, or unknown)
- `affected_modules` (when present)

The summary includes total ports, counts by status, and total commits behind.

## Relationship graph

Build and render graphs with the API:

```elixir
graph = PortfolioManager.Graph.build(portfolio)
IO.puts(PortfolioManager.Graph.to_ascii(graph))
File.write!("portfolio.dot", PortfolioManager.Graph.to_dot(graph))
```

Or use the CLI:

```bash
mix portfolio.graph
mix portfolio.graph my-app --depth=3
mix portfolio.graph --type=depends_on -o deps.dot
mix portfolio.graph my-app --ascii
```

For SVG/PNG output, install Graphviz (`dot`) and pass `--output` with a
`.svg` or `.png` extension.
