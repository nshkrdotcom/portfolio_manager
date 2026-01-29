# Getting Started

Portfolio Manager is the application layer for the Portfolio ecosystem. It
wraps `portfolio_core` (port specifications) and `portfolio_index` (adapter
implementations) to deliver manifest-driven RAG workflows, LLM routing, agent
tooling, graph analysis, evaluation, and CLI tasks for managing code
portfolios.

## What You Get

- **RAG queries** with four strategies: hybrid, self-RAG, graph-RAG, agentic
- **Centralized LLM gateway** through PortfolioCore adapters
- **Multi-profile routing** with fallback, round-robin, specialist, and
  cost-optimized strategies
- **Streaming** for RAG responses, router calls, and CLI output
- **Tool-using agents** for multi-step code analysis
- **Pipeline orchestration** with DAG-based step dependencies and caching
- **Graph analysis** for dependency and knowledge graphs (Neo4j)
- **Retrieval evaluation** with IR metrics and the RAG Triad framework
- **8 Mix tasks** for indexing, querying, evaluation, diagnostics, and maintenance
- **Manifest-driven configuration** via YAML files per environment

## Installation

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.4.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Prerequisites

- **Elixir** >= 1.17
- **PostgreSQL** with the pgvector extension (for vector storage)
- **Neo4j** (optional, only required for graph features)
- **API key** for your LLM provider (Gemini, OpenAI, or Anthropic)

## Environment Setup

```bash
# Required: at least one LLM provider key
export GEMINI_API_KEY=your-key
# export OPENAI_API_KEY=your-key
# export ANTHROPIC_API_KEY=your-key

# Database (standard Postgres env vars)
export PGHOST=localhost
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=portfolio_manager_dev

# Optional: Neo4j for graph features
export NEO4J_URI=bolt://localhost:7687
export NEO4J_USER=neo4j
export NEO4J_PASSWORD=password
```

## Database Setup

```bash
# Create the database and run migrations
mix ecto.create -r PortfolioIndex.Repo
mix ecto.migrate -r PortfolioIndex.Repo
```

## Quick Start

### 1. Index a Repository

Make a codebase searchable by indexing it:

```bash
mix portfolio.index /path/to/your/repo --index my_project
```

### 2. Search the Index

Find relevant code without generating an answer:

```bash
mix portfolio.search "authentication flow" --index my_project
```

### 3. Ask Questions

Get AI-generated answers grounded in your code:

```bash
mix portfolio.ask "How is user authentication implemented?" --index my_project
```

### 4. Stream Responses

Stream answers incrementally for a better experience:

```bash
mix portfolio.ask "Explain the caching layer" --stream
```

### 5. Evaluate Quality

Measure how well your RAG pipeline retrieves relevant content:

```bash
mix portfolio.eval.generate --sample-size 20
mix portfolio.eval.run --mode hybrid
```

## Library Usage

Use Portfolio Manager programmatically in your Elixir application:

```elixir
# Index a repository
{:ok, result} = PortfolioManager.RAG.index_repo("/path/to/repo", index_id: "my_project")

# Search for documents
{:ok, items} = PortfolioManager.RAG.search("GenServer callbacks", index_id: "my_project")

# Ask a question
{:ok, answer} = PortfolioManager.RAG.ask("How does error handling work?")

# Direct LLM completion
{:ok, result} = PortfolioManager.LLM.complete([
  %{role: :user, content: "Summarize this code..."}
])

# Route through multiple provider profiles
{:ok, response} = PortfolioManager.Router.complete(messages, task_type: :code)

# Run a tool-using agent
{:ok, analysis} = PortfolioManager.Agent.run(
  "Analyze authentication and suggest improvements",
  tools: [:search_code, :read_file]
)
```

## Configuration

Portfolio Manager uses YAML manifests for environment-specific configuration.
See the [Configuration Guide](configuration.md) for details on adapters,
pipelines, router profiles, and RAG strategies.

## Next Steps

- [LLM Gateway](llm.md) -- How LLM calls are routed and executed
- [RAG Guide](rag.md) -- Deep dive into retrieval strategies
- [Router Guide](router.md) -- Multi-profile LLM routing
- [Streaming Guide](streaming.md) -- Streaming patterns and integrations
- [Agent Guide](agent.md) -- Tool-using agents for code analysis
- [Pipeline Guide](pipeline.md) -- DAG-based workflow orchestration
- [Graph Guide](graph.md) -- Dependency and knowledge graphs
- [Evaluation Guide](evaluation.md) -- Measuring RAG quality
- [CLI Reference](cli.md) -- Complete command reference
- [Configuration](configuration.md) -- Manifest and adapter setup
