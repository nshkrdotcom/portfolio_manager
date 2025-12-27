# Pipelines, Chunking, Embeddings, and Ops

## Ingestion Pipeline (Docs and Code)

Recommended steps:

1. Discover sources (repos, docs, README, code paths)
2. Normalize text (strip front matter, remove boilerplate)
3. Chunk (strategy per manifest)
4. Embed (model per manifest)
5. Store chunks in vector store
6. Extract entities/relationships (optional)
7. Update graph store
8. Summarize per doc and per repo
9. Persist summary in portfolio repo

### Incremental Ingestion

- Track file hashes and skip unchanged files
- Store ingestion version and embed model used
- Support partial re-embedding for model upgrades

## Chunking Strategy Matrix

- Character: predictable size, low quality
- Sentence: better boundaries, moderate cost
- Paragraph: good for docs, good coherence
- Recursive: best for large docs
- Semantic: expensive but can yield high quality

Manifest should allow per-content chunking rules.

## Embedding Strategy

- Support multiple embedding models in parallel
- Store embedding_model and dimensions in metadata
- Allow per-query selection (fast vs accurate)
- Normalize embeddings if model requires it

## Retrieval Pipeline

Recommended pipeline steps:

1. Embed query
2. Run semantic and full-text retrieval in parallel
3. Apply hybrid fusion (RRF)
4. Optional graph expansion (local and global)
5. Rerank with LLM or cross-encoder
6. Build context and answer

### Evaluation Loop

- Store query + retrieved chunks + final answer
- Track relevance metrics and drift over time
- Use offline evaluation to tune chunking and retriever weights

## Agent Integration

Agents should not directly query DB. They should call tools that
map to pipeline endpoints:

- search_docs
- search_graph
- get_context
- retrieve_repo

This keeps agent behavior stable even when backends change.

## Observability

- Emit telemetry for pipeline steps
- Track costs per embedding and per rerank call
- Store query traces and retrieval provenance
- Collect per-adapter latency and error budgets

## Caching Strategy

- Cache embeddings for repeated queries
- Cache intermediate retrieval results for repeated queries
- Cache graph traversal for large graphs
- Cache community summaries and graph expansions

## Failure Handling

- Ingestion failures should be isolated by repo
- Partial ingestion is acceptable with clear error reporting
- Embedding provider failures should degrade gracefully
- If graph store is unavailable, fall back to vector + fulltext
