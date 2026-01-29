# RAG Queries

Portfolio Manager provides RAG (Retrieval-Augmented Generation) capabilities
through the `PortfolioManager.RAG` module. This guide covers indexing, searching,
and querying your codebase.

## Indexing

Before you can query, you need to index your repository:

```elixir
# Index with default settings
{:ok, result} = PortfolioManager.RAG.index_repo("/path/to/repo")

# Specify index name and file types
{:ok, result} = PortfolioManager.RAG.index_repo("/path/to/repo",
  index_id: "my_project",
  extensions: [".ex", ".exs", ".md", ".txt"]
)
```

The indexer:
1. Scans the repository for matching files
2. Chunks documents using the configured chunker
3. Generates embeddings using the configured embedder
4. Stores vectors in the configured vector store (pgvector by default)

### CLI

```bash
# Index current directory
mix portfolio.index

# Index specific path with custom settings
mix portfolio.index /path/to/repo --index my_project --extensions .ex,.exs,.md
```

## Searching

Search retrieves relevant documents without generating an answer:

```elixir
{:ok, items} = PortfolioManager.RAG.search("authentication middleware")

# Each item contains:
# - content: the text chunk
# - score: relevance score
# - source: file path
# - metadata: additional context
```

### CLI

```bash
mix portfolio.search "GenServer callbacks" --index my_project --k 5
```

## Asking Questions

The `ask/2` function retrieves context and generates an answer:

```elixir
{:ok, answer} = PortfolioManager.RAG.ask("How is caching implemented?")
```

Generation runs through `nsai_llm` Actions using the configured LLM adapter.

### CLI

```bash
mix portfolio.ask "What does the User module do?" --strategy hybrid
```

## RAG Strategies

Portfolio Manager supports multiple retrieval strategies:

### Hybrid (default)

Combines vector similarity with keyword matching:

```elixir
PortfolioManager.RAG.ask(question, strategy: :hybrid)
```

Configurable weights in manifest:

```yaml
rag:
  strategies:
    hybrid:
      vector_weight: 0.7
      keyword_weight: 0.3
```

### Self-RAG

Includes self-critique to improve answer quality:

```elixir
PortfolioManager.RAG.ask(question, strategy: :self_rag)
```

### Graph-RAG

Uses graph relationships to enhance context:

```elixir
PortfolioManager.RAG.ask(question, strategy: :graph_rag, graph_id: "my_graph")
```

### Agentic

Multi-step reasoning with tool use:

```elixir
PortfolioManager.RAG.ask(question, strategy: :agentic)
```

## Query Options

```elixir
PortfolioManager.RAG.query(question,
  strategy: :hybrid,      # RAG strategy
  index_id: "default",    # Vector index to search
  graph_id: "default",    # Graph for context (graph_rag)
  k: 10                   # Number of results to retrieve
)
```

## API Reference

### `query/2`

Full RAG query returning structured results:

```elixir
@spec query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}

# Returns map with:
# - :items - retrieved documents
# - :answer - generated answer (some strategies)
# - :strategy - strategy used
# - :timing_ms - execution time
```

### `ask/2`

Simplified interface returning just the answer:

```elixir
@spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
```

### `search/2`

Retrieval only, no generation:

```elixir
@spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

### `index_repo/2`

Index a repository for RAG:

```elixir
@spec index_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}

# Options:
# - :index_id - Index name (default: "default")
# - :extensions - File extensions to include
# - :exclude - Patterns to exclude
# - :recreate_index - Drop and recreate on dimension mismatch
```

## Telemetry

RAG operations emit telemetry events:

```elixir
[:portfolio_manager, :rag, :query]
```

Measurements include `timing_ms` and `items_count`.
