# Portfolio Manager

<p align="center">
  <img src="assets/portfolio_manager.svg" alt="Portfolio Manager Logo" width="200">
</p>

<p align="center">
  <a href="https://hex.pm/packages/portfolio_manager"><img alt="Hex.pm" src="https://img.shields.io/hexpm/v/portfolio_manager.svg"></a>
  <a href="https://hexdocs.pm/portfolio_manager"><img alt="Documentation" src="https://img.shields.io/badge/docs-hexdocs-purple.svg"></a>
  <a href="https://github.com/nshkrdotcom/portfolio_manager/actions"><img alt="Build Status" src="https://img.shields.io/github/actions/workflow/status/nshkrdotcom/portfolio_manager/ci.yml"></a>
  <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/hexpm/l/portfolio_manager.svg"></a>
</p>

Portfolio Manager is the application layer on top of `portfolio_core` and `portfolio_index`. It provides CLI workflows, RAG query interfaces, graph tooling, and manifest-driven configuration for managing code portfolios.

## Quick Install (0.3.1)

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.3.1"}
  ]
end
```

Then:

```bash
mix deps.get
```

## Features

- Manifest-driven adapter wiring (vector store, graph store, embedder, LLM, chunker)
- RAG queries with multiple strategies (hybrid, self-rag, graph-rag, agentic)
- Graph utilities for dependency and knowledge graphs
- CLI tasks for ask/search/index/graph operations
- Runnable examples under `examples/`

### Multi-Provider Routing (v0.3.1)

Route LLM requests across multiple providers with intelligent strategies:

```elixir
# Automatic routing
{:ok, response} = PortfolioManager.Router.complete(messages)

# Force specific strategy
{:ok, response} = PortfolioManager.Router.complete(messages, strategy: :specialist)

# Route by task type
{:ok, response} = PortfolioManager.Router.complete(messages, task_type: :code)

# Stream responses
PortfolioManager.Router.stream(messages, &IO.write/1)
```

### Streaming Responses (v0.3.1)

Stream RAG query responses for better UX:

```elixir
PortfolioManager.RAG.stream_query("How does this work?", fn chunk ->
  IO.write(chunk)
end)

# CLI
mix portfolio.ask "Your question" --stream
```

### Agent Framework (v0.3.1)

Use tool-based agents for complex tasks:

```elixir
PortfolioManager.Agent.run("Analyze this codebase and suggest improvements",
  tools: [:search_code, :read_file, :get_graph_context]
)
```

### Pipeline Orchestration (v0.3.1)

Build complex workflows with dependency management:

```elixir
import PortfolioManager.Pipeline

run(:analysis, %{repo: "/path/to/repo"}) do
  step :scan, &scan_files/1
  step :analyze, &analyze/1, depends_on: [:scan]
  step :report, &generate_report/1, depends_on: [:analyze]
end
```

## Quickstart

```bash
mix deps.get
mix compile

# Start the app
iex -S mix
```

## Configuration

Manifests live in `config/manifests/` and select adapters per environment.
Set environment variables for API keys and graph connections as needed:

```bash
export GEMINI_API_KEY=your-key
export NEO4J_URI=bolt://localhost:7687
export NEO4J_USER=neo4j
export NEO4J_PASSWORD=password
```

## CLI

```bash
# Ask a question (RAG + LLM)
mix portfolio.ask "How does the workflow engine process steps?"

# Search without generation
mix portfolio.search "authentication flow" --index default --k 5

# Index a repository
mix portfolio.index . --index portfolio_manager --extensions .ex,.exs,.md

# Graph stats
mix portfolio.graph stats --graph default
```

## Examples

Examples assume the development manifest plus Postgres/pgvector and Neo4j. Run the
PortfolioIndex migrations before trying the RAG scripts:

```bash
mix ecto.create -r PortfolioIndex.Repo
mix ecto.migrate -r PortfolioIndex.Repo
```

See `examples/README.md` for runnable scripts, adapter notes, and the
`examples/run_all.sh` runner.

## License

MIT License - see [LICENSE](LICENSE) for details.
