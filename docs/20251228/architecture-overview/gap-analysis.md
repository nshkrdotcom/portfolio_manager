# Gap Analysis: rag_ex vs Portfolio Ecosystem

**Date**: December 28, 2025
**Comparison**: rag_ex v0.4.0 vs portfolio_core/index/manager v0.2.0-0.3.0

---

## Executive Summary

This document identifies features present in the original `rag_ex` library that have not yet been ported to the new `portfolio_*` ecosystem. The analysis reveals **28 significant gaps** across 9 categories, with particular deficiencies in chunking strategies, evaluation systems, and alternative storage backends.

### Gap Severity Legend

- **Critical**: Core functionality missing that limits practical use
- **High**: Important features affecting quality or flexibility
- **Medium**: Nice-to-have features that improve developer experience
- **Low**: Edge cases or specialized functionality

---

## Summary Matrix

| Category | rag_ex Features | Portfolio Has | Gap Count | Severity |
|----------|-----------------|---------------|-----------|----------|
| Chunking Strategies | 6 | 1 | 5 | **Critical** |
| Evaluation System | 2 | 0 | 2 | **Critical** |
| Retriever Types | 4 | 4 | 0 | None |
| Reranking | 2 | 0 | 2 | **High** |
| Graph Storage | 2 | 1 | 1 | **High** |
| LLM Providers | 6 | 3 | 3 | Medium |
| Agent Tools | 4 | 4 | 0 | None |
| Pipeline Features | 5 | 4 | 1 | Low |
| Embedding Service | 3 | 1 | 2 | Medium |
| Generation Lifecycle | 1 | 0 | 1 | Medium |
| Community Detection | 1 | 0 | 1 | **High** |
| Router Strategies | 3 | 4 | 0 | None |
| **TOTAL** | - | - | **18** | - |

---

## Detailed Gap Analysis

### 1. CHUNKING STRATEGIES (Critical)

#### rag_ex Has (6 strategies):
1. **Character** - Fixed-size with word/sentence boundaries
2. **Sentence** - Split on sentence boundaries
3. **Paragraph** - Split on paragraph boundaries
4. **Recursive** - Hierarchical: paragraph → sentence → character
5. **Semantic** - Embedding-based similarity chunking
6. **FormatAware** - Code/markdown structure-aware

#### Portfolio Has (1 strategy):
1. **Recursive** - Format-aware recursive splitting

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Semantic Chunker** | Groups text by embedding similarity, creates semantically coherent chunks | Better retrieval quality, fewer context splits | **Critical** |
| **Sentence Chunker** | Simple sentence-boundary splitting | Baseline option, good for structured docs | High |
| **Paragraph Chunker** | Paragraph-aware splitting | Preserves document structure | Medium |
| **Character Chunker** | Fixed-size with smart boundaries | Predictable chunk sizes | Medium |
| **Byte Position Tracking** | Track exact byte positions in chunks | Source highlighting, reconstruction | High |

**Recommended Implementation**:
```elixir
# Add to portfolio_index/lib/portfolio_index/adapters/chunker/

defmodule PortfolioIndex.Adapters.Chunker.Semantic do
  @behaviour PortfolioCore.Ports.Chunker

  @doc """
  Groups sentences by embedding similarity.
  Starts new chunk when similarity drops below threshold.
  """
  def chunk(text, :semantic, config) do
    embedding_fn = config[:embedding_fn]
    threshold = config[:threshold] || 0.8
    max_chars = config[:max_chars] || 1000

    # Split into sentences
    # Generate embeddings for each
    # Group by similarity threshold
    # Respect max_chars limit
  end
end
```

---

### 2. EVALUATION SYSTEM (Critical)

#### rag_ex Has:
1. **RAG Triad Evaluation** (TruLens-based)
   - Context Relevance (1-5)
   - Groundedness (1-5)
   - Answer Relevance (1-5)
2. **Hallucination Detection**
   - Binary YES/NO output
   - Context-based verification

#### Portfolio Has:
- **Nothing** - No evaluation capabilities

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **RAG Triad Evaluation** | Systematic quality assessment | Cannot measure RAG quality | **Critical** |
| **Hallucination Detection** | Verify responses are grounded | Risk of incorrect answers | **Critical** |

**Recommended Implementation**:
```elixir
defmodule PortfolioManager.Evaluation do
  @moduledoc """
  RAG quality evaluation using the RAG Triad framework.
  """

  @doc """
  Evaluate a RAG generation on three dimensions:
  - Context Relevance: Is retrieved context relevant to query?
  - Groundedness: Is response supported by context?
  - Answer Relevance: Is answer relevant to query?

  Returns scores 1-5 for each dimension.
  """
  @spec evaluate_rag_triad(Generation.t(), keyword()) ::
    {:ok, %{context_relevance: 1..5, groundedness: 1..5, answer_relevance: 1..5}}
  def evaluate_rag_triad(generation, opts \\ [])

  @doc """
  Check if response contains hallucinations not supported by context.
  """
  @spec detect_hallucination(Generation.t(), keyword()) :: {:ok, boolean()}
  def detect_hallucination(generation, opts \\ [])
end
```

---

### 3. RERANKING SYSTEM (High)

#### rag_ex Has:
1. **LLM Reranker** - Uses LLM to score relevance 1-10
2. **Passthrough Reranker** - No-op baseline

#### Portfolio Has:
- **Nothing** - Reranker port defined but no implementations

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **LLM Reranker** | LLM-based relevance scoring | Significant retrieval quality improvement | **High** |
| **Cross-Encoder Reranker** | Dedicated reranking models | Fast, accurate reranking | Medium |

**Recommended Implementation**:
```elixir
defmodule PortfolioIndex.Adapters.Reranker.LLM do
  @behaviour PortfolioCore.Ports.Reranker

  def rerank(query, documents, opts) do
    prompt = build_rerank_prompt(query, documents)

    case Router.complete([%{role: :user, content: prompt}], opts) do
      {:ok, %{content: json}} ->
        scores = parse_scores(json)
        reordered = reorder_by_score(documents, scores)
        {:ok, Enum.take(reordered, opts[:top_k] || 10)}
      error -> error
    end
  end

  defp build_rerank_prompt(query, documents) do
    # Format documents with indices
    # Ask LLM to score relevance 1-10
    # Return JSON array of {doc_index, score}
  end
end
```

---

### 4. GRAPH STORAGE BACKENDS (High)

#### rag_ex Has:
1. **Pgvector** - PostgreSQL + pgvector for entity embeddings
2. **TripleStore** - RocksDB + RDF triples (high-performance)

#### Portfolio Has:
1. **Neo4j** - Native graph database

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **RocksDB TripleStore** | High-performance local graph storage | Large-scale GraphRAG, no external deps | **High** |
| **PostgreSQL Graph** | Use existing Postgres for simple graphs | No additional infrastructure | Medium |

**Note**: The TripleStore in rag_ex is designed for:
- Sub-millisecond traversals
- Large graphs (millions of nodes)
- Hybrid architecture with pgvector for vectors + RocksDB for graph
- RDF triple model for flexible schemas

---

### 5. COMMUNITY DETECTION (High)

#### rag_ex Has:
1. **Label Propagation** - Community clustering algorithm
2. **Hierarchy Building** - Multi-level communities
3. **LLM Summarization** - Generate community summaries

#### Portfolio Has:
- **Nothing** - No community detection

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Community Detection** | Cluster related entities | Enables global GraphRAG search | **High** |
| **Community Summarization** | LLM-generated cluster summaries | Higher-level semantic search | High |

**rag_ex Implementation Reference**:
```elixir
# Label propagation algorithm
def detect(graph_store, graph_id, opts) do
  max_iterations = opts[:max_iterations] || 100
  entities = graph_store.list_entities(graph_id)

  # Initialize: each entity in own community
  # Iterate: each entity adopts most common neighbor label
  # Stop: when labels stabilize or max iterations
end

def detect_and_summarize(graph_store, graph_id, opts) do
  communities = detect(graph_store, graph_id, opts)

  # For each community, gather member entities
  # Generate LLM summary of community theme
  # Store summary for global search
end
```

---

### 6. LLM PROVIDERS (Medium)

#### rag_ex Has:
1. **Gemini** - Google Gemini (embeddings + text)
2. **Claude** - Anthropic Claude
3. **Codex** - OpenAI-compatible API
4. **OpenAI** - Direct OpenAI
5. **Cohere** - Cohere provider
6. **Ollama** - Local models

#### Portfolio Has:
1. **Gemini** - Google Gemini
2. **Anthropic** - Claude
3. **OpenAI** - OpenAI (partial)

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Cohere** | Cohere API support | Access to Cohere reranker/embed | Medium |
| **Ollama** | Local model support | Offline/private deployments | Medium |
| **Nx Provider** | Local Nx/Bumblebee models | No API costs, full control | Low |

---

### 7. EMBEDDING SERVICE (Medium)

#### rag_ex Has:
1. **Embedding.Service** - GenServer with auto-batching
2. **Batch Optimization** - Automatic request batching
3. **Token Estimation** - Estimate tokens before API call

#### Portfolio Has:
1. **Direct Embedding** - Via embedder adapter

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Auto-Batching Service** | Batch multiple embed requests | Reduce API calls, cost savings | Medium |
| **Token Estimation** | Predict token usage | Cost prediction, rate limit management | Low |

**Recommended Implementation**:
```elixir
defmodule PortfolioManager.Embedding.Service do
  use GenServer

  @batch_timeout 50  # ms to wait for more texts
  @max_batch_size 100

  def embed_text(text), do: GenServer.call(__MODULE__, {:embed, text})
  def embed_texts(texts), do: GenServer.call(__MODULE__, {:embed_batch, texts})

  # Accumulate requests, batch when:
  # - Batch size reached
  # - Timeout expires
  # - Explicit flush
end
```

---

### 8. GENERATION LIFECYCLE (Medium)

#### rag_ex Has:
```elixir
%Generation{
  query: String.t(),
  query_embedding: [float()],
  retrieval_results: %{atom() => any()},
  context: String.t(),
  context_sources: [String.t()],
  prompt: String.t(),
  response: String.t(),
  evaluations: %{atom() => any()},
  halted?: boolean(),
  errors: [any()],
  ref: any()
}
```

#### Portfolio Has:
- Ad-hoc result maps, no standardized structure

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Generation Struct** | Standardized RAG lifecycle tracking | Better debugging, evaluation integration | Medium |

---

### 9. PIPELINE FEATURES (Low)

#### rag_ex Has:
1. **Sequential execution**
2. **Parallel execution**
3. **Step dependencies**
4. **ETS caching**
5. **Error handling modes** (halt/continue/retry)

#### Portfolio Has:
1. **Sequential execution** (via depends_on)
2. **Parallel execution** (independent steps)
3. **Step dependencies**
4. **ETS caching**

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Retry on Error** | Automatic step retry with backoff | Resilience to transient failures | Low |

---

### 10. RETRIEVAL UTILITIES (Low)

#### rag_ex Has:
1. **RRF Fusion** - Reciprocal Rank Fusion
2. **Deduplication** - Remove duplicate results
3. **Result Concatenation** - Merge multiple sources

#### Portfolio Has:
1. **RRF Fusion** - In Hybrid strategy

#### GAPS:

| Gap | Description | Impact | Priority |
|-----|-------------|--------|----------|
| **Standalone Deduplication** | Reusable dedup utility | Cleaner results from multiple sources | Low |
| **Multi-Source Concatenation** | Merge retrieval results | Combine graph + vector + keyword | Low |

---

## Features Portfolio Has That rag_ex Lacks

The portfolio ecosystem also has unique features:

| Feature | Description |
|---------|-------------|
| **Manifest-Driven Config** | YAML configuration with env var expansion |
| **Health Tracking** | Registry-level health and metrics |
| **Broadway Pipelines** | Production streaming with backpressure |
| **Neo4j Native** | First-class Neo4j support (vs PostgreSQL-based) |
| **CLI Tools** | mix portfolio.* tasks |
| **Domain Registry** | In-memory entity registry |
| **Multi-Tenant** | Graph isolation via graph_id |

---

## Prioritized Implementation Roadmap

### Phase 1: Critical (Weeks 1-2)
1. **Semantic Chunker** - Embedding-based chunking
2. **RAG Triad Evaluation** - Quality measurement
3. **Hallucination Detection** - Safety check

### Phase 2: High Priority (Weeks 3-4)
4. **LLM Reranker** - Relevance scoring
5. **Community Detection** - Graph clustering
6. **Byte Position Tracking** - Source highlighting
7. **Sentence/Paragraph Chunkers** - Additional strategies

### Phase 3: Medium Priority (Weeks 5-6)
8. **Generation Struct** - Lifecycle tracking
9. **Embedding Service** - Auto-batching
10. **Ollama Provider** - Local models
11. **Cohere Provider** - Additional provider

### Phase 4: Low Priority (As Needed)
12. **RocksDB TripleStore** - Alternative graph backend
13. **Pipeline Retry** - Error handling enhancement
14. **Deduplication Utility** - Standalone helper

---

## Implementation Notes

### Semantic Chunker Design

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Semantic do
  @moduledoc """
  Groups sentences by embedding similarity.

  Algorithm:
  1. Split text into sentences
  2. Generate embeddings for each sentence
  3. Calculate pairwise cosine similarity
  4. Group consecutive sentences above threshold
  5. Respect max_chars limit
  """

  @default_threshold 0.75
  @default_max_chars 1000

  def chunk(text, :semantic, config) do
    threshold = config[:threshold] || @default_threshold
    max_chars = config[:max_chars] || @default_max_chars
    embed_fn = config[:embedding_fn] || &default_embed/1

    sentences = split_sentences(text)
    embeddings = Enum.map(sentences, embed_fn)

    sentences
    |> Enum.zip(embeddings)
    |> group_by_similarity(threshold, max_chars)
    |> to_chunks()
  end

  defp group_by_similarity(sentence_embeddings, threshold, max_chars) do
    # Start with first sentence in current group
    # For each subsequent sentence:
    #   - Calculate similarity to group centroid
    #   - If similarity >= threshold and chars < max: add to group
    #   - Otherwise: start new group
  end
end
```

### Evaluation System Design

```elixir
defmodule PortfolioManager.Evaluation do
  @moduledoc """
  RAG quality evaluation based on TruLens RAG Triad.
  """

  alias PortfolioManager.Router

  @context_relevance_prompt """
  Rate how relevant the retrieved context is to the question.

  Question: {question}
  Context: {context}

  Score 1-5:
  1 = Completely irrelevant
  2 = Mostly irrelevant
  3 = Partially relevant
  4 = Mostly relevant
  5 = Highly relevant

  Return JSON: {"score": N, "reasoning": "..."}
  """

  @groundedness_prompt """
  Rate how well the response is supported by the context.

  Context: {context}
  Response: {response}

  Score 1-5:
  1 = No support (hallucination)
  2 = Minimal support
  3 = Partial support
  4 = Good support
  5 = Fully supported

  Return JSON: {"score": N, "reasoning": "..."}
  """

  @answer_relevance_prompt """
  Rate how relevant the answer is to the question.

  Question: {question}
  Answer: {answer}

  Score 1-5:
  1 = Does not address question
  2 = Tangentially related
  3 = Partially addresses
  4 = Mostly addresses
  5 = Directly and fully addresses

  Return JSON: {"score": N, "reasoning": "..."}
  """

  def evaluate_rag_triad(generation, opts \\ []) do
    with {:ok, cr} <- evaluate_context_relevance(generation, opts),
         {:ok, gr} <- evaluate_groundedness(generation, opts),
         {:ok, ar} <- evaluate_answer_relevance(generation, opts) do
      {:ok, %{
        context_relevance: cr,
        groundedness: gr,
        answer_relevance: ar,
        overall: (cr.score + gr.score + ar.score) / 3
      }}
    end
  end

  def detect_hallucination(generation, opts \\ []) do
    prompt = """
    Given only the context below, determine if the response contains
    information NOT supported by the context (hallucination).

    Context: #{generation.context}
    Response: #{generation.response}

    Answer YES if the response contains hallucinations, NO if fully grounded.
    Return JSON: {"hallucinating": true/false, "evidence": "..."}
    """

    case Router.complete([%{role: :user, content: prompt}], opts) do
      {:ok, %{content: json}} ->
        %{"hallucinating" => result} = Jason.decode!(json)
        {:ok, result}
      error -> error
    end
  end
end
```

---

## Conclusion

The portfolio ecosystem provides a solid foundation with excellent architectural principles (hexagonal architecture, manifest-driven configuration, Broadway pipelines). However, it lacks several features from rag_ex that are important for production RAG systems:

1. **Semantic chunking** - Critical for retrieval quality
2. **Evaluation system** - Critical for measuring and improving RAG
3. **Reranking** - High impact on result quality
4. **Community detection** - Enables advanced GraphRAG

Implementing these gaps would bring the portfolio ecosystem to feature parity with rag_ex while maintaining its superior architectural foundation.
