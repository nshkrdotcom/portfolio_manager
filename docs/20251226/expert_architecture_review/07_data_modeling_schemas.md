# Data Modeling and Schema Design

**Expert:** Dr. Rachel Kim, Senior Fellow Data Architect
**Experience:** 20+ years at Oracle, Snowflake, ML Systems Architecture

---

## Table of Contents

1. [Domain Model Overview](#domain-model-overview)
2. [PostgreSQL Schema](#postgresql-schema)
3. [Vector Store Schema](#vector-store-schema)
4. [Graph Schema](#graph-schema)
5. [Manifest Storage Schema](#manifest-storage-schema)
6. [Migration Strategy](#migration-strategy)

---

## 1. Domain Model Overview

### 1.1 Core Entities

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DOMAIN MODEL                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  DOCUMENT DOMAIN                                                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │  Repository  │◀──▶│   Document   │◀──▶│    Chunk     │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│        │                   │                    │                       │
│        │                   │                    │                       │
│        ▼                   ▼                    ▼                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   RepoMeta   │    │  DocVersion  │    │  Embedding   │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│                                                                          │
│  GRAPH DOMAIN                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │ GraphSpace   │◀──▶│   Entity     │◀──▶│    Edge      │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│        │                   │                    │                       │
│        ▼                   ▼                    ▼                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │  Community   │    │EntityEmbed   │    │ EdgeWeight   │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│                                                                          │
│  CONFIG DOMAIN                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   Manifest   │◀──▶│   Pipeline   │◀──▶│   Adapter    │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Entity Relationships

```elixir
# Domain model as Elixir structs (no Ecto dependency in core)

defmodule PortfolioCore.Domain.Repository do
  defstruct [
    :id,
    :name,
    :path,
    :remote_url,
    :default_branch,
    :languages,
    :metadata,
    :created_at,
    :updated_at
  ]
end

defmodule PortfolioCore.Domain.Document do
  defstruct [
    :id,
    :repo_id,
    :path,
    :content_hash,
    :content_type,
    :language,
    :size_bytes,
    :line_count,
    :metadata,
    :created_at,
    :updated_at
  ]
end

defmodule PortfolioCore.Domain.Chunk do
  defstruct [
    :id,
    :document_id,
    :index,
    :content,
    :content_hash,
    :start_offset,
    :end_offset,
    :embedding_id,
    :metadata,
    :created_at
  ]
end

defmodule PortfolioCore.Domain.Embedding do
  defstruct [
    :id,
    :chunk_id,
    :model_id,
    :model_version,
    :vector,
    :dimensions,
    :created_at
  ]
end

defmodule PortfolioCore.Domain.GraphEntity do
  defstruct [
    :id,
    :graph_id,
    :type,
    :name,
    :properties,
    :embedding_id,
    :source_chunk_ids,
    :created_at,
    :updated_at
  ]
end

defmodule PortfolioCore.Domain.GraphEdge do
  defstruct [
    :id,
    :graph_id,
    :from_entity_id,
    :to_entity_id,
    :type,
    :weight,
    :properties,
    :created_at
  ]
end

defmodule PortfolioCore.Domain.Community do
  defstruct [
    :id,
    :graph_id,
    :level,
    :parent_id,
    :entity_ids,
    :summary,
    :summary_embedding_id,
    :metadata,
    :created_at
  ]
end
```

---

## 2. PostgreSQL Schema

### 2.1 Core Tables DDL

```sql
-- ============================================
-- REPOSITORIES AND DOCUMENTS
-- ============================================

CREATE TABLE repositories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    path VARCHAR(1000) NOT NULL,
    remote_url VARCHAR(1000),
    default_branch VARCHAR(100) DEFAULT 'main',
    languages JSONB DEFAULT '[]',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT repositories_name_unique UNIQUE (name),
    CONSTRAINT repositories_path_unique UNIQUE (path)
);

CREATE INDEX idx_repositories_name ON repositories(name);
CREATE INDEX idx_repositories_languages ON repositories USING gin(languages);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER repositories_updated_at
    BEFORE UPDATE ON repositories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- DOCUMENTS
-- ============================================

CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    repo_id UUID NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    path VARCHAR(1000) NOT NULL,
    content_hash VARCHAR(64) NOT NULL,  -- SHA-256
    content_type VARCHAR(100),
    language VARCHAR(50),
    size_bytes INTEGER,
    line_count INTEGER,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT documents_repo_path_unique UNIQUE (repo_id, path)
);

CREATE INDEX idx_documents_repo ON documents(repo_id);
CREATE INDEX idx_documents_content_hash ON documents(content_hash);
CREATE INDEX idx_documents_path ON documents(path);
CREATE INDEX idx_documents_language ON documents(language);

CREATE TRIGGER documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Document versions for tracking changes
CREATE TABLE document_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    git_commit VARCHAR(40),
    change_type VARCHAR(20) CHECK (change_type IN ('created', 'modified', 'deleted')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT document_versions_unique UNIQUE (document_id, version_number)
);

CREATE INDEX idx_doc_versions_document ON document_versions(document_id);

-- ============================================
-- CHUNKS AND EMBEDDINGS
-- ============================================

CREATE TABLE chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    index_in_document INTEGER NOT NULL,
    content TEXT NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    chunk_strategy VARCHAR(50),  -- 'recursive', 'semantic', 'code'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT chunks_document_index_unique UNIQUE (document_id, index_in_document)
);

CREATE INDEX idx_chunks_document ON chunks(document_id);
CREATE INDEX idx_chunks_content_hash ON chunks(content_hash);

-- Embeddings table with model versioning
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chunk_id UUID NOT NULL REFERENCES chunks(id) ON DELETE CASCADE,
    index_id VARCHAR(100) NOT NULL,  -- Which vector index this belongs to
    model_id VARCHAR(100) NOT NULL,
    model_version VARCHAR(50) NOT NULL,
    vector vector(3072),  -- Max dimension we support
    dimensions INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT embeddings_chunk_index_model UNIQUE (chunk_id, index_id, model_id)
);

-- Create appropriate vector index based on dimension
-- For 1536 dimensions (common)
CREATE INDEX idx_embeddings_vector_1536 ON embeddings
    USING hnsw ((vector::vector(1536)) vector_cosine_ops)
    WHERE dimensions = 1536;

-- For 768 dimensions
CREATE INDEX idx_embeddings_vector_768 ON embeddings
    USING hnsw ((vector::vector(768)) vector_cosine_ops)
    WHERE dimensions = 768;

-- For 3072 dimensions
CREATE INDEX idx_embeddings_vector_3072 ON embeddings
    USING hnsw ((vector::vector(3072)) vector_cosine_ops)
    WHERE dimensions = 3072;

CREATE INDEX idx_embeddings_chunk ON embeddings(chunk_id);
CREATE INDEX idx_embeddings_index ON embeddings(index_id);
CREATE INDEX idx_embeddings_model ON embeddings(model_id, model_version);

-- ============================================
-- VECTOR INDEXES REGISTRY
-- ============================================

CREATE TABLE vector_indexes (
    id VARCHAR(100) PRIMARY KEY,
    display_name VARCHAR(255) NOT NULL,
    embedding_model VARCHAR(100) NOT NULL,
    dimensions INTEGER NOT NULL,
    index_type VARCHAR(50) DEFAULT 'hnsw',
    content_types VARCHAR(100)[] DEFAULT '{}',
    backend VARCHAR(50) DEFAULT 'pgvector',
    config JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    chunk_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TRIGGER vector_indexes_updated_at
    BEFORE UPDATE ON vector_indexes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 2.2 Graph Tables DDL

```sql
-- ============================================
-- GRAPH NAMESPACES
-- ============================================

CREATE TABLE graph_namespaces (
    id VARCHAR(255) PRIMARY KEY,  -- e.g., 'repo:my-repo', 'domain:auth'
    type VARCHAR(50) NOT NULL CHECK (type IN ('repo', 'domain', 'ecosystem', 'community', 'meta')),
    parent_id VARCHAR(255) REFERENCES graph_namespaces(id),
    display_name VARCHAR(255) NOT NULL,
    description TEXT,
    config JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    entity_count INTEGER DEFAULT 0,
    edge_count INTEGER DEFAULT 0,
    community_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_graph_namespaces_type ON graph_namespaces(type);
CREATE INDEX idx_graph_namespaces_parent ON graph_namespaces(parent_id);

CREATE TRIGGER graph_namespaces_updated_at
    BEFORE UPDATE ON graph_namespaces
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- GRAPH ENTITIES
-- ============================================

CREATE TABLE graph_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(id) ON DELETE CASCADE,
    external_id VARCHAR(255),  -- Optional external reference
    type VARCHAR(100) NOT NULL,  -- 'function', 'class', 'concept', etc.
    name VARCHAR(500) NOT NULL,
    description TEXT,
    properties JSONB DEFAULT '{}',
    source_chunk_ids UUID[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT graph_entities_graph_external UNIQUE (graph_id, external_id)
);

-- Partitioning by graph_id for large deployments
-- CREATE TABLE graph_entities (...) PARTITION BY HASH (graph_id);

CREATE INDEX idx_graph_entities_graph ON graph_entities(graph_id);
CREATE INDEX idx_graph_entities_type ON graph_entities(graph_id, type);
CREATE INDEX idx_graph_entities_name ON graph_entities(graph_id, name);
CREATE INDEX idx_graph_entities_name_trgm ON graph_entities
    USING gin(name gin_trgm_ops);

CREATE TRIGGER graph_entities_updated_at
    BEFORE UPDATE ON graph_entities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Entity embeddings (separate for flexibility)
CREATE TABLE entity_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id UUID NOT NULL REFERENCES graph_entities(id) ON DELETE CASCADE,
    model_id VARCHAR(100) NOT NULL,
    model_version VARCHAR(50) NOT NULL,
    vector vector(1536),
    dimensions INTEGER NOT NULL DEFAULT 1536,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT entity_embeddings_unique UNIQUE (entity_id, model_id)
);

CREATE INDEX idx_entity_embeddings_vector ON entity_embeddings
    USING hnsw (vector vector_cosine_ops);
CREATE INDEX idx_entity_embeddings_entity ON entity_embeddings(entity_id);

-- ============================================
-- GRAPH EDGES
-- ============================================

CREATE TABLE graph_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(id) ON DELETE CASCADE,
    from_entity_id UUID NOT NULL REFERENCES graph_entities(id) ON DELETE CASCADE,
    to_entity_id UUID NOT NULL REFERENCES graph_entities(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,  -- 'CALLS', 'IMPORTS', 'DEPENDS_ON', etc.
    weight FLOAT DEFAULT 1.0,
    properties JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT graph_edges_unique UNIQUE (graph_id, from_entity_id, to_entity_id, type)
);

CREATE INDEX idx_graph_edges_graph ON graph_edges(graph_id);
CREATE INDEX idx_graph_edges_from ON graph_edges(graph_id, from_entity_id);
CREATE INDEX idx_graph_edges_to ON graph_edges(graph_id, to_entity_id);
CREATE INDEX idx_graph_edges_type ON graph_edges(graph_id, type);

-- Cross-graph edges (for graph-of-graphs)
CREATE TABLE cross_graph_edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(id),
    from_entity_id UUID NOT NULL,
    to_graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(id),
    to_entity_id UUID NOT NULL,
    type VARCHAR(100) NOT NULL,  -- 'SAME_AS', 'REFERENCES', 'DEPENDS_ON'
    weight FLOAT DEFAULT 1.0,
    evidence TEXT,  -- Why this connection exists
    properties JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_cross_edges_from ON cross_graph_edges(from_graph_id, from_entity_id);
CREATE INDEX idx_cross_edges_to ON cross_graph_edges(to_graph_id, to_entity_id);

-- ============================================
-- COMMUNITIES
-- ============================================

CREATE TABLE graph_communities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(id) ON DELETE CASCADE,
    level INTEGER NOT NULL DEFAULT 0,  -- Hierarchy level
    parent_id UUID REFERENCES graph_communities(id),
    entity_ids UUID[] NOT NULL,
    summary TEXT,
    summary_embedding vector(1536),
    algorithm VARCHAR(50),  -- 'louvain', 'leiden', 'lpa'
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_communities_graph ON graph_communities(graph_id);
CREATE INDEX idx_communities_level ON graph_communities(graph_id, level);
CREATE INDEX idx_communities_parent ON graph_communities(parent_id);
CREATE INDEX idx_communities_embedding ON graph_communities
    USING hnsw (summary_embedding vector_cosine_ops)
    WHERE summary_embedding IS NOT NULL;
```

### 2.3 Audit and Provenance Tables

```sql
-- ============================================
-- AUDIT LOG
-- ============================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    action VARCHAR(50) NOT NULL,  -- 'create', 'update', 'delete', 'ingest', 'query'
    actor VARCHAR(255) NOT NULL,
    resource_type VARCHAR(100) NOT NULL,
    resource_id VARCHAR(255) NOT NULL,
    details JSONB DEFAULT '{}',
    trace_id VARCHAR(64),
    duration_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Partition by month for time-series queries
CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX idx_audit_resource ON audit_log(resource_type, resource_id);
CREATE INDEX idx_audit_trace ON audit_log(trace_id) WHERE trace_id IS NOT NULL;

-- ============================================
-- PROVENANCE CHAINS
-- ============================================

CREATE TABLE provenance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type VARCHAR(100) NOT NULL,  -- 'chunk', 'entity', 'embedding'
    entity_id UUID NOT NULL,
    source_type VARCHAR(100),  -- 'document', 'chunk', 'extraction'
    source_id UUID,
    operation VARCHAR(100) NOT NULL,  -- 'chunked_from', 'embedded_from', 'extracted_from'
    operator VARCHAR(100),  -- Which component performed the operation
    operator_version VARCHAR(50),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_provenance_entity ON provenance(entity_type, entity_id);
CREATE INDEX idx_provenance_source ON provenance(source_type, source_id);

-- ============================================
-- QUERY HISTORY (for evaluation)
-- ============================================

CREATE TABLE query_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_text TEXT NOT NULL,
    query_embedding vector(1536),
    mode VARCHAR(50),  -- 'semantic', 'hybrid', 'graph'
    result_count INTEGER,
    latency_ms INTEGER,
    retrieved_chunk_ids UUID[],
    generated_answer TEXT,
    feedback_score FLOAT,  -- User feedback if provided
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_query_history_created ON query_history(created_at);
CREATE INDEX idx_query_history_mode ON query_history(mode);
```

---

## 3. Vector Store Schema

### 3.1 Multi-Index Management

```sql
-- Index configuration and health
CREATE TABLE vector_index_health (
    index_id VARCHAR(100) PRIMARY KEY REFERENCES vector_indexes(id),
    last_sync TIMESTAMP WITH TIME ZONE,
    chunk_count INTEGER DEFAULT 0,
    avg_query_latency_ms FLOAT,
    last_query_at TIMESTAMP WITH TIME ZONE,
    error_count INTEGER DEFAULT 0,
    last_error TEXT,
    last_error_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'healthy'
        CHECK (status IN ('healthy', 'degraded', 'error', 'rebuilding')),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index rebuild jobs
CREATE TABLE vector_index_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    index_id VARCHAR(100) NOT NULL REFERENCES vector_indexes(id),
    job_type VARCHAR(50) NOT NULL,  -- 'rebuild', 'optimize', 'reembed'
    status VARCHAR(20) DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    progress_pct FLOAT DEFAULT 0,
    items_processed INTEGER DEFAULT 0,
    items_total INTEGER,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_vector_jobs_index ON vector_index_jobs(index_id);
CREATE INDEX idx_vector_jobs_status ON vector_index_jobs(status);
```

### 3.2 Qdrant Schema (Conceptual)

```elixir
# Qdrant collection configuration
defmodule PortfolioIndex.Adapters.Qdrant.Schema do
  def collection_config(index_config) do
    %{
      vectors: %{
        size: index_config.dimensions,
        distance: :Cosine
      },
      hnsw_config: %{
        m: 16,
        ef_construct: 100,
        full_scan_threshold: 10000
      },
      optimizers_config: %{
        memmap_threshold: 20000
      },
      on_disk_payload: true
    }
  end

  def payload_schema do
    %{
      chunk_id: :keyword,
      document_id: :keyword,
      repo_id: :keyword,
      path: :keyword,
      content_type: :keyword,
      language: :keyword,
      chunk_index: :integer,
      created_at: :datetime
    }
  end
end
```

---

## 4. Graph Schema

### 4.1 Triple Store Schema (RocksDB)

```elixir
# Column families for triple store
defmodule PortfolioIndex.Adapters.TripleStore.Schema do
  @doc """
  Column families:
  - spo: (subject, predicate, object) -> context
  - pos: (predicate, object, subject) -> context
  - osp: (object, subject, predicate) -> context
  - contexts: context_id -> metadata
  - entities: entity_id -> entity data
  """

  def column_families do
    [
      "default",
      "spo",
      "pos",
      "osp",
      "contexts",
      "entities",
      "entity_names",
      "entity_types"
    ]
  end

  @doc """
  Key encoding for triple indexes.
  """
  def encode_spo_key(subject, predicate, object) do
    [encode_term(subject), encode_term(predicate), encode_term(object)]
    |> Enum.join(<<0>>)
  end

  def encode_pos_key(predicate, object, subject) do
    [encode_term(predicate), encode_term(object), encode_term(subject)]
    |> Enum.join(<<0>>)
  end

  def encode_osp_key(object, subject, predicate) do
    [encode_term(object), encode_term(subject), encode_term(predicate)]
    |> Enum.join(<<0>>)
  end

  defp encode_term(term) when is_binary(term), do: term
  defp encode_term(term), do: :erlang.term_to_binary(term)

  @doc """
  Context value encoding.
  """
  def encode_context(context) do
    :erlang.term_to_binary(%{
      graph_id: context.graph_id,
      source_chunk_id: context.source_chunk_id,
      confidence: context.confidence,
      extractor: context.extractor,
      timestamp: context.timestamp
    })
  end
end
```

### 4.2 Neo4j Schema

```cypher
-- Constraints
CREATE CONSTRAINT entity_id IF NOT EXISTS
FOR (e:Entity) REQUIRE e.id IS UNIQUE;

CREATE CONSTRAINT entity_graph_external IF NOT EXISTS
FOR (e:Entity) REQUIRE (e.graph_id, e.external_id) IS UNIQUE;

CREATE CONSTRAINT graph_namespace IF NOT EXISTS
FOR (g:GraphNamespace) REQUIRE g.id IS UNIQUE;

CREATE CONSTRAINT community_id IF NOT EXISTS
FOR (c:Community) REQUIRE c.id IS UNIQUE;

-- Indexes
CREATE INDEX entity_graph IF NOT EXISTS
FOR (e:Entity) ON (e.graph_id);

CREATE INDEX entity_type IF NOT EXISTS
FOR (e:Entity) ON (e.type);

CREATE INDEX entity_name IF NOT EXISTS
FOR (e:Entity) ON (e.name);

-- Full-text search index
CREATE FULLTEXT INDEX entity_fulltext IF NOT EXISTS
FOR (e:Entity) ON EACH [e.name, e.description];

-- Vector index (Neo4j 5.x+)
CREATE VECTOR INDEX entity_embedding IF NOT EXISTS
FOR (e:Entity) ON (e.embedding)
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 1536,
    `vector.similarity_function`: 'cosine'
  }
};

-- Community summary embedding index
CREATE VECTOR INDEX community_embedding IF NOT EXISTS
FOR (c:Community) ON (c.summary_embedding)
OPTIONS {
  indexConfig: {
    `vector.dimensions`: 1536,
    `vector.similarity_function`: 'cosine'
  }
};
```

---

## 5. Manifest Storage Schema

```sql
-- ============================================
-- MANIFEST STORAGE
-- ============================================

CREATE TABLE manifests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,  -- e.g., 'production', 'local-dev'
    version INTEGER NOT NULL DEFAULT 1,
    environment VARCHAR(50),
    parent_manifest_id UUID REFERENCES manifests(id),
    content JSONB NOT NULL,  -- Parsed manifest content
    content_hash VARCHAR(64) NOT NULL,
    is_active BOOLEAN DEFAULT false,
    activated_at TIMESTAMP WITH TIME ZONE,
    created_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT manifests_name_version UNIQUE (name, version)
);

CREATE INDEX idx_manifests_name ON manifests(name);
CREATE INDEX idx_manifests_active ON manifests(is_active) WHERE is_active = true;
CREATE INDEX idx_manifests_environment ON manifests(environment);

-- Manifest deployment history
CREATE TABLE manifest_deployments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manifest_id UUID NOT NULL REFERENCES manifests(id),
    environment VARCHAR(50) NOT NULL,
    deployed_by VARCHAR(255),
    deployment_status VARCHAR(20) DEFAULT 'pending'
        CHECK (deployment_status IN ('pending', 'deploying', 'active', 'rolled_back', 'failed')),
    previous_manifest_id UUID REFERENCES manifests(id),
    rollback_reason TEXT,
    deployed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_deployments_manifest ON manifest_deployments(manifest_id);
CREATE INDEX idx_deployments_env ON manifest_deployments(environment);

-- Adapter registry persisted
CREATE TABLE adapter_registry (
    id VARCHAR(255) PRIMARY KEY,  -- e.g., 'portfolio_index.adapters.pgvector'
    port_name VARCHAR(100) NOT NULL,
    module_name VARCHAR(255) NOT NULL,
    capabilities VARCHAR(100)[] DEFAULT '{}',
    config_schema JSONB DEFAULT '{}',
    is_builtin BOOLEAN DEFAULT false,
    package_name VARCHAR(100),  -- If from external package
    package_version VARCHAR(50),
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_adapters_port ON adapter_registry(port_name);
```

---

## 6. Migration Strategy

### 6.1 Ecto Migrations

```elixir
defmodule PortfolioIndex.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    # Enable extensions
    execute "CREATE EXTENSION IF NOT EXISTS vector"
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Repositories
    create table(:repositories, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :path, :string, size: 1000, null: false
      add :remote_url, :string, size: 1000
      add :default_branch, :string, size: 100, default: "main"
      add :languages, :jsonb, default: "[]"
      add :metadata, :jsonb, default: "{}"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:repositories, [:name])
    create unique_index(:repositories, [:path])
    create index(:repositories, [:languages], using: :gin)

    # Documents
    create table(:documents, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :repo_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :path, :string, size: 1000, null: false
      add :content_hash, :string, size: 64, null: false
      add :content_type, :string, size: 100
      add :language, :string, size: 50
      add :size_bytes, :integer
      add :line_count, :integer
      add :metadata, :jsonb, default: "{}"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:documents, [:repo_id, :path])
    create index(:documents, [:repo_id])
    create index(:documents, [:content_hash])
    create index(:documents, [:language])

    # Chunks
    create table(:chunks, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :document_id, references(:documents, type: :uuid, on_delete: :delete_all), null: false
      add :index_in_document, :integer, null: false
      add :content, :text, null: false
      add :content_hash, :string, size: 64, null: false
      add :start_offset, :integer, null: false
      add :end_offset, :integer, null: false
      add :chunk_strategy, :string, size: 50
      add :metadata, :jsonb, default: "{}"
      add :inserted_at, :utc_datetime, default: fragment("NOW()")
    end

    create unique_index(:chunks, [:document_id, :index_in_document])
    create index(:chunks, [:document_id])
    create index(:chunks, [:content_hash])

    # Embeddings
    create table(:embeddings, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :chunk_id, references(:chunks, type: :uuid, on_delete: :delete_all), null: false
      add :index_id, :string, size: 100, null: false
      add :model_id, :string, size: 100, null: false
      add :model_version, :string, size: 50, null: false
      add :vector, :vector, size: 3072
      add :dimensions, :integer, null: false
      add :inserted_at, :utc_datetime, default: fragment("NOW()")
    end

    create unique_index(:embeddings, [:chunk_id, :index_id, :model_id])
    create index(:embeddings, [:chunk_id])
    create index(:embeddings, [:index_id])
    create index(:embeddings, [:model_id, :model_version])

    # Vector index for common dimensions
    execute """
    CREATE INDEX embeddings_vector_1536_idx ON embeddings
    USING hnsw ((vector::vector(1536)) vector_cosine_ops)
    WHERE dimensions = 1536
    """
  end
end

defmodule PortfolioIndex.Repo.Migrations.CreateGraphTables do
  use Ecto.Migration

  def change do
    # Graph namespaces
    create table(:graph_namespaces, primary_key: false) do
      add :id, :string, size: 255, primary_key: true
      add :type, :string, size: 50, null: false
      add :parent_id, references(:graph_namespaces, type: :string, on_delete: :nilify_all)
      add :display_name, :string, size: 255, null: false
      add :description, :text
      add :config, :jsonb, default: "{}"
      add :metadata, :jsonb, default: "{}"
      add :entity_count, :integer, default: 0
      add :edge_count, :integer, default: 0
      add :is_active, :boolean, default: true
      timestamps(type: :utc_datetime)
    end

    create index(:graph_namespaces, [:type])
    create index(:graph_namespaces, [:parent_id])

    # Graph entities
    create table(:graph_entities, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :graph_id, references(:graph_namespaces, type: :string, on_delete: :delete_all), null: false
      add :external_id, :string, size: 255
      add :type, :string, size: 100, null: false
      add :name, :string, size: 500, null: false
      add :description, :text
      add :properties, :jsonb, default: "{}"
      add :source_chunk_ids, {:array, :uuid}, default: []
      timestamps(type: :utc_datetime)
    end

    create unique_index(:graph_entities, [:graph_id, :external_id],
      where: "external_id IS NOT NULL")
    create index(:graph_entities, [:graph_id])
    create index(:graph_entities, [:graph_id, :type])
    create index(:graph_entities, [:graph_id, :name])

    execute """
    CREATE INDEX graph_entities_name_trgm_idx ON graph_entities
    USING gin(name gin_trgm_ops)
    """

    # Graph edges
    create table(:graph_edges, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :graph_id, references(:graph_namespaces, type: :string, on_delete: :delete_all), null: false
      add :from_entity_id, references(:graph_entities, type: :uuid, on_delete: :delete_all), null: false
      add :to_entity_id, references(:graph_entities, type: :uuid, on_delete: :delete_all), null: false
      add :type, :string, size: 100, null: false
      add :weight, :float, default: 1.0
      add :properties, :jsonb, default: "{}"
      add :inserted_at, :utc_datetime, default: fragment("NOW()")
    end

    create unique_index(:graph_edges, [:graph_id, :from_entity_id, :to_entity_id, :type])
    create index(:graph_edges, [:graph_id])
    create index(:graph_edges, [:graph_id, :from_entity_id])
    create index(:graph_edges, [:graph_id, :to_entity_id])
    create index(:graph_edges, [:graph_id, :type])

    # Communities
    create table(:graph_communities, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :graph_id, references(:graph_namespaces, type: :string, on_delete: :delete_all), null: false
      add :level, :integer, null: false, default: 0
      add :parent_id, references(:graph_communities, type: :uuid, on_delete: :nilify_all)
      add :entity_ids, {:array, :uuid}, null: false
      add :summary, :text
      add :summary_embedding, :vector, size: 1536
      add :algorithm, :string, size: 50
      add :metadata, :jsonb, default: "{}"
      add :inserted_at, :utc_datetime, default: fragment("NOW()")
    end

    create index(:graph_communities, [:graph_id])
    create index(:graph_communities, [:graph_id, :level])
    create index(:graph_communities, [:parent_id])

    execute """
    CREATE INDEX graph_communities_embedding_idx ON graph_communities
    USING hnsw (summary_embedding vector_cosine_ops)
    WHERE summary_embedding IS NOT NULL
    """
  end
end
```

### 6.2 Zero-Downtime Migration Strategy

```elixir
defmodule PortfolioIndex.Migration.Strategy do
  @moduledoc """
  Strategies for zero-downtime schema migrations.
  """

  @doc """
  Add column with default, then backfill, then add constraint.
  """
  def add_required_column(repo, table, column, type, default) do
    # Step 1: Add nullable column
    repo.query!("ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{column} #{type}")

    # Step 2: Backfill in batches
    backfill_column(repo, table, column, default)

    # Step 3: Add NOT NULL constraint
    repo.query!("ALTER TABLE #{table} ALTER COLUMN #{column} SET NOT NULL")

    # Step 4: Add default for new rows
    repo.query!("ALTER TABLE #{table} ALTER COLUMN #{column} SET DEFAULT #{default}")
  end

  defp backfill_column(repo, table, column, default, batch_size \\ 1000) do
    repo.query!("""
    UPDATE #{table} SET #{column} = #{default}
    WHERE #{column} IS NULL
    LIMIT #{batch_size}
    """)

    case repo.query!("SELECT COUNT(*) FROM #{table} WHERE #{column} IS NULL") do
      %{rows: [[0]]} -> :done
      _ -> backfill_column(repo, table, column, default, batch_size)
    end
  end

  @doc """
  Create index concurrently to avoid locking.
  """
  def create_index_concurrently(repo, table, columns, opts \\ []) do
    index_name = Keyword.get(opts, :name, "idx_#{table}_#{Enum.join(columns, "_")}")
    using = Keyword.get(opts, :using, "btree")

    repo.query!("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS #{index_name}
    ON #{table} USING #{using} (#{Enum.join(columns, ", ")})
    """)
  end
end
```

---

## Summary

This schema design provides:

1. **Normalized Document Storage**: Repositories → Documents → Chunks → Embeddings
2. **Multi-Index Vector Support**: Flexible embedding storage with model versioning
3. **Namespaced Graphs**: Full graph isolation with cross-graph edges
4. **Provenance Tracking**: Complete audit trail from source to derived data
5. **Manifest Persistence**: Version-controlled configuration storage
6. **Zero-Downtime Migrations**: Safe schema evolution strategies

The schema supports the full hexagonal architecture with clean separation between domain models and storage concerns.
