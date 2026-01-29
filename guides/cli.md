# CLI Reference

Portfolio Manager provides Mix tasks for RAG queries, indexing, evaluation,
graph analysis, and maintenance operations.

## mix portfolio.ask

Ask a question using RAG retrieval and LLM generation.

```bash
mix portfolio.ask "What does the User module do?"
mix portfolio.ask "How is authentication handled?" --strategy self_rag
mix portfolio.ask "Explain the caching layer" --index my_project --k 15
mix portfolio.ask "Summarize this module" --stream
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--strategy` | RAG strategy (hybrid, self_rag, graph_rag, agentic) | hybrid |
| `--index` | Vector index to query | default |
| `--k` | Number of documents to retrieve | 10 |
| `--stream` | Stream the response incrementally | false |

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

Returns ranked results with relevance score, source file path, and a content
snippet.

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

1. Scans the repository for matching files
2. Excludes `deps/`, `_build/`, `.git/` by default
3. Queues files for chunking and embedding
4. Creates the vector index if it does not exist

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

## mix portfolio.diagnostics

Show system diagnostics and health information.

```bash
mix portfolio.diagnostics
mix portfolio.diagnostics --format json
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--format` | Output format (table, json) | table |
| `--dry-run` | Show what would be checked | false |

### Output

Displays:
- Collection, document, and chunk counts
- Embedding coverage statistics
- Failed document counts
- Configuration summary

## mix portfolio.eval.generate

Generate synthetic evaluation test cases from indexed content.

```bash
mix portfolio.eval.generate
mix portfolio.eval.generate --sample-size 20
mix portfolio.eval.generate --collection my_docs --source-id doc_abc
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--sample-size` | Number of chunks to sample | 10 |
| `--collection` | Filter chunks by collection | all |
| `--source-id` | Filter by source document ID | all |

The generator samples chunks and uses the LLM to create realistic questions
that those chunks should answer.

## mix portfolio.eval.run

Run retrieval evaluation against test cases and report IR metrics.

```bash
mix portfolio.eval.run
mix portfolio.eval.run --mode hybrid
mix portfolio.eval.run --generate --sample-size 10
mix portfolio.eval.run --fail-under 0.8 --format json
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--mode` | Search mode (semantic, fulltext, hybrid) | semantic |
| `--collection` | Filter test cases by collection | all |
| `--generate` | Auto-generate test cases if none exist | false |
| `--sample-size` | Sample size when generating | 10 |
| `--format` | Output format (table, json) | table |
| `--fail-under` | Exit code 1 if recall@5 is below this threshold | none |

### Reported Metrics

- **Recall@K** -- Fraction of relevant chunks found
- **Precision@K** -- Fraction of top K results that are relevant
- **MRR** -- Mean Reciprocal Rank
- **Hit Rate@K** -- Whether any relevant result appears in top K

## mix portfolio.reembed

Re-embed documents using the current embedding model configuration.

```bash
mix portfolio.reembed
mix portfolio.reembed --collection my_docs --verbose
mix portfolio.reembed --batch-size 50
mix portfolio.reembed --dry-run
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--collection` | `-c` | Only re-embed chunks in this collection | all |
| `--batch-size` | `-b` | Chunks per batch | 100 |
| `--verbose` | `-v` | Show progress updates | false |
| `--dry-run` | | Preview without changes | false |
| `--help` | | Show help message | |

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
# Index multiple projects
mix portfolio.index ~/projects/api --index api
mix portfolio.index ~/projects/web --index web

# Query specific projects
mix portfolio.ask "How does auth work?" --index api
```

### Evaluation Workflow

```bash
# Generate test cases from your index
mix portfolio.eval.generate --sample-size 50

# Run baseline evaluation
mix portfolio.eval.run --mode semantic

# Compare with hybrid search
mix portfolio.eval.run --mode hybrid

# Gate CI on minimum quality
mix portfolio.eval.run --fail-under 0.8
```

### Re-embedding After Model Change

```bash
# Preview what would be re-embedded
mix portfolio.reembed --dry-run

# Re-embed with progress output
mix portfolio.reembed --verbose --batch-size 200
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (missing arguments, query failure, threshold not met) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GEMINI_API_KEY` | API key for Gemini embeddings and LLM |
| `OPENAI_API_KEY` | API key for OpenAI models |
| `ANTHROPIC_API_KEY` | API key for Anthropic (Claude) models |
| `NEO4J_URI` | Neo4j connection URI |
| `NEO4J_USER` | Neo4j username |
| `NEO4J_PASSWORD` | Neo4j password |
| `PGHOST` | PostgreSQL host |
| `PGUSER` | PostgreSQL username |
| `PGPASSWORD` | PostgreSQL password |
| `PGDATABASE` | PostgreSQL database name |
