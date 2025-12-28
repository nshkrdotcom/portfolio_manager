# Getting Started

Portfolio Manager is an application layer that provides RAG (Retrieval-Augmented
Generation) queries and graph tooling for code analysis. It wraps `portfolio_core`
and `portfolio_index` to deliver manifest-driven, production-ready AI workflows.

## Features

- **RAG Queries**: Ask questions about your codebase using multiple retrieval strategies
- **Vector Search**: Find relevant code and documentation using semantic search
- **Graph Analysis**: Build and query dependency graphs for your projects
- **Manifest-Driven Configuration**: YAML-based adapter configuration for different environments

## Installation

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

## Prerequisites

Portfolio Manager requires:

- **PostgreSQL** with pgvector extension for vector storage
- **Neo4j** for graph operations (optional, only if using graph features)
- **Gemini API key** for embeddings and LLM (or configure alternative providers)

## Environment Setup

```bash
# Required for RAG
export GEMINI_API_KEY=your-key

# Database (uses standard Postgres env vars)
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
# Create database and run migrations
mix ecto.create -r PortfolioIndex.Repo
mix ecto.migrate -r PortfolioIndex.Repo
```

## Quick Start

### 1. Index a Repository

First, index a codebase to make it searchable:

```bash
mix portfolio.index /path/to/your/repo --index my_project
```

### 2. Search the Index

Find relevant code without generating an answer:

```bash
mix portfolio.search "authentication flow" --index my_project
```

### 3. Ask Questions

Get AI-generated answers based on your code:

```bash
mix portfolio.ask "How is user authentication implemented?" --index my_project
```

## Library Usage

You can also use Portfolio Manager programmatically:

```elixir
# Index a repository
{:ok, result} = PortfolioManager.RAG.index_repo("/path/to/repo", index_id: "my_project")

# Search for documents
{:ok, items} = PortfolioManager.RAG.search("GenServer callbacks", index_id: "my_project")

# Ask a question
{:ok, answer} = PortfolioManager.RAG.ask("How does error handling work?", index_id: "my_project")
```

## Configuration

Portfolio Manager uses YAML manifests for configuration. See the
[Configuration Guide](configuration.md) for details on customizing adapters,
pipelines, and RAG strategies.

## Next Steps

- [RAG Guide](rag.md) - Deep dive into RAG queries and strategies
- [Graph Guide](graph.md) - Learn about dependency graph analysis
- [CLI Reference](cli.md) - Complete command reference
- [Configuration](configuration.md) - Customize adapters and settings
