# CLI Reference

Portfolio Manager provides Mix tasks for common operations.

## mix portfolio.ask

Ask a question using RAG.

```bash
mix portfolio.ask "What does the User module do?"
mix portfolio.ask "How is authentication handled?" --strategy self_rag
mix portfolio.ask "Explain the caching layer" --index my_project --k 15
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--strategy` | RAG strategy (hybrid, self_rag, graph_rag, agentic) | hybrid |
| `--index` | Vector index to query | default |
| `--k` | Number of documents to retrieve | 10 |

## mix portfolio.search

Search portfolio content without generating an answer.

```bash
mix portfolio.search "authentication flow"
mix portfolio.search "GenServer" --index code --k 5
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--index` | Vector index to query | default |
| `--k` | Number of results to return | 10 |

### Output

Returns ranked results with:
- Relevance score
- Source file path
- Content snippet

## mix portfolio.index

Index a repository for RAG queries.

```bash
mix portfolio.index /path/to/repo
mix portfolio.index . --index my_project
mix portfolio.index ~/code/app --extensions .ex,.exs,.md,.txt
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--index` | Index name | default |
| `--extensions` | Comma-separated file extensions | .ex,.exs,.md |

### Behavior

1. Scans repository for matching files
2. Excludes `deps/`, `_build/`, `.git/` by default
3. Queues files for chunking and embedding
4. Creates vector index if it doesn't exist

## mix portfolio.graph

Graph operations for dependency analysis.

### Show Stats

```bash
mix portfolio.graph stats
mix portfolio.graph stats --graph my_graph
mix portfolio.graph  # defaults to stats
```

### Build Dependency Graph

```bash
mix portfolio.graph build /path/to/repo --graph deps
mix portfolio.graph build . --graph elixir_deps --language elixir
mix portfolio.graph build /python/project --graph py_deps --language python
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--graph` | Graph ID | default |
| `--language` | Dependency language (elixir, python) | elixir |

## Common Patterns

### Index and Query Workflow

```bash
# Step 1: Index your codebase
mix portfolio.index ~/projects/my_app --index my_app

# Step 2: Search for relevant code
mix portfolio.search "error handling" --index my_app

# Step 3: Ask questions
mix portfolio.ask "How are errors logged?" --index my_app
```

### Multi-Project Setup

```bash
# Index multiple projects with different names
mix portfolio.index ~/projects/api --index api
mix portfolio.index ~/projects/web --index web
mix portfolio.index ~/projects/core --index core

# Query specific projects
mix portfolio.ask "How does auth work?" --index api
mix portfolio.ask "What components exist?" --index web
```

### Build and Query Dependencies

```bash
# Build dependency graph
mix portfolio.graph build ~/projects/my_app --graph deps

# View statistics
mix portfolio.graph stats --graph deps
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (missing arguments, query failure, etc.) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GEMINI_API_KEY` | API key for Gemini embeddings/LLM |
| `NEO4J_URI` | Neo4j connection URI |
| `NEO4J_USER` | Neo4j username |
| `NEO4J_PASSWORD` | Neo4j password |
| `PGHOST` | PostgreSQL host |
| `PGUSER` | PostgreSQL username |
| `PGPASSWORD` | PostgreSQL password |
| `PGDATABASE` | PostgreSQL database name |
