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

Portfolio Manager is the application layer for the Portfolio ecosystem. It
provides RAG workflows, LLM routing, agent tooling, pipeline orchestration,
graph analysis, evaluation, and CLI tasks -- all wired together through
manifest-driven configuration on top of
[portfolio_core](https://github.com/nshkrdotcom/portfolio_core) and
[portfolio_index](https://github.com/nshkrdotcom/portfolio_index).

## Install

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.4.0"}
  ]
end
```

## Features

### Centralized LLM Gateway

All LLM calls flow through `PortfolioManager.LLM`, which resolves the active
adapter from the PortfolioCore registry and normalizes responses:

```elixir
{:ok, result} = PortfolioManager.LLM.complete([
  %{role: :user, content: "Explain pattern matching in Elixir."}
])

IO.puts(result.content)
```

### RAG Queries

Index a codebase and ask questions with retrieval-augmented generation. Four
strategies are available: hybrid (vector + keyword), self-RAG (self-critique),
graph-RAG (graph-enhanced context), and agentic (multi-step reasoning):

```elixir
{:ok, answer} = PortfolioManager.RAG.ask("How is auth implemented?",
  strategy: :hybrid
)
```

### Multi-Profile LLM Routing

Route requests across provider profiles with fallback, round-robin, specialist,
or cost-optimized strategies:

```elixir
{:ok, response} = PortfolioManager.Router.complete(messages, task_type: :code)
```

Profiles are defined in the manifest as lightweight configurations (model,
capabilities, priority) without requiring separate adapter modules.

### Streaming

Stream RAG responses, router completions, and CLI output:

```elixir
PortfolioManager.RAG.stream_query("How does this work?", fn chunk ->
  IO.write(chunk)
end)
```

```bash
mix portfolio.ask "Explain this codebase" --stream
```

### Tool-Using Agents

Run multi-step code analysis with tool-using agents:

```elixir
{:ok, analysis} = PortfolioManager.Agent.run(
  "Analyze authentication and suggest improvements",
  tools: [:search_code, :read_file, :get_graph_context]
)
```

### Pipeline Orchestration

Define DAG-based workflows with dependencies, caching, and parallel execution:

```elixir
import PortfolioManager.Pipeline

run(:analysis, %{repo: "/path/to/repo"}) do
  step :scan, &scan_files/1
  step :analyze, &analyze/1, depends_on: [:scan]
  step :report, &generate_report/1, depends_on: [:analyze]
end
```

### Retrieval Evaluation

Measure RAG quality with IR metrics and the RAG Triad (context relevance,
groundedness, answer relevance):

```bash
mix portfolio.eval.generate --sample-size 50
mix portfolio.eval.run --mode hybrid --fail-under 0.8
```

### Graph Analysis

Build and query dependency graphs from repositories:

```bash
mix portfolio.graph build /path/to/repo --graph deps --language elixir
```

## CLI Tasks

| Task | Description |
|------|-------------|
| `mix portfolio.ask` | RAG query with LLM generation |
| `mix portfolio.search` | Semantic search without generation |
| `mix portfolio.index` | Index a repository for RAG |
| `mix portfolio.graph` | Graph stats and dependency building |
| `mix portfolio.diagnostics` | System health and statistics |
| `mix portfolio.eval.generate` | Generate synthetic evaluation test cases |
| `mix portfolio.eval.run` | Run retrieval evaluation with IR metrics |
| `mix portfolio.reembed` | Re-embed documents after model changes |

## Quick Start

```bash
# Set your API key
export GEMINI_API_KEY=your-key

# Fetch deps and set up the database
mix deps.get
mix ecto.create -r PortfolioIndex.Repo
mix ecto.migrate -r PortfolioIndex.Repo

# Index a codebase
mix portfolio.index /path/to/repo --index my_project

# Search it
mix portfolio.search "error handling" --index my_project

# Ask a question
mix portfolio.ask "How are errors handled?" --index my_project --stream
```

## Configuration

Manifests live in `config/manifests/` and configure adapters, pipelines, router
profiles, and RAG strategies per environment:

```yaml
adapters:
  llm:
    adapter: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-flash-lite-latest

router:
  strategy: specialist
  providers:
    - name: gemini_fast
      config:
        model: gemini-flash-lite-latest
      capabilities: [generation, code]
      priority: 1
    - name: gemini_reasoning
      config:
        model: gemini-1.5-pro-latest
      capabilities: [reasoning, analysis]
      priority: 2
```

Environment variables for API keys and database connections:

```bash
export GEMINI_API_KEY=your-key
export OPENAI_API_KEY=your-key       # optional
export ANTHROPIC_API_KEY=your-key    # optional
export NEO4J_URI=bolt://localhost:7687
export NEO4J_USER=neo4j
export NEO4J_PASSWORD=password
```

## Documentation

Full guides are available on [HexDocs](https://hexdocs.pm/portfolio_manager):

- [Getting Started](guides/getting_started.md) -- Installation and first steps
- [LLM Gateway](guides/llm.md) -- Centralized LLM access and configuration
- [RAG Queries](guides/rag.md) -- Retrieval strategies and query patterns
- [Router](guides/router.md) -- Multi-profile routing strategies
- [Streaming](guides/streaming.md) -- Streaming patterns and integrations
- [Agent](guides/agent.md) -- Tool-using agents for code analysis
- [Pipeline](guides/pipeline.md) -- DAG workflow orchestration
- [Graph](guides/graph.md) -- Dependency and knowledge graphs
- [Evaluation](guides/evaluation.md) -- RAG quality measurement
- [CLI Reference](guides/cli.md) -- Complete command reference
- [Configuration](guides/configuration.md) -- Manifest and adapter setup

## Examples

Runnable example scripts live in `examples/`. They assume the development
manifest plus PostgreSQL/pgvector. See [examples/README.md](examples/README.md)
for setup and usage.

## Architecture

Portfolio Manager sits on top of two foundation packages:

- **[portfolio_core](https://github.com/nshkrdotcom/portfolio_core)** (v0.5.0) --
  Port specifications (Elixir behaviours) and the adapter registry
- **[portfolio_index](https://github.com/nshkrdotcom/portfolio_index)** (v0.5.0) --
  Concrete adapter implementations for LLM, embedding, vector store, graph
  store, chunking, evaluation, and more

Portfolio Manager provides the application layer: OTP supervision, manifest
loading, the LLM gateway, router GenServer, RAG orchestration, agent
framework, pipeline engine, and CLI tasks.

## License

MIT License -- see [LICENSE](LICENSE) for details.
