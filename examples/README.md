# Portfolio Manager Examples

## Setup

Ensure dependencies are installed and configured:

```bash
# Set environment variables
export GEMINI_API_KEY=your-key
export NEO4J_URI=bolt://localhost:7687
export NEO4J_USER=neo4j
export NEO4J_PASSWORD=password
```

If you switch the manifest to use OpenAI, also set:

```bash
export OPENAI_API_KEY=your-key
```

Start required services (Postgres with pgvector; Neo4j for graph examples) using
your preferred tooling.

```bash
# Create the database and run PortfolioIndex migrations
mix ecto.create -r PortfolioIndex.Repo
mix ecto.migrate -r PortfolioIndex.Repo
```

## Running Examples

These examples rely on the adapters configured in `config/manifests/development.yml`.
By default they use the Gemini embedder/LLM in `portfolio_index`, so set
`GEMINI_API_KEY` or swap the manifest to another provider. LLM calls are executed
through `nsai_llm` Actions using the configured adapter. Graph examples also
require a `graph_store` adapter (such as Neo4j).
The `rag_query` example expects an index named `default`, so run `index_repo`
first or adjust the `index_id` in the script. You can also set
`PORTFOLIO_INDEX_ID` to keep all examples aligned on the same index.

If you previously created an index with different embedding dimensions,
drop the old `vectors_<index_id>` table (and its entry in
`vector_index_registry`) or switch to a fresh index ID.

```bash
# Run all examples
./examples/run_all.sh

# List available examples
./examples/run_all.sh --list

# Run a single example
./examples/run_all.sh rag
```

```bash
# Basic RAG query
mix run examples/rag_query.exs

# Index a repository
mix run examples/index_repo.exs

# Graph analysis
mix run examples/graph_analysis.exs

# Full workflow
mix run examples/full_workflow.exs

# Router usage (v0.3.1)
mix run examples/router_usage.exs

# Streaming query (v0.3.1)
mix run examples/streaming_query.exs

# Agent task (v0.3.1)
mix run examples/agent_task.exs

# Pipeline workflow (v0.3.1)
mix run examples/pipeline_workflow.exs
```

## v0.3.1 Examples

### Router Usage

Demonstrates multi-provider LLM routing with different strategies:
- Fallback routing
- Specialist routing by task type
- Streaming responses

### Streaming Query

Shows how to stream RAG queries and search results incrementally.

### Agent Task

Demonstrates the tool-using agent framework for complex code analysis tasks.

### Pipeline Workflow

Shows DAG-based pipeline orchestration with:
- Step dependencies
- Caching
- Telemetry events
- Timeout handling
