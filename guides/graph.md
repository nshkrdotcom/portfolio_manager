# Graph Operations

Portfolio Manager provides graph capabilities for dependency analysis and
knowledge representation through the `PortfolioManager.Graph` module.

## Overview

The graph module supports:
- Creating and managing graphs
- Adding nodes and edges
- Querying graph structure
- Building dependency graphs from repositories
- Running Cypher queries (when using Neo4j)

## Creating Graphs

```elixir
# Create a basic graph
:ok = PortfolioManager.Graph.create_graph("my_graph")

# Create with configuration
:ok = PortfolioManager.Graph.create_graph("deps", %{type: :dependency})
```

## Adding Nodes

```elixir
{:ok, node} = PortfolioManager.Graph.add_node("my_graph", %{
  id: "user_module",
  labels: ["Module", "Elixir"],
  properties: %{
    path: "lib/my_app/user.ex",
    functions: 12
  }
})
```

## Adding Edges

```elixir
{:ok, edge} = PortfolioManager.Graph.add_edge("my_graph", %{
  from: "user_module",
  to: "repo_module",
  type: "CALLS",
  properties: %{count: 5}
})
```

## Querying

### Get Neighbors

```elixir
{:ok, neighbors} = PortfolioManager.Graph.neighbors("my_graph", "user_module")
```

### Graph Statistics

```elixir
{:ok, stats} = PortfolioManager.Graph.stats("my_graph")
# => %{node_count: 42, edge_count: 128}
```

### Raw Cypher Queries

When using Neo4j, you can run arbitrary Cypher:

```elixir
{:ok, result} = PortfolioManager.Graph.query("my_graph",
  "MATCH (n)-[r]->(m) WHERE n.id = $id RETURN m",
  %{id: "user_module"}
)
```

## Building Dependency Graphs

Automatically build a dependency graph from a repository:

```elixir
{:ok, stats} = PortfolioManager.Graph.build_dependency_graph(
  "my_deps",
  "/path/to/repo",
  language: :elixir
)
```

Supported languages:
- `:elixir` - Parses `mix.exs` dependencies
- `:python` - Parses `requirements.txt`

## CLI Usage

### View Graph Stats

```bash
mix portfolio.graph stats --graph my_graph
```

### Build Dependency Graph

```bash
# Elixir project
mix portfolio.graph build /path/to/repo --graph deps --language elixir

# Python project
mix portfolio.graph build /path/to/repo --graph deps --language python
```

## API Reference

### `create_graph/2`

```elixir
@spec create_graph(String.t(), map()) :: :ok | {:error, term()}
```

### `add_node/2`

```elixir
@spec add_node(String.t(), map()) :: {:ok, map()} | {:error, term()}

# Node map should include:
# - :id - Unique node identifier
# - :labels - List of labels (optional)
# - :properties - Node properties (optional)
```

### `add_edge/2`

```elixir
@spec add_edge(String.t(), map()) :: {:ok, map()} | {:error, term()}

# Edge map should include:
# - :from - Source node ID
# - :to - Target node ID
# - :type - Relationship type
# - :properties - Edge properties (optional)
```

### `neighbors/3`

```elixir
@spec neighbors(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

### `query/3`

```elixir
@spec query(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

### `stats/1`

```elixir
@spec stats(String.t()) :: {:ok, map()} | {:error, term()}
```

### `build_dependency_graph/3`

```elixir
@spec build_dependency_graph(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}

# Options:
# - :language - :elixir or :python (default: :elixir)
```

## Graph Store Configuration

Configure the graph store adapter in your manifest:

```yaml
adapters:
  graph_store:
    adapter: PortfolioIndex.Adapters.GraphStore.Neo4j
    config:
      uri: ${NEO4J_URI:-bolt://localhost:7687}
      username: ${NEO4J_USER:-neo4j}
      password: ${NEO4J_PASSWORD:-password}
      pool_size: 5
```

See [Configuration](configuration.md) for more adapter options.
