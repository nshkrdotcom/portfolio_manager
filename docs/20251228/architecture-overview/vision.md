# Portfolio Ecosystem: Vision & Ideal Feature Set

**Date**: December 28, 2025
**Status**: Strategic Planning Document
**Scope**: Foundational capabilities for a best-in-class RAG ecosystem

---

## Executive Summary

This document outlines the ideal feature set for the Portfolio Ecosystem, envisioning it as a comprehensive, production-grade platform for building intelligent code analysis, knowledge management, and RAG-powered applications. The vision encompasses not just filling gaps from rag_ex, but creating a differentiated, world-class system.

---

## Core Design Principles

### 1. Hexagonal Architecture First
Every component should be a pluggable adapter implementing a well-defined port (behaviour). No hardcoded dependencies on specific databases, LLM providers, or storage backends.

### 2. Configuration Over Code
System behavior should be primarily driven by YAML manifests with environment variable support. Developers should be able to deploy completely different architectures without code changes.

### 3. Observable by Default
Every operation emits telemetry. Built-in support for metrics, tracing, and logging that integrates with standard observability stacks.

### 4. Graceful Degradation
The system should continue functioning when components fail. Fallback strategies, circuit breakers, and health monitoring are first-class features.

### 5. Developer Experience
Clear APIs, comprehensive documentation, helpful error messages, and intuitive CLI tools. Getting started should take minutes, not hours.

---

## Feature Categories

1. [Storage & Indexing](#1-storage--indexing)
2. [Chunking & Preprocessing](#2-chunking--preprocessing)
3. [Embedding & Vectorization](#3-embedding--vectorization)
4. [Retrieval Strategies](#4-retrieval-strategies)
5. [Knowledge Graphs](#5-knowledge-graphs)
6. [LLM Integration](#6-llm-integration)
7. [Agent Framework](#7-agent-framework)
8. [Evaluation & Quality](#8-evaluation--quality)
9. [Pipeline Orchestration](#9-pipeline-orchestration)
10. [Developer Tools](#10-developer-tools)
11. [Enterprise Features](#11-enterprise-features)
12. [Integrations](#12-integrations)

---

## 1. Storage & Indexing

### Vector Storage

| Feature | Status | Description |
|---------|--------|-------------|
| **Pgvector Adapter** | ✅ Exists | PostgreSQL + pgvector |
| **HNSW Indexes** | ✅ Exists | Approximate nearest neighbor |
| **IVFFlat Indexes** | ✅ Exists | Inverted file indexing |
| **Flat Indexes** | ✅ Exists | Exact search |
| **Qdrant Adapter** | 🎯 Vision | Cloud-native vector DB |
| **Pinecone Adapter** | 🎯 Vision | Managed vector service |
| **Weaviate Adapter** | 🎯 Vision | GraphQL vector DB |
| **Milvus Adapter** | 🎯 Vision | Distributed vector DB |
| **SQLite-Vec Adapter** | 🎯 Vision | Embedded vector DB |
| **Redis Vector Adapter** | 🎯 Vision | Redis Stack vectors |

### Document Storage

| Feature | Status | Description |
|---------|--------|-------------|
| **PostgreSQL Store** | ✅ Exists | JSONB metadata |
| **Content Hashing** | ✅ Exists | SHA256 deduplication |
| **S3 Adapter** | 🎯 Vision | Cloud object storage |
| **MinIO Adapter** | 🎯 Vision | Self-hosted S3-compatible |
| **SQLite Adapter** | 🎯 Vision | Embedded local storage |
| **Versioning** | 🎯 Vision | Document version history |

### Ideal Vector Store Interface

```elixir
defmodule PortfolioCore.Ports.VectorStore do
  @callback create_index(index_id, config) :: :ok | {:error, term()}
  @callback delete_index(index_id) :: :ok | {:error, term()}

  # Basic operations
  @callback store(index_id, id, vector, metadata) :: :ok | {:error, term()}
  @callback store_batch(index_id, items) :: {:ok, count} | {:error, term()}
  @callback get(index_id, id) :: {:ok, item} | {:error, term()}
  @callback delete(index_id, id) :: :ok | {:error, term()}

  # Search operations
  @callback search(index_id, vector, k, opts) :: {:ok, results} | {:error, term()}
  @callback search_with_filter(index_id, vector, k, filter, opts) :: {:ok, results}

  # Advanced operations (vision)
  @callback upsert(index_id, id, vector, metadata) :: :ok | {:error, term()}
  @callback bulk_delete(index_id, ids) :: {:ok, count} | {:error, term()}
  @callback update_metadata(index_id, id, metadata) :: :ok | {:error, term()}

  # Index management
  @callback index_stats(index_id) :: {:ok, stats} | {:error, term()}
  @callback optimize_index(index_id) :: :ok | {:error, term()}
  @callback rebuild_index(index_id, config) :: :ok | {:error, term()}

  # Filtering (vision)
  @callback create_filter_index(index_id, field, type) :: :ok
  @callback supported_filter_types() :: [atom()]
end
```

---

## 2. Chunking & Preprocessing

### Chunking Strategies

| Feature | Status | Description |
|---------|--------|-------------|
| **Recursive Chunker** | ✅ Exists | Format-aware hierarchy |
| **Semantic Chunker** | 🔴 Gap | Embedding similarity grouping |
| **Sentence Chunker** | 🔴 Gap | Sentence boundaries |
| **Paragraph Chunker** | 🔴 Gap | Paragraph boundaries |
| **Character Chunker** | 🔴 Gap | Fixed-size with smart breaks |
| **Code Chunker** | 🎯 Vision | AST-aware code splitting |
| **Markdown Chunker** | 🎯 Vision | Heading-based sections |
| **Sliding Window** | 🎯 Vision | Overlapping fixed windows |
| **Parent-Child** | 🎯 Vision | Hierarchical chunk relationships |

### Preprocessing Pipeline

| Feature | Status | Description |
|---------|--------|-------------|
| **Format Detection** | ✅ Exists | Auto-detect file types |
| **Text Extraction** | 🎯 Vision | PDF, DOCX, HTML, etc. |
| **Code Parsing** | 🎯 Vision | AST extraction for languages |
| **Metadata Extraction** | 🎯 Vision | Auto-extract from content |
| **Language Detection** | 🎯 Vision | Identify code/natural language |
| **Cleaning Pipeline** | 🎯 Vision | Remove boilerplate, normalize |

### Ideal Semantic Chunker

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Semantic do
  @moduledoc """
  Groups text by embedding similarity to create semantically coherent chunks.

  ## Algorithm

  1. Split text into sentences
  2. Generate embeddings for each sentence
  3. Build similarity matrix (or rolling window)
  4. Identify breakpoints where similarity drops
  5. Group sentences between breakpoints
  6. Merge small groups, split large ones

  ## Configuration

  - `threshold` - Similarity threshold (default: 0.75)
  - `max_chars` - Maximum chunk size (default: 1000)
  - `min_chars` - Minimum chunk size (default: 100)
  - `embedding_fn` - Function to generate embeddings
  - `window_size` - Rolling similarity window (default: 3)
  """

  @behaviour PortfolioCore.Ports.Chunker

  defstruct [:threshold, :max_chars, :min_chars, :embedding_fn, :window_size]

  def chunk(text, format, config) do
    sentences = split_sentences(text)
    embeddings = batch_embed(sentences, config.embedding_fn)

    breakpoints = find_semantic_breakpoints(embeddings, config)
    groups = group_sentences(sentences, breakpoints)

    groups
    |> merge_small_groups(config.min_chars)
    |> split_large_groups(config.max_chars)
    |> build_chunks_with_positions(text)
  end

  defp find_semantic_breakpoints(embeddings, config) do
    embeddings
    |> Enum.chunk_every(config.window_size, 1, :discard)
    |> Enum.with_index()
    |> Enum.filter(fn {window, _idx} ->
      avg_similarity(window) < config.threshold
    end)
    |> Enum.map(fn {_, idx} -> idx + config.window_size end)
  end
end
```

### Code-Aware Chunking (Vision)

```elixir
defmodule PortfolioIndex.Adapters.Chunker.CodeAware do
  @moduledoc """
  AST-aware chunking for source code.

  Preserves:
  - Complete function definitions
  - Module boundaries
  - Class/struct definitions
  - Import/require blocks
  - Documentation strings

  Uses tree-sitter or language-specific parsers.
  """

  def chunk(code, :elixir, config) do
    {:ok, ast} = Code.string_to_quoted(code)

    ast
    |> extract_top_level_forms()
    |> group_related_forms(config.max_chars)
    |> build_chunks_with_context()
  end

  defp extract_top_level_forms(ast) do
    # Extract: defmodule, def, defp, defmacro, @doc, @moduledoc
    # Preserve relationships between docs and functions
  end
end
```

---

## 3. Embedding & Vectorization

### Embedding Providers

| Feature | Status | Description |
|---------|--------|-------------|
| **Gemini Embeddings** | ✅ Exists | text-embedding-004 |
| **OpenAI Embeddings** | ⚠️ Partial | text-embedding-3-* |
| **Cohere Embeddings** | 🔴 Gap | embed-v3 |
| **Voyage Embeddings** | 🎯 Vision | voyage-code-2 |
| **Nomic Embeddings** | 🎯 Vision | nomic-embed-text |
| **Local Embeddings (Nx)** | 🔴 Gap | Bumblebee models |
| **Ollama Embeddings** | 🔴 Gap | Local via Ollama |
| **Sentence Transformers** | 🎯 Vision | SBERT models |

### Embedding Service Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Auto-Batching** | 🔴 Gap | Accumulate and batch API calls |
| **Rate Limiting** | ✅ Exists | Hammer integration |
| **Caching** | 🎯 Vision | Cache embeddings by content hash |
| **Dimensionality Reduction** | 🎯 Vision | PCA/UMAP for storage |
| **Normalization** | 🎯 Vision | L2 normalization |
| **Multi-Vector** | 🎯 Vision | ColBERT-style late interaction |

### Ideal Embedding Service

```elixir
defmodule PortfolioManager.Embedding.Service do
  @moduledoc """
  Managed embedding service with auto-batching and caching.

  ## Features

  - Automatic request batching (reduces API costs)
  - Content-hash-based caching (never embed same text twice)
  - Rate limiting with backpressure
  - Multiple provider support with fallback
  - Async batch processing
  """

  use GenServer

  defstruct [
    :provider,
    :cache,
    :rate_limiter,
    :batch_size,
    :batch_timeout,
    :pending_requests
  ]

  # Public API
  def embed(text, opts \\ [])
  def embed_batch(texts, opts \\ [])
  def embed_async(texts, callback, opts \\ [])

  # With caching
  def embed_with_cache(text, opts \\ []) do
    hash = content_hash(text)

    case Cache.get(:embeddings, hash) do
      {:ok, embedding} -> {:ok, embedding}
      :miss ->
        {:ok, embedding} = embed(text, opts)
        Cache.put(:embeddings, hash, embedding, ttl: :infinity)
        {:ok, embedding}
    end
  end

  # Batch optimization
  defp handle_cast({:embed_request, text, from}, state) do
    state = add_to_batch(state, text, from)

    if batch_ready?(state) do
      flush_batch(state)
    else
      schedule_batch_timeout(state)
      {:noreply, state}
    end
  end
end
```

---

## 4. Retrieval Strategies

### Current Strategies

| Feature | Status | Description |
|---------|--------|-------------|
| **Hybrid (RRF)** | ✅ Exists | Vector + keyword fusion |
| **Self-RAG** | ✅ Exists | Self-critique retrieval |
| **Agentic** | ✅ Exists | Tool-based exploration |
| **Graph-RAG** | ✅ Exists | Entity + graph traversal |

### Vision Strategies

| Feature | Status | Description |
|---------|--------|-------------|
| **HyDE** | 🎯 Vision | Hypothetical Document Embeddings |
| **RAPTOR** | 🎯 Vision | Recursive Abstractive Processing |
| **Multi-Query** | 🎯 Vision | Generate multiple query variations |
| **Step-Back** | 🎯 Vision | Abstract to broader concepts |
| **Corrective RAG** | 🎯 Vision | Web search fallback |
| **Adaptive RAG** | 🎯 Vision | Dynamic strategy selection |
| **Long-Context** | 🎯 Vision | Stuff entire context |
| **Map-Reduce** | 🎯 Vision | Parallel chunk processing |

### HyDE Implementation (Vision)

```elixir
defmodule PortfolioIndex.RAG.Strategies.HyDE do
  @moduledoc """
  Hypothetical Document Embeddings (HyDE)

  Instead of embedding the query directly, generate a hypothetical
  answer and embed that. This often produces better retrieval
  because the hypothetical answer is more similar to actual documents.

  ## Algorithm

  1. Generate hypothetical answer using LLM
  2. Embed the hypothetical answer
  3. Search with hypothetical embedding
  4. Optionally: also search with query embedding
  5. Fuse results if using both

  ## When to Use

  - Questions where direct query embedding underperforms
  - Domain-specific technical queries
  - When you want retrieval to match answer-style text
  """

  @behaviour PortfolioIndex.RAG.Strategy

  def retrieve(query, context, opts) do
    # Generate hypothetical answer
    hypothetical = generate_hypothetical_answer(query, opts)

    # Embed hypothetical
    {:ok, hypo_embedding} = embed(hypothetical, context)

    # Search with hypothetical embedding
    {:ok, hypo_results} = search(context.index_id, hypo_embedding, opts[:k] * 2)

    # Optionally fuse with direct query results
    if opts[:include_direct_query] do
      {:ok, query_embedding} = embed(query, context)
      {:ok, query_results} = search(context.index_id, query_embedding, opts[:k])
      fuse_results(hypo_results, query_results, opts)
    else
      {:ok, Enum.take(hypo_results, opts[:k])}
    end
  end

  defp generate_hypothetical_answer(query, opts) do
    prompt = """
    Write a detailed paragraph that would answer this question.
    Do not say "I don't know" - provide a plausible, detailed answer
    as if you had the information.

    Question: #{query}

    Hypothetical answer:
    """

    {:ok, %{content: answer}} = Router.complete([%{role: :user, content: prompt}])
    answer
  end
end
```

### Multi-Query RAG (Vision)

```elixir
defmodule PortfolioIndex.RAG.Strategies.MultiQuery do
  @moduledoc """
  Generate multiple query variations for comprehensive retrieval.

  ## Algorithm

  1. Generate N query variations using LLM
  2. Embed and search for each variation
  3. Fuse all results using RRF
  4. Deduplicate

  ## Query Variations

  - Rephrasings
  - Different perspectives
  - More specific versions
  - More general versions
  - Related questions
  """

  def retrieve(query, context, opts) do
    num_queries = opts[:num_queries] || 3

    # Generate variations
    variations = generate_query_variations(query, num_queries)

    # Search for each variation in parallel
    results =
      [query | variations]
      |> Task.async_stream(&search_single(&1, context, opts))
      |> Enum.map(fn {:ok, result} -> result end)

    # Fuse all results
    fused = reciprocal_rank_fusion(results, opts[:rrf_k] || 60)

    {:ok, Enum.take(fused, opts[:k])}
  end
end
```

### Adaptive RAG (Vision)

```elixir
defmodule PortfolioIndex.RAG.Strategies.Adaptive do
  @moduledoc """
  Dynamically select the best RAG strategy based on query analysis.

  ## Decision Factors

  - Query complexity (simple fact vs. multi-hop reasoning)
  - Query type (definition, how-to, comparison, etc.)
  - Available context quality
  - Previous strategy performance

  ## Strategy Selection

  | Query Type | Recommended Strategy |
  |------------|---------------------|
  | Simple fact | Hybrid |
  | Code-related | Graph-RAG |
  | Complex reasoning | Agentic |
  | Quality-critical | Self-RAG |
  | Unclear/broad | Multi-Query |
  """

  def retrieve(query, context, opts) do
    # Analyze query
    analysis = analyze_query(query)

    # Select strategy
    strategy = select_strategy(analysis, context)

    # Execute chosen strategy
    strategy.retrieve(query, context, opts)
  end

  defp analyze_query(query) do
    prompt = """
    Analyze this query and return JSON:
    {
      "complexity": "simple" | "moderate" | "complex",
      "type": "fact" | "how_to" | "comparison" | "code" | "exploration",
      "requires_reasoning": boolean,
      "domain_specific": boolean
    }

    Query: #{query}
    """

    {:ok, %{content: json}} = Router.complete([%{role: :user, content: prompt}])
    Jason.decode!(json)
  end

  defp select_strategy(analysis, _context) do
    cond do
      analysis["type"] == "code" -> GraphRAG
      analysis["complexity"] == "complex" -> Agentic
      analysis["requires_reasoning"] -> SelfRAG
      true -> Hybrid
    end
  end
end
```

---

## 5. Knowledge Graphs

### Graph Storage

| Feature | Status | Description |
|---------|--------|-------------|
| **Neo4j Adapter** | ✅ Exists | Native graph database |
| **PostgreSQL Graph** | 🔴 Gap | Adjacency list in Postgres |
| **RocksDB TripleStore** | 🔴 Gap | High-performance local |
| **DGraph Adapter** | 🎯 Vision | Distributed graph DB |
| **Neptune Adapter** | 🎯 Vision | AWS managed graph |

### Graph Operations

| Feature | Status | Description |
|---------|--------|-------------|
| **Node CRUD** | ✅ Exists | Basic node operations |
| **Edge CRUD** | ✅ Exists | Basic edge operations |
| **Cypher Queries** | ✅ Exists | Neo4j query language |
| **Community Detection** | 🔴 Gap | Label propagation |
| **PageRank** | 🎯 Vision | Node importance scoring |
| **Shortest Path** | 🎯 Vision | Path finding algorithms |
| **Graph Embedding** | 🎯 Vision | Node2Vec, GraphSAGE |
| **Temporal Graphs** | 🎯 Vision | Time-based relationships |

### Code Knowledge Graph (Vision)

```elixir
defmodule PortfolioManager.CodeGraph do
  @moduledoc """
  Build comprehensive knowledge graphs from code repositories.

  ## Node Types

  - Module/Class
  - Function/Method
  - Type/Struct
  - File
  - Test
  - Documentation
  - Concept (extracted)

  ## Edge Types

  - CALLS
  - IMPORTS
  - IMPLEMENTS
  - EXTENDS
  - TESTS
  - DOCUMENTS
  - RELATED_TO (semantic)
  - DEPENDS_ON
  """

  def build_from_repo(graph_id, repo_path, opts \\ []) do
    with {:ok, files} <- scan_files(repo_path, opts),
         {:ok, ast_data} <- parse_all_files(files),
         :ok <- create_graph(graph_id),
         :ok <- populate_nodes(graph_id, ast_data),
         :ok <- populate_edges(graph_id, ast_data),
         :ok <- add_semantic_edges(graph_id, opts) do
      compute_metrics(graph_id)
    end
  end

  defp add_semantic_edges(graph_id, opts) do
    # Use LLM to identify semantic relationships
    # between concepts that aren't in code structure
  end

  def query_related(graph_id, entity, depth \\ 2) do
    # Find all related nodes within depth
    # Return subgraph with context
  end

  def find_impact(graph_id, entity) do
    # Find all nodes that depend on this entity
    # Useful for change impact analysis
  end
end
```

---

## 6. LLM Integration

### Provider Support

| Feature | Status | Description |
|---------|--------|-------------|
| **Gemini** | ✅ Exists | Google AI |
| **Claude** | ✅ Exists | Anthropic |
| **OpenAI** | ✅ Exists | GPT models |
| **Cohere** | 🔴 Gap | Command models |
| **Ollama** | 🔴 Gap | Local models |
| **Groq** | 🎯 Vision | Fast inference |
| **Together** | 🎯 Vision | Open models |
| **Replicate** | 🎯 Vision | Model marketplace |
| **Bedrock** | 🎯 Vision | AWS managed |
| **Azure OpenAI** | 🎯 Vision | Enterprise Azure |
| **Vertex AI** | 🎯 Vision | Google Cloud |

### LLM Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Streaming** | ✅ Exists | Real-time responses |
| **Tool Calling** | ✅ Exists | Function calling |
| **JSON Mode** | 🎯 Vision | Structured output |
| **Vision** | 🎯 Vision | Image understanding |
| **Token Counting** | 🎯 Vision | Pre-request estimation |
| **Prompt Caching** | 🎯 Vision | Cache system prompts |
| **Context Caching** | 🎯 Vision | Cache long contexts |
| **Batch API** | 🎯 Vision | Cost-effective batch |

### Ideal LLM Router

```elixir
defmodule PortfolioManager.Router do
  @moduledoc """
  Intelligent multi-provider LLM routing.

  ## Strategies

  - **Fallback**: Try providers in priority order
  - **Round Robin**: Distribute load evenly
  - **Specialist**: Route by task type
  - **Cost Optimized**: Minimize cost
  - **Latency Optimized**: Minimize response time
  - **Quality Optimized**: Route to best model for task

  ## Features

  - Automatic health monitoring
  - Request/response logging
  - Usage tracking and cost calculation
  - Rate limit awareness
  - Retry with exponential backoff
  - Circuit breaker per provider
  """

  # Latency-optimized routing (vision)
  def complete_fastest(messages, opts \\ []) do
    providers = healthy_providers()

    # Race all providers, return first response
    providers
    |> Task.async_stream(&call_provider(&1, messages, opts))
    |> Enum.find(&match?({:ok, _}, &1))
  end

  # Quality-optimized routing (vision)
  def complete_best(messages, opts \\ []) do
    task_type = classify_task(messages)

    # Select best model for task type
    provider = best_provider_for(task_type)

    call_provider(provider, messages, opts)
  end

  defp classify_task(messages) do
    content = extract_content(messages)

    cond do
      code_related?(content) -> :code
      analytical?(content) -> :analysis
      creative?(content) -> :creative
      factual?(content) -> :factual
      true -> :general
    end
  end
end
```

---

## 7. Agent Framework

### Current Agent Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Tool Execution** | ✅ Exists | Run tools based on LLM |
| **Iterative Loop** | ✅ Exists | Multi-turn reasoning |
| **Built-in Tools** | ✅ Exists | search, read, list, graph |
| **Session Memory** | ✅ Exists | Conversation history |

### Vision Agent Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Planning** | 🎯 Vision | Multi-step plan generation |
| **Reflection** | 🎯 Vision | Self-critique and correction |
| **Multi-Agent** | 🎯 Vision | Agent collaboration |
| **Human-in-Loop** | 🎯 Vision | Request human input |
| **Checkpointing** | 🎯 Vision | Save/restore agent state |
| **Tool Discovery** | 🎯 Vision | Dynamic tool registration |
| **Sub-Agents** | 🎯 Vision | Hierarchical delegation |
| **Long-Term Memory** | 🎯 Vision | Persistent knowledge |

### ReAct Agent (Vision)

```elixir
defmodule PortfolioManager.Agent.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) agent implementation.

  ## Loop Structure

  1. Think: Reason about current state
  2. Act: Choose and execute tool
  3. Observe: Process tool output
  4. Repeat until answer or max iterations

  ## Output Format

  Thought: I need to find information about X
  Action: search_code
  Action Input: {"query": "X implementation"}
  Observation: Found 3 relevant results...
  Thought: Based on the results, I can see...
  Action: read_file
  ...
  Final Answer: The implementation of X works by...
  """

  def run(task, opts \\ []) do
    state = %{
      task: task,
      thoughts: [],
      actions: [],
      observations: [],
      iteration: 0,
      max_iterations: opts[:max_iterations] || 10
    }

    react_loop(state, opts)
  end

  defp react_loop(%{iteration: i, max_iterations: max} = state, _opts) when i >= max do
    synthesize_answer(state)
  end

  defp react_loop(state, opts) do
    # Generate thought and action
    {:ok, response} = generate_step(state, opts)

    case parse_response(response) do
      {:final_answer, answer} ->
        {:ok, answer}

      {:action, action, input} ->
        # Execute tool
        {:ok, observation} = execute_tool(action, input)

        # Update state and continue
        state
        |> add_thought(response.thought)
        |> add_action(action, input)
        |> add_observation(observation)
        |> increment_iteration()
        |> react_loop(opts)
    end
  end
end
```

### Multi-Agent System (Vision)

```elixir
defmodule PortfolioManager.Agent.Coordinator do
  @moduledoc """
  Coordinate multiple specialized agents.

  ## Agent Types

  - **Researcher**: Find and gather information
  - **Analyst**: Analyze and synthesize
  - **Coder**: Write and modify code
  - **Reviewer**: Review and critique
  - **Planner**: Create execution plans

  ## Coordination Patterns

  - Sequential: A → B → C
  - Parallel: A | B | C → D
  - Debate: A vs B → Judge
  - Hierarchy: Manager → Workers
  """

  def solve(task, opts \\ []) do
    # Generate plan
    plan = Planner.create_plan(task)

    # Execute plan with agents
    execute_plan(plan, opts)
  end

  defp execute_plan(plan, opts) do
    Enum.reduce(plan.steps, %{}, fn step, context ->
      agent = select_agent(step.type)
      {:ok, result} = agent.execute(step.task, context, opts)
      Map.put(context, step.id, result)
    end)
  end
end
```

---

## 8. Evaluation & Quality

### Evaluation Metrics

| Feature | Status | Description |
|---------|--------|-------------|
| **RAG Triad** | 🔴 Gap | Context relevance, groundedness, answer relevance |
| **Hallucination Detection** | 🔴 Gap | Verify grounded responses |
| **Faithfulness** | 🎯 Vision | Response matches context |
| **Answer Correctness** | 🎯 Vision | Compare to ground truth |
| **Context Precision** | 🎯 Vision | Relevant chunks retrieved |
| **Context Recall** | 🎯 Vision | All relevant chunks found |
| **Latency Metrics** | 🎯 Vision | Response time tracking |
| **Cost Metrics** | 🎯 Vision | Token usage and cost |

### Evaluation Framework (Vision)

```elixir
defmodule PortfolioManager.Evaluation do
  @moduledoc """
  Comprehensive RAG evaluation framework.

  ## Metrics

  ### Retrieval Quality
  - Context Precision: % of retrieved chunks that are relevant
  - Context Recall: % of relevant chunks that were retrieved
  - MRR: Mean Reciprocal Rank of first relevant result

  ### Generation Quality
  - Faithfulness: Response claims supported by context
  - Answer Relevance: Response addresses the question
  - Groundedness: No hallucinated information

  ### End-to-End
  - Answer Correctness: Matches expected answer
  - Answer Completeness: Covers all aspects
  - Answer Conciseness: Not unnecessarily verbose

  ## Usage

      generation = %Generation{
        query: "What is GenServer?",
        context: "...",
        response: "...",
        retrieval_results: [...]
      }

      {:ok, scores} = Evaluation.evaluate(generation, [:rag_triad, :faithfulness])
  """

  def evaluate(generation, metrics \\ [:rag_triad]) do
    results =
      metrics
      |> Enum.map(&evaluate_metric(&1, generation))
      |> Map.new()

    {:ok, results}
  end

  def evaluate_metric(:rag_triad, generation) do
    {:rag_triad, %{
      context_relevance: evaluate_context_relevance(generation),
      groundedness: evaluate_groundedness(generation),
      answer_relevance: evaluate_answer_relevance(generation)
    }}
  end

  def evaluate_metric(:faithfulness, generation) do
    # Extract claims from response
    claims = extract_claims(generation.response)

    # Verify each claim against context
    verified =
      Enum.map(claims, fn claim ->
        verify_claim(claim, generation.context)
      end)

    score = Enum.count(verified, & &1.supported) / length(verified)

    {:faithfulness, %{score: score, claims: verified}}
  end

  def evaluate_metric(:retrieval, generation) do
    # Requires ground truth relevant chunks
    ground_truth = generation.metadata[:ground_truth_chunks] || []
    retrieved = Enum.map(generation.retrieval_results, & &1.id)

    precision = length(retrieved -- (retrieved -- ground_truth)) / length(retrieved)
    recall = length(ground_truth -- (ground_truth -- retrieved)) / length(ground_truth)

    {:retrieval, %{precision: precision, recall: recall}}
  end
end
```

### Automated Testing (Vision)

```elixir
defmodule PortfolioManager.Evaluation.TestSuite do
  @moduledoc """
  Automated RAG evaluation test suite.

  ## Test Cases

  Define test cases with:
  - Query
  - Expected relevant chunks
  - Expected answer (optional)
  - Quality thresholds

  ## Example

      test_cases = [
        %{
          query: "What is GenServer?",
          expected_chunks: ["chunk_1", "chunk_3"],
          expected_answer: "GenServer is a behavior...",
          thresholds: %{
            context_relevance: 0.8,
            faithfulness: 0.9,
            answer_relevance: 0.7
          }
        }
      ]

      results = TestSuite.run(test_cases)
  """

  def run(test_cases, opts \\ []) do
    test_cases
    |> Task.async_stream(&run_test_case(&1, opts))
    |> Enum.map(fn {:ok, result} -> result end)
    |> summarize_results()
  end

  defp run_test_case(test_case, opts) do
    # Run RAG pipeline
    {:ok, generation} = RAG.query(test_case.query, opts)

    # Evaluate
    {:ok, scores} = Evaluation.evaluate(generation, [:rag_triad, :faithfulness])

    # Check thresholds
    passed = check_thresholds(scores, test_case.thresholds)

    %{
      query: test_case.query,
      scores: scores,
      passed: passed,
      generation: generation
    }
  end
end
```

---

## 9. Pipeline Orchestration

### Current Pipeline Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Sequential Steps** | ✅ Exists | Ordered execution |
| **Parallel Steps** | ✅ Exists | Concurrent execution |
| **Dependencies** | ✅ Exists | Step ordering |
| **Caching** | ✅ Exists | ETS-based result cache |
| **Timeouts** | ✅ Exists | Per-step timeouts |

### Vision Pipeline Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Retry Logic** | 🔴 Gap | Automatic retry with backoff |
| **Conditional Steps** | 🎯 Vision | Skip based on condition |
| **Dynamic Steps** | 🎯 Vision | Add steps at runtime |
| **Streaming Steps** | 🎯 Vision | Process stream data |
| **Checkpointing** | 🎯 Vision | Resume from failure |
| **Visualization** | 🎯 Vision | Pipeline DAG diagram |
| **Metrics** | 🎯 Vision | Per-step timing/success |
| **Distributed** | 🎯 Vision | Run across nodes |

### Advanced Pipeline DSL (Vision)

```elixir
defmodule MyPipeline do
  use PortfolioManager.Pipeline

  pipeline :analysis do
    # Conditional step
    step :check_cache, &check_cache/1

    step :fetch_data, &fetch_data/1,
      depends_on: [:check_cache],
      skip_if: &cache_hit?/1

    # Parallel steps
    parallel do
      step :parse, &parse/1, depends_on: [:fetch_data]
      step :extract, &extract/1, depends_on: [:fetch_data]
    end

    # Retry with backoff
    step :embed, &embed/1,
      depends_on: [:parse, :extract],
      retry: [max: 3, backoff: :exponential]

    # Streaming step
    step :process, &process_stream/1,
      depends_on: [:embed],
      streaming: true

    # Checkpoint after expensive operations
    step :store, &store/1,
      depends_on: [:process],
      checkpoint: true

    # Final step
    step :report, &report/1,
      depends_on: [:store]
  end
end
```

---

## 10. Developer Tools

### CLI Tools

| Feature | Status | Description |
|---------|--------|-------------|
| **mix portfolio.ask** | ✅ Exists | RAG Q&A |
| **mix portfolio.search** | ✅ Exists | Vector search |
| **mix portfolio.index** | ✅ Exists | Index repository |
| **mix portfolio.graph** | ✅ Exists | Graph operations |
| **mix portfolio.eval** | 🎯 Vision | Run evaluations |
| **mix portfolio.chat** | 🎯 Vision | Interactive chat |
| **mix portfolio.serve** | 🎯 Vision | Start API server |
| **mix portfolio.dashboard** | 🎯 Vision | Web dashboard |

### Interactive Chat (Vision)

```elixir
defmodule Mix.Tasks.Portfolio.Chat do
  use Mix.Task

  @shortdoc "Interactive RAG chat session"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Portfolio Chat - Type 'exit' to quit")
    IO.puts("Commands: /strategy, /index, /history, /clear")

    session = Agent.Session.new()
    chat_loop(session)
  end

  defp chat_loop(session) do
    input = IO.gets("> ") |> String.trim()

    case input do
      "exit" -> :ok
      "/strategy " <> strategy -> handle_strategy(strategy, session)
      "/clear" -> chat_loop(Agent.Session.new())
      "/history" -> show_history(session)
      query -> handle_query(query, session)
    end
  end

  defp handle_query(query, session) do
    IO.puts("\nThinking...\n")

    RAG.stream_query(query, fn chunk ->
      IO.write(chunk)
    end)

    IO.puts("\n")

    session = Agent.Session.add_message(session, %{role: :user, content: query})
    chat_loop(session)
  end
end
```

### Web Dashboard (Vision)

```elixir
defmodule PortfolioManagerWeb.DashboardLive do
  use Phoenix.LiveView

  @doc """
  Real-time dashboard showing:
  - RAG query statistics
  - Provider health status
  - Embedding pipeline progress
  - Recent queries and responses
  - Evaluation scores
  - Cost tracking
  """

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :telemetry.attach_many(...)
    end

    {:ok, assign(socket,
      queries: [],
      providers: Router.list_providers(),
      pipeline_stats: get_pipeline_stats(),
      evaluations: []
    )}
  end
end
```

---

## 11. Enterprise Features

### Security

| Feature | Status | Description |
|---------|--------|-------------|
| **API Key Encryption** | 🎯 Vision | Encrypt keys at rest |
| **Audit Logging** | 🎯 Vision | Track all operations |
| **RBAC** | 🎯 Vision | Role-based access |
| **Data Encryption** | 🎯 Vision | Encrypt stored data |
| **PII Detection** | 🎯 Vision | Detect sensitive data |
| **Content Filtering** | 🎯 Vision | Filter unsafe content |

### Multi-Tenancy

| Feature | Status | Description |
|---------|--------|-------------|
| **Tenant Isolation** | ⚠️ Partial | Via index_id/graph_id |
| **Per-Tenant Config** | 🎯 Vision | Different settings per tenant |
| **Usage Tracking** | 🎯 Vision | Track per-tenant usage |
| **Cost Allocation** | 🎯 Vision | Charge back to tenants |
| **Rate Limiting** | 🎯 Vision | Per-tenant limits |

### Scalability

| Feature | Status | Description |
|---------|--------|-------------|
| **Horizontal Scaling** | 🎯 Vision | Multiple nodes |
| **Request Queuing** | ✅ Exists | Broadway backpressure |
| **Caching Layer** | 🎯 Vision | Distributed cache |
| **Load Balancing** | 🎯 Vision | Distribute requests |
| **Async Processing** | ✅ Exists | Background pipelines |

---

## 12. Integrations

### IDE Integrations

| Feature | Status | Description |
|---------|--------|-------------|
| **VSCode Extension** | 🎯 Vision | Code assistant |
| **JetBrains Plugin** | 🎯 Vision | IntelliJ integration |
| **Neovim Plugin** | 🎯 Vision | Vim integration |
| **LSP Server** | 🎯 Vision | Language Server Protocol |

### External Services

| Feature | Status | Description |
|---------|--------|-------------|
| **GitHub Integration** | 🎯 Vision | Index repos, PRs |
| **GitLab Integration** | 🎯 Vision | GitLab repositories |
| **Jira Integration** | 🎯 Vision | Issue tracking |
| **Slack Bot** | 🎯 Vision | Query via Slack |
| **Discord Bot** | 🎯 Vision | Query via Discord |
| **Webhooks** | 🎯 Vision | Event notifications |

### Data Sources

| Feature | Status | Description |
|---------|--------|-------------|
| **Git Repository** | ✅ Exists | Index code repos |
| **Confluence** | 🎯 Vision | Documentation |
| **Notion** | 🎯 Vision | Knowledge base |
| **Google Drive** | 🎯 Vision | Documents |
| **Slack History** | 🎯 Vision | Team discussions |
| **Database Schemas** | 🎯 Vision | Index DB structure |

---

## Implementation Roadmap

### Phase 1: Foundation (Q1 2025)
- [ ] Semantic chunker
- [ ] RAG evaluation framework
- [ ] LLM reranker
- [ ] Embedding service with batching

### Phase 2: Quality (Q2 2025)
- [ ] Community detection for graphs
- [ ] HyDE and multi-query strategies
- [ ] Additional chunking strategies
- [ ] Pipeline retry logic

### Phase 3: Scale (Q3 2025)
- [ ] Additional vector store adapters (Qdrant, Pinecone)
- [ ] Distributed caching
- [ ] Multi-tenant improvements
- [ ] Web dashboard

### Phase 4: Enterprise (Q4 2025)
- [ ] Security features
- [ ] Audit logging
- [ ] IDE integrations
- [ ] External service connectors

---

## Conclusion

This vision document outlines a comprehensive feature set that would make the Portfolio Ecosystem a world-class RAG platform. The focus should be on:

1. **Immediate priorities**: Filling critical gaps (semantic chunking, evaluation, reranking)
2. **Quality improvements**: Advanced retrieval strategies, better agent capabilities
3. **Developer experience**: Better CLI tools, dashboard, IDE integrations
4. **Enterprise readiness**: Security, multi-tenancy, scalability

By following this roadmap, the Portfolio Ecosystem can become the definitive choice for building intelligent code analysis and knowledge management systems in Elixir.
