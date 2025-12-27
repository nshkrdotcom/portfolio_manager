# Storage Topology: Relational, Vector, Graph, Triple Store

## Goals

- Support many vector indexes, possibly with different embedding models.
- Support multiple graphs (disconnected or partially connected).
- Preserve provenance for every fact and chunk.
- Allow both local and cloud-scale storage.

## Relational Core (Postgres)

Use Postgres as the default operational database:

- doc_files: file-level metadata and hashes
- doc_chunks: chunk content and embedding references
- rag_chunks: current rag_ex table (can be replaced by doc_chunks)
- repo_metadata: repo-level attributes

This provides a stable, queryable baseline even if vector/graph backends change.

## Vector Store Strategy

### Multi-Index Design

- Each vector index has an index_id and embedding_model.
- Chunks can be stored in multiple indexes in parallel.
- A retrieval query chooses which index to hit via manifest config.
- Store embedding_dimensions to avoid mismatched queries.

### Backends

- Default: Postgres + pgvector
- Scale-out: Qdrant, Pinecone, Weaviate
- Local embedded: sqlite-vss (optional), but not for large data

### Index Types

- pgvector ivfflat: fast build, limited by dimensions (<= 2000)
- pgvector HNSW: better recall for higher dimensions
- External ANN: Qdrant/Weaviate for large corpus

### Metadata

- Store repo_id, path, sha256, chunk_index, embedding_model, and graph_id.
- This enables filtered retrieval and provenance display.
- Store embedding_version to support re-embedding strategies.

## Graph Store Strategy

### Multi-Graph Support

Graph data should include graph_id or namespace:

- graph_entities: {id, graph_id, type, name, properties, embedding, source_chunk_ids}
- graph_edges: {id, graph_id, from_id, to_id, type, weight, properties}
- graph_communities: {id, graph_id, level, summary, entity_ids}

A graph_id is required for:

- per-repo graphs
- per-domain graphs
- meta-graphs connecting other graphs

### Multi-Graph Queries

- local graph traversal within graph_id
- cross-graph traversal via explicit meta edges
- graph-of-graphs indexes for large ecosystems

### Graph of Graphs

- Represent each graph as a node in a meta-graph
- Connect graphs with edges such as depends_on, shares_schema, uses_library
- Retrieval can traverse meta-graph to expand the search scope

### Backends

- Default: Postgres + pgvector (rag_ex GraphStore.Pgvector)
- Scale-out: Neo4j for large graphs
- Triple store: RocksDB-backed subject/predicate/object store

## Context Graphs (Quadruples)

The system should store facts as quadruples:

- subject, predicate, object, context

Context contains:

- graph_id
- source_path
- repo_id
- chunk_id
- extractor_version
- confidence
- timestamps

Use this to build explicit provenance chains (fact -> chunk -> file -> repo).

This supports provenance and allows the same triple to exist in multiple contexts.

## Triple Store Option

rag_ex already includes Rag.GraphStore.TripleStore, which wraps the
triple_store library (RocksDB + SPARQL + OWL). That is the wrong layer for
a hex architecture and must be moved behind the index layer.

Correct placement:

- Move or wrap the triple_store integration into portfolio_index as a
  GraphStore adapter.
- Keep Rag.GraphStore behavior in rag_ex, but do not couple rag_ex to RocksDB.
- If SPARQL or OWL reasoning is required, add a dedicated RdfStorePort to
  expose those features; keep GraphStorePort focused on property-graph access.

Implementation details:

- Primary index: (graph_id, subject, predicate, object)
- Secondary indexes: SPO, POS, OSP for fast queries
- Store context and evidence metadata in a side column family
- Provide a graph_id namespace for multi-graph separation
- Add a batch ingestion pipeline with compaction-aware writes

## Recommended Storage Path

1) Start with Postgres + pgvector for both vectors and graph storage.
2) Add graph_id columns to support multiple graphs.
3) If graph scale grows beyond Postgres, add Neo4j adapter.
4) If triple store is needed, add RocksDB adapter as a GraphStorePort.
5) Add a VectorIndex registry to route queries to the right backend.
