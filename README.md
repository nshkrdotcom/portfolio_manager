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

## Quick Install (0.2.0)

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.2.0"}
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
