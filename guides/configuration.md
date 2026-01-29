# Configuration

Portfolio Manager uses manifest-driven configuration. YAML manifests define
adapters, pipelines, and RAG strategies for each environment.

## Manifest Location

Manifests are located in `config/manifests/`:

```
config/manifests/
  development.yml
  production.yml
  test.yml
```

The environment is determined by the `:env` config:

```elixir
config :portfolio_manager,
  env: :development  # or :production, :test
```

## Manifest Structure

```yaml
version: "1.0"
environment: development

adapters:
  # Core adapters
  vector_store: ...
  graph_store: ...
  embedder: ...
  llm: ...
  chunker: ...

pipelines:
  ingestion: ...
  embedding: ...

graphs:
  # Named graph configurations
  default: ...

rag:
  # RAG strategy settings
  default_strategy: hybrid
  strategies: ...

telemetry:
  enabled: true
  exporters: [console]
```

## Adapters

### Vector Store

pgvector-backed vector storage:

```yaml
adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      repo: PortfolioManager.Repo
      index_type: ivfflat  # or hnsw, flat
      lists: 100           # IVFFlat lists parameter
```

### Graph Store

Neo4j graph database:

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

### Embedder

Gemini embeddings:

```yaml
adapters:
  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.Gemini
    config:
      model: gemini-embedding-001
      dimensions: 768
```

### LLM

Gemini for answer generation:

```yaml
adapters:
  llm:
    adapter: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-flash-lite-latest
      max_tokens: 4096
```

LLM execution goes through `nsai_llm` Actions and the configured adapter above.

#### Router Profiles (Optional)

```yaml
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

### Chunker

Document chunking configuration:

```yaml
adapters:
  chunker:
    adapter: PortfolioIndex.Adapters.Chunker.Recursive
    config:
      chunk_size: 1000
      chunk_overlap: 200
```

## Pipelines

Control background processing:

```yaml
pipelines:
  ingestion:
    enabled: true
    concurrency: 10
    batch_size: 50

  embedding:
    enabled: true
    concurrency: 5
    rate_limit: 100  # requests per minute
```

## RAG Strategies

Configure RAG behavior:

```yaml
rag:
  default_strategy: hybrid

  strategies:
    hybrid:
      vector_weight: 0.7
      keyword_weight: 0.3

    self_rag:
      critique_threshold: 3
```

## Graph Definitions

Pre-define named graphs:

```yaml
graphs:
  default:
    id: default
    type: knowledge
    config:
      community_detection: false

  code:
    id: code
    type: dependency
    config:
      languages: [elixir, python, javascript]
```

## Environment Variables

Manifests support environment variable substitution:

```yaml
config:
  uri: ${NEO4J_URI:-bolt://localhost:7687}
```

Syntax: `${VAR_NAME:-default_value}`

## Elixir Configuration

Additional Elixir config in `config/config.exs`:

```elixir
# Database connection
config :portfolio_manager, PortfolioManager.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: System.get_env("PGDATABASE", "portfolio_manager_dev"),
  pool_size: 10

# Disable repo for testing
config :portfolio_manager, start_repo: false
```

## Production Manifest Example

```yaml
version: "1.0"
environment: production

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      repo: PortfolioManager.Repo
      index_type: hnsw
      m: 16
      ef_construction: 64

  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.Gemini
    config:
      model: gemini-embedding-001
      dimensions: 768

  llm:
    adapter: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-flash-lite-latest
      max_tokens: 8192

pipelines:
  ingestion:
    enabled: true
    concurrency: 20
    batch_size: 100

  embedding:
    enabled: true
    concurrency: 10
    rate_limit: 500

telemetry:
  enabled: true
  exporters:
    - otlp
```
