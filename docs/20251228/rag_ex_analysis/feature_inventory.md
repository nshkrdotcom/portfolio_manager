# RAG_EX COMPREHENSIVE FEATURE INVENTORY

**Version**: 0.4.0
**Repository**: https://github.com/nshkrdotcom/rag_ex
**Date Analyzed**: 2025-12-28

## Overview

This document provides a complete technical inventory of all features, modules, functions, and capabilities in the rag_ex library - a comprehensive Elixir library for building Retrieval-Augmented Generation (RAG) systems with multi-LLM support and agentic capabilities.

---

## 1. CORE RAG COMPONENTS

### 1.1 Chunking Strategies (`Rag.Chunker` behavior)

**Location**: `/lib/rag/chunker.ex`

Core behavior defining text chunking interface with implementations:

#### Module: `Rag.Chunker` (Behavior)
- **`chunk(chunker, text, opts)` :: [Chunk.t()]** - Split text into chunks
- **`chunk_ingestion(chunker, map, opts)` :: map()** - Chunk with ingestion map integration
- **`default_opts()` :: keyword()** - Optional callback for default options

#### Implementation: `Rag.Chunker.Character` (`/lib/rag/chunker/character.ex`)
- Fixed-size character chunking with smart boundaries
- **Parameters**: `max_chars` (default: 500), `overlap`
- **Output**: Chunks with byte positions (`start_byte`, `end_byte`)
- **Smart boundaries**: Prefers sentence/word boundaries over character splits

#### Implementation: `Rag.Chunker.Sentence` (`/lib/rag/chunker/sentence.ex`)
- Sentence-aware chunking using NLP tokenization
- **Parameters**: `max_chars`, `min_chars`
- **Preserves**: Sentence-level semantic units
- **Returns**: Chunks aligned to sentence boundaries

#### Implementation: `Rag.Chunker.Paragraph` (`/lib/rag/chunker/paragraph.ex`)
- Paragraph-boundary aware splitting
- **Parameters**: `max_chars`
- **Preserves**: Document structure and paragraphs

#### Implementation: `Rag.Chunker.Recursive` (`/lib/rag/chunker/recursive.ex`)
- Hierarchical chunking: paragraph → sentence → character fallback
- **Parameters**: `max_chars`, `min_chars`
- **Metadata**: Includes `hierarchy` level (`:paragraph`, `:sentence`, `:character`)
- **Advantages**: Maintains semantic structure while respecting size limits

#### Implementation: `Rag.Chunker.Semantic` (`/lib/rag/chunker/semantic.ex`)
- Embedding-based similarity grouping
- **Requirements**: `embedding_fn` (function to generate embeddings)
- **Parameters**:
  - `threshold` (default: 0.8) - Similarity cutoff for grouping
  - `max_chars` (default: 500) - Maximum chunk size
- **Algorithm**: Groups sentences by cosine similarity until threshold drops
- **Features**:
  - Cosine similarity calculation between embeddings
  - Average embeddings for chunk grouping
  - Sentence-level boundary detection

#### Implementation: `Rag.Chunker.FormatAware` (`/lib/rag/chunker/format_aware.ex`)
- Adapter to `TextChunker` library for format-aware splitting
- **Parameters**: `format` (`:markdown`, `:code`, etc.), `chunk_size`
- **Dependency**: Optional `text_chunker_ex` hex package
- **Use case**: Preserves code blocks, markdown structure, etc.

#### Data Structure: `Rag.Chunker.Chunk`
```elixir
%Chunk{
  content: String.t(),
  start_byte: integer(),  # Byte position in source
  end_byte: integer(),    # Byte position in source
  index: integer(),       # Chunk sequence number
  metadata: map()         # Custom metadata
}
```

### 1.2 Embedding Generation (`Rag.Embedding` module)

**Location**: `/lib/rag/embedding.ex`

Functions for embedding generation and management:

- **`generate_embedding(ingestion, embeddings_fn, opts)` :: map()**
  - Generates single embedding for ingestion
  - Options: `text_key` (default: `:text`), `embedding_key` (default: `:embedding`)
  - Telemetry: `[:rag, :generate_embedding]`

- **`generate_embeddings_batch(ingestions, embeddings_fn, opts)` :: [map()]**
  - Batch embedding generation for multiple texts
  - Automatically batches to provider limits
  - Telemetry: `[:rag, :generate_embeddings_batch]`

### 1.3 Retrieval Strategies (`Rag.Retriever` behavior)

**Location**: `/lib/rag/retriever.ex`

Core behavior for document retrieval with multiple implementations:

#### Behavior: `Rag.Retriever`
- **`retrieve(retriever, query, opts)` :: {:ok, [result()]} | {:error, term()}`**
  - Query: String.t() | [float()] | {[float()], String.t()}
  - Result format: `%{id, content, score, metadata}`
- **`supports_embedding?()` :: boolean()**
- **`supports_text_query?()` :: boolean()**

#### Implementation: `Rag.Retriever.Semantic` (`/lib/rag/retriever/semantic.ex`)
- Vector similarity search using pgvector L2 distance
- **Requires**: Ecto repo with VectorStore.Chunk schema
- **Parameters**:
  - Query: `[float()]` - Embedding vector
  - Options: `limit` (default: 10)
- **Score calculation**: `1.0 - distance` (similarity, 0-1 range)
- **Database**: PostgreSQL with pgvector extension

#### Implementation: `Rag.Retriever.FullText` (`/lib/rag/retriever/fulltext.ex`)
- PostgreSQL tsvector full-text search
- **Parameters**:
  - Query: `String.t()` - Text to search
  - Options: `limit` (default: 10)
- **Algorithm**:
  - Converts text to tsquery (AND'd terms)
  - Uses PostgreSQL `@@` operator
  - Ranks with `ts_rank()` function
- **Features**: Keyword matching, language-aware tokenization

#### Implementation: `Rag.Retriever.Hybrid` (`/lib/rag/retriever/hybrid.ex`)
- Reciprocal Rank Fusion (RRF) combining semantic + fulltext
- **Parameters**:
  - Query: `{[float()], String.t()}` - Tuple of (embedding, text)
  - Options: `limit` (default: 10)
- **RRF Formula**: `1.0 / (k + rank)` where k=60
- **Features**:
  - Parallel semantic and fulltext search
  - Combines rankings of documents appearing in both
  - Documents in both results score higher
  - Effective for balanced relevance

#### Implementation: `Rag.Retriever.Graph` (`/lib/rag/retriever/graph.ex`)
- Graph-enhanced retrieval with three search modes
- **Search Modes**:
  1. **Local**: Vector search on entities → graph traversal → chunk retrieval
  2. **Global**: Community summary search for high-level context
  3. **Hybrid**: Parallel local+global with RRF fusion
- **Features**:
  - BFS traversal with configurable depth
  - Entity neighborhood expansion
  - Source chunk aggregation
  - Community summary scoring
  - Parallel execution with Task.async
- **Parameters**:
  - `graph_store` - GraphStore implementation (required)
  - `vector_store` - VectorStore for chunk retrieval (required)
  - `mode` - `:local|:global|:hybrid` (default: `:local`)
  - `depth` - Traversal depth (default: 2)
  - `local_weight`, `global_weight` - RRF weights for hybrid

### 1.4 Reranking (`Rag.Reranker` behavior)

**Location**: `/lib/rag/reranker.ex`

Result reranking after retrieval:

#### Behavior: `Rag.Reranker`
- **`rerank(reranker, query, documents, opts)` :: {:ok, [document()]} | {:error, term()}`**
  - Takes retrieval results and reranks by relevance

#### Implementation: `Rag.Reranker.LLM` (`/lib/rag/reranker/llm.ex`)
- LLM-based relevance scoring
- **How it works**:
  1. Formats query and documents into prompt
  2. LLM scores each document (1-10 scale)
  3. Parses JSON response with scores
  4. Sorts by LLM-generated scores
- **Features**:
  - Configurable prompt template
  - Score normalization option
  - Default prompt with clear rubric
  - Router integration for LLM calls
- **Parameters**:
  - `top_k` - Limit to top K documents
  - `normalize_scores` - Normalize to 0-1 range
  - Custom `prompt_template` with `{query}` and `{documents}` placeholders

#### Implementation: `Rag.Reranker.Passthrough` (`/lib/rag/reranker/passthrough.ex`)
- No-op reranker for testing/benchmarking
- Returns documents unchanged

---

## 2. VECTOR STORE INTEGRATION

### 2.1 VectorStore Module (`Rag.VectorStore`)

**Location**: `/lib/rag/vector_store.ex`

Comprehensive vector storage and search operations (requires Ecto):

#### Core Functions:

**Chunk Building**:
- **`build_chunk(attrs)` :: Chunk.t()`** - Create single chunk
- **`build_chunks(attrs_list)` :: [Chunk.t()]`** - Create multiple chunks
- **`from_chunker_chunks(chunks, source)` :: [Chunk.t()]`** - Convert from Chunker output
  - Preserves byte positions in metadata
  - Tracks `start_byte`, `end_byte`, `chunk_index`

**Embedding Operations**:
- **`add_embeddings(chunks, embeddings)` :: [Chunk.t()]`**
  - Zips embeddings with chunks
  - Validates count matching
- **`prepare_for_insert(chunk)` :: map()`**
  - Converts to database-ready map
  - Adds timestamps for Ecto schemas

**Search Queries**:
- **`semantic_search_query(embedding, opts)` :: Ecto.Query.t()`**
  - Builds query for L2 distance similarity
  - Returns results ordered by distance (closest first)
  - Options: `limit` (default: 10), `min_similarity`
  - Pgvector operator: `<->` (L2 distance)

- **`fulltext_search_query(text, opts)` :: Ecto.Query.t()`**
  - PostgreSQL tsvector search
  - Converts text to tsquery with AND operators
  - Returns results ranked by `ts_rank()`
  - Options: `limit` (default: 10)

**Hybrid Search**:
- **`calculate_rrf_score(semantic_results, fulltext_results)` :: [map()]`**
  - Combines semantic and fulltext with RRF
  - Formula: `Σ 1 / (k + rank)` where k=60
  - Deduplicates by ID and combines scores
  - Returns sorted by RRF score (descending)

**Text Chunking**:
- **`chunk_text(text, opts)` :: [String.t()]`**
  - Character-based chunking with overlap
  - Smart sentence/word boundary detection
  - Options: `max_chars` (default: 500), `overlap` (default: 50)

### 2.2 Chunk Schema (`Rag.VectorStore.Chunk`)

**Location**: `/lib/rag/vector_store/chunk.ex`

Ecto schema for chunk storage (conditional on Ecto availability):

```elixir
%Chunk{
  id: integer(),
  content: String.t(),           # Main text content
  source: String.t(),            # Document source identifier
  embedding: vector(768),        # pgvector embedding
  metadata: map(),               # Custom metadata
  inserted_at: NaiveDateTime,
  updated_at: NaiveDateTime
}
```

**Features**:
- Pgvector support via `Pgvector` type
- Full-text search index on content
- Semantic search index on embedding (IVFFlat with 100 lists)
- Metadata storage for custom fields

---

## 3. LLM PROVIDER INTEGRATION

### 3.1 Provider Interface (`Rag.Ai.Provider` behavior)

**Location**: `/lib/rag/ai/provider.ex`

Defines LLM provider contract:

- **`new(attrs)` :: struct()** - Initialize provider
- **`generate_embeddings(provider, texts, opts)` :: {:ok, [embedding()]} | {:error, term()}`**
  - texts: `[String.t()]` - Multiple texts to embed
  - Returns: List of embedding vectors
- **`generate_text(provider, prompt, opts)` :: {:ok, response()} | {:error, term()}`**
  - response: `String.t() | Enumerable.t()` (supports streaming)

### 3.2 Provider Capabilities (`Rag.Ai.Capabilities`)

**Location**: `/lib/rag/ai/capabilities.ex`

Capability registry and selection helpers:

**Functions**:
- **`get(provider)` :: map() | nil`** - Get provider capabilities
- **`all()` :: map()`** - Get all providers
- **`available()` :: [{atom(), map()}]`** - Providers with loaded modules and credentials
- **`with_capability(capability)` :: [{atom(), map()}]`** - Filter by capability
- **`best_for(task)` :: atom()`** - Select best provider for task type
- **`check_available(module)` :: boolean()`** - Check if provider module is loaded
- **`default_provider()` :: atom()`** - Get first available provider
- **`can_handle?(provider, capability)` :: boolean()`** - Check capability support

**Task Types for `best_for()`**:
- `:embeddings` → Gemini
- `:code_generation` → Codex
- `:code_review` → Codex
- `:analysis` → Claude
- `:writing` → Claude
- `:long_context` → Gemini
- `:structured_output` → Codex
- `:agentic` → Claude
- `:reasoning` → Claude
- `:multimodal` → Gemini
- `:cost` → Gemini
- `:speed` → Gemini
- `:safety` → Claude

---

## 4. ROUTING & REQUEST ORCHESTRATION

### 4.1 Router Module (`Rag.Router`)

**Location**: `/lib/rag/router.ex`

Multi-provider router with pluggable strategies:

**Core Functions**:
- **`new(opts)` :: {:ok, Router.t()} | {:error, term()}`**
  - Options:
    - `providers: [atom()]` - Provider list (required unless auto_detect)
    - `strategy: atom()` - `:fallback|:round_robin|:specialist|:auto` (default: auto)
    - `auto_detect: boolean()` - Auto-detect available providers
    - `fallback_order: [atom()]` - Fallback provider order

- **`route(router, type, prompt, opts)` :: {:ok, atom(), Router.t()} | {:error, term()}`**
  - Selects provider based on strategy
  - Returns selected provider atom

- **`execute(router, type, prompt, opts)` :: {:ok, response, Router.t()} | {:error, term()}`**
  - Automatically selects provider and executes
  - Type: `:text | :embeddings`
  - Retries with fallbacks on failure

- **`report_result(router, provider, result)` :: Router.t()`**
  - Updates strategy state based on success/failure
  - Tracks provider performance

- **`next_provider(router, failed_provider)` :: {:ok, atom(), Router.t()} | {:error, term()}`**
  - Gets next provider after failure

- **`available_providers(router)` :: [atom()]`**
  - Returns currently available providers

### 4.2 Routing Strategies

#### Fallback Strategy (`Rag.Router.Fallback`)
- Try providers in order until success
- Linear fallback through configured order
- Tracks failures per provider
- Max failure threshold before marking unavailable

#### Round Robin Strategy (`Rag.Router.RoundRobin`)
- Distribute load across providers
- Cycles through providers in order
- Balances request distribution
- Falls back on provider failure

#### Specialist Strategy (`Rag.Router.Specialist`)
- Route based on task type
- Task mappings: `:embeddings` → Gemini, `:code_generation` → Codex, etc.
- Task inference from prompt content
- Keyword detection for code vs. analysis tasks

---

## 5. PIPELINE ARCHITECTURE

### 5.1 Pipeline Module (`Rag.Pipeline`)

**Location**: `/lib/rag/pipeline.ex`

Composable RAG workflow orchestration:

**Pipeline Structure**:
```elixir
%Pipeline{
  name: atom(),
  description: String.t() | nil,
  steps: [Step.t()],
  config: map(),
  metadata: map()
}
```

**Core Functions**:
- **`new(name, opts)` :: Pipeline.t()`**
- **`add_step(pipeline, step)` :: Pipeline.t()`**
- **`execute(pipeline, input, opts)` :: {:ok, result, Context.t()} | {:error, term()}`**

### 5.2 Pipeline Step (`Rag.Pipeline.Step`)

```elixir
%Step{
  name: atom(),                           # Step identifier
  module: module(),                       # Module with function
  function: atom(),                       # Function to call
  args: keyword(),                        # Arguments to pass
  inputs: list(atom()) | nil,            # Dependency step names
  parallel: boolean(),                    # Run in parallel
  on_error: :halt | :continue | {:retry, n},
  cache: boolean(),                       # Cache result
  timeout: non_neg_integer() | nil
}
```

### 5.3 Pipeline Context (`Rag.Pipeline.Context`)

```elixir
%Context{
  input: any(),
  query: String.t() | nil,
  query_embedding: [float()] | nil,
  retrieval_results: any(),
  reranked_results: any(),
  context_text: String.t() | nil,
  response: String.t() | nil,
  metadata: map(),
  errors: [any()]
}
```

---

## 6. AGENT FRAMEWORK

### 6.1 Agent Module (`Rag.Agent.Agent`)

**Location**: `/lib/rag/agent/agent.ex`

**Structure**:
```elixir
%Agent{
  session: Session.t(),
  registry: Registry.t(),
  provider: struct(),
  max_iterations: pos_integer()
}
```

**Core Functions**:
- **`new(opts)` :: Agent.t()`**
- **`process(agent, query)` :: {:ok, response, Agent.t()} | {:error, term()}`**
- **`process_with_tools(agent, query)` :: {:ok, response, Agent.t()} | {:error, term()}`**
- **`parse_tool_call(response)` :: {:ok, tool_name, args} | {:none, response}`**
- **`execute_tool(registry, name, args, context)` :: {:ok, result} | {:error, term()}`**
- **`with_context(agent, key, value)` :: Agent.t()`**
- **`get_history(agent)` :: [Session.message()]`**
- **`clear_history(agent)` :: Agent.t()`**

### 6.2 Session Management (`Rag.Agent.Session`)

**Structure**:
```elixir
%Session{
  id: String.t(),                    # Unique session ID (UUID)
  messages: [message()],             # Conversation history
  context: map(),                    # Persistent context
  metadata: map(),                   # Custom metadata
  created_at: integer()              # Creation timestamp (ms)
}
```

**Message Format**:
```elixir
%{
  role: :user | :assistant | :system | :tool,
  content: String.t(),
  timestamp: integer(),
  tool_name: String.t() | nil,
  error: term() | nil
}
```

**Core Functions**:
- **`new(opts)` :: Session.t()`**
- **`add_message(session, role, content)` :: Session.t()`**
- **`add_tool_result(session, tool_name, result)` :: Session.t()`**
- **`messages(session)` :: [message()]`**
- **`context(session)` :: map()`**
- **`set_context(session, key, value)` :: Session.t()`**
- **`merge_context(session, map)` :: Session.t()`**
- **`get_context(session, key, default)` :: term()`**
- **`message_count(session)` :: non_neg_integer()`**
- **`last_messages(session, n)` :: [message()]`**
- **`clear_messages(session)` :: Session.t()`**
- **`to_llm_messages(session)` :: [map()]`**
- **`token_estimate(session)` :: non_neg_integer()`**

### 6.3 Tool System (`Rag.Agent.Tool`)

**Callbacks**:
- **`name()` :: String.t()`**
- **`description()` :: String.t()`**
- **`parameters()` :: map()`** (JSON Schema)
- **`execute(args, context)` :: {:ok, result} | {:error, term()}`**

**Context Available to Tools**:
- `:session_id`
- `:user_id`
- `:repo`
- `:router`
- Custom context from agent

---

## 7. GRAPH CAPABILITIES (KNOWLEDGE GRAPHS)

### 7.1 GraphStore Behaviour (`Rag.GraphStore`)

**Location**: `/lib/rag/graph_store.ex`

**Node Operations**:
- **`create_node(store, node_attrs)` :: {:ok, node} | {:error, term()}`**
- **`get_node(store, id)` :: {:ok, node} | {:error, :not_found}`**

**Edge Operations**:
- **`create_edge(store, edge_attrs)` :: {:ok, edge} | {:error, term()}`**

**Graph Operations**:
- **`find_neighbors(store, node_id, opts)` :: {:ok, [node]} | {:error, term()}`**
- **`traverse(store, start_id, opts)` :: {:ok, [node]} | {:error, term()}`**
- **`vector_search(store, embedding, opts)` :: {:ok, [node]} | {:error, term()}`**

**Community Operations**:
- **`create_community(store, attrs)` :: {:ok, community} | {:error, term()}`**
- **`get_community_members(store, community_id)` :: {:ok, [node]} | {:error, term()}`**
- **`update_community_summary(store, community_id, summary)` :: {:ok, community} | {:error, term()}`**

### 7.2 GraphRAG Components

**Entity Extraction** (`Rag.GraphRAG.Extractor`):
- `extract(text, opts)` - Full extraction (entities + relationships)
- `extract_entities(text, opts)` - Entities only
- `extract_relationships(text, entities, opts)` - Relationships between entities
- `resolve_entities(entities, opts)` - Consolidate duplicates
- `extract_batch(texts, opts)` - Concurrent batch extraction

**Community Detection** (`Rag.GraphRAG.CommunityDetector`):
- `detect(store, opts)` - Label propagation algorithm

---

## 8. EVALUATION FRAMEWORK

### 8.1 Evaluation Module (`Rag.Evaluation`)

**Location**: `/lib/rag/evaluation.ex`

**Functions**:

- **`evaluate_rag_triad(generation, response_function)` :: Generation.t()`**
  - Evaluates three dimensions:
    1. **Context Relevance**: Is retrieved context relevant to query?
    2. **Groundedness**: Is response supported by context?
    3. **Answer Relevance**: Is answer relevant to query?
  - Scores: 1-5 scale for each dimension

- **`detect_hallucination(generation, response_function)` :: Generation.t()`**
  - Detects if response contains hallucinations
  - Output: Boolean (`true` = hallucination detected)

---

## 9. GENERATION STRUCT

**Location**: `/lib/rag/generation.ex`

Main RAG data structure:

```elixir
%Generation{
  query: String.t(),
  query_embedding: [float()] | nil,
  retrieval_results: [map()] | nil,
  context: String.t() | nil,
  context_sources: [map()] | nil,
  prompt: String.t() | nil,
  response: String.t() | nil,
  evaluations: map(),
  halted?: boolean(),
  errors: [any()]
}
```

---

## 10. SUMMARY OF CAPABILITIES

### Core RAG
- 6 chunking strategies (character, sentence, paragraph, recursive, semantic, format-aware)
- 4 retriever types (semantic, fulltext, hybrid, graph)
- 2 reranker types (LLM-based, passthrough)
- 4 LLM providers (Gemini, Claude, Codex, Ollama)
- 3 routing strategies (fallback, round-robin, specialist)
- Complete vector store with pgvector backend
- Pipeline system with parallel execution

### Knowledge Graphs
- GraphRAG implementation with entity extraction
- 2 graph backends (PostgreSQL, TripleStore/RocksDB)
- Community detection with label propagation
- 3 graph search modes (local, global, hybrid)
- Graph traversal (BFS/DFS)

### Agents
- Multi-turn conversation management
- Tool-using agent loop
- 4 built-in tools (search, read, context, analyze)
- Custom tool framework
- Session memory management

### Quality
- RAG Triad evaluation (context relevance, groundedness, answer relevance)
- Hallucination detection
- Configurable evaluation via LLM prompts

### Infrastructure
- Comprehensive telemetry
- Type safety with dialyzer
- Conditional Ecto/pgvector support
- Error handling with provider failover
- ETS-backed caching

---

**Document Generated**: 2025-12-28
**rag_ex Version**: 0.4.0
**Analysis Depth**: Comprehensive - All modules, functions, and behaviors catalogued
