# Multi-Vector and Embedding Systems Architecture

**Expert:** Dr. James Liu, Senior Fellow ML/Embeddings Researcher
**Experience:** Google Brain, OpenAI Embeddings Team, Pinecone

---

## Table of Contents

1. [Multi-Index Architecture](#multi-index-architecture)
2. [Embedding Model Strategies](#embedding-model-strategies)
3. [Chunking Strategies Deep Dive](#chunking-strategies-deep-dive)
4. [Vector Index Types](#vector-index-types)
5. [Hybrid Search Architecture](#hybrid-search-architecture)
6. [Vector Store Comparison](#vector-store-comparison)
7. [Query-Time Optimizations](#query-time-optimizations)

---

## 1. Multi-Index Architecture

### 1.1 Index Registry Design

```elixir
defmodule PortfolioManager.VectorIndexRegistry do
  @moduledoc """
  Registry for managing multiple vector indexes with different
  embedding models and backends.
  """

  use GenServer

  @type index_config :: %{
    id: atom(),
    adapter: module(),
    embedding_model: String.t(),
    dimensions: pos_integer(),
    content_types: [atom()],
    backend: atom(),
    config: map()
  }

  defstruct indexes: %{}, default_index: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    indexes = build_indexes_from_manifest(opts[:manifest])
    default = Keyword.get(opts, :default_index, :docs_dense)

    {:ok, %__MODULE__{indexes: indexes, default_index: default}}
  end

  @doc """
  Route a query to the appropriate index based on content type.
  """
  def route_query(query, opts \\ []) do
    content_type = Keyword.get(opts, :content_type) || detect_content_type(query)

    GenServer.call(__MODULE__, {:route, content_type, opts})
  end

  @doc """
  Get all indexes for a given content type.
  """
  def indexes_for_content_type(content_type) do
    GenServer.call(__MODULE__, {:indexes_for, content_type})
  end

  @doc """
  Search across multiple indexes and merge results.
  """
  def multi_index_search(query, embedding, opts \\ []) do
    indexes = Keyword.get(opts, :indexes) || all_indexes()

    results = indexes
    |> Task.async_stream(fn index_id ->
      search_index(index_id, embedding, opts)
    end, timeout: 30_000)
    |> Enum.filter(&match?({:ok, {:ok, _}}, &1))
    |> Enum.flat_map(fn {:ok, {:ok, results}} -> results end)

    merge_and_rerank(results, query, opts)
  end

  @impl true
  def handle_call({:route, content_type, _opts}, _from, state) do
    index = find_best_index(state.indexes, content_type) ||
            Map.get(state.indexes, state.default_index)

    {:reply, {:ok, index}, state}
  end

  def handle_call({:indexes_for, content_type}, _from, state) do
    indexes = state.indexes
    |> Map.values()
    |> Enum.filter(fn idx -> content_type in idx.content_types end)

    {:reply, {:ok, indexes}, state}
  end

  defp build_indexes_from_manifest(%{indexes: indexes_config}) do
    Map.new(indexes_config, fn {id, config} ->
      {id, %{
        id: id,
        adapter: resolve_adapter(config.adapter),
        embedding_model: config.embedding_model,
        dimensions: config.dimensions,
        content_types: config[:content_types] || [:general],
        backend: config[:backend] || :pgvector,
        config: config[:config] || %{}
      }}
    end)
  end

  defp find_best_index(indexes, content_type) do
    indexes
    |> Map.values()
    |> Enum.find(fn idx -> content_type in idx.content_types end)
  end

  defp detect_content_type(query) do
    cond do
      is_code_query?(query) -> :code
      is_api_query?(query) -> :api
      true -> :docs
    end
  end

  defp is_code_query?(query) do
    code_indicators = ["function", "class", "def ", "import ", "require", "->", "=>", "()"]
    Enum.any?(code_indicators, &String.contains?(query, &1))
  end

  defp is_api_query?(query) do
    api_indicators = ["endpoint", "API", "REST", "GraphQL", "HTTP", "request", "response"]
    Enum.any?(api_indicators, &String.contains?(query, &1))
  end

  defp resolve_adapter(adapter_string) do
    # Convert string to module
    adapter_string
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> Module.concat()
  end

  defp all_indexes do
    GenServer.call(__MODULE__, :all_indexes)
  end

  defp search_index(index_id, embedding, opts) do
    GenServer.call(__MODULE__, {:search, index_id, embedding, opts})
  end

  defp merge_and_rerank(results, _query, opts) do
    limit = Keyword.get(opts, :limit, 20)

    results
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
    |> then(&{:ok, &1})
  end
end
```

### 1.2 Index Configuration Matrix

```yaml
# Recommended index configurations
indexes:
  # Dense embeddings for code
  code_dense:
    adapter: portfolio_index.adapters.qdrant
    embedding_model: voyage-code-2
    dimensions: 1536
    content_types: [code, function, class, module]
    config:
      collection: code_embeddings
      distance: cosine

  # Dense embeddings for documentation
  docs_dense:
    adapter: portfolio_index.adapters.pgvector
    embedding_model: text-embedding-3-large
    dimensions: 3072
    content_types: [docs, readme, markdown]
    config:
      table: doc_embeddings
      index_type: hnsw

  # Smaller model for fast retrieval
  docs_fast:
    adapter: portfolio_index.adapters.pgvector
    embedding_model: text-embedding-3-small
    dimensions: 1536
    content_types: [docs, readme]
    config:
      table: doc_embeddings_fast
      index_type: ivfflat

  # Sparse embeddings for keyword matching
  docs_sparse:
    adapter: portfolio_index.adapters.elastic
    embedding_model: splade-v3
    dimensions: 30522
    content_types: [docs, code]
    config:
      index: sparse_embeddings

  # Graph node embeddings
  graph_nodes:
    adapter: portfolio_index.adapters.qdrant
    embedding_model: node2vec-custom
    dimensions: 256
    content_types: [entity, concept]
    config:
      collection: graph_embeddings
```

---

## 2. Embedding Model Strategies

### 2.1 Model Selection Guide

| Use Case | Recommended Model | Dimensions | Notes |
|----------|------------------|------------|-------|
| **General Docs** | text-embedding-3-large | 3072 | Best quality, higher cost |
| **Fast Retrieval** | text-embedding-3-small | 1536 | Good balance |
| **Code Search** | voyage-code-2 | 1536 | Trained on code |
| **Multilingual** | multilingual-e5-large | 1024 | 100+ languages |
| **Local/Privacy** | nomic-embed-text | 768 | Self-hosted |
| **Sparse (Keywords)** | SPLADE-v3 | 30522 | Interpretable |

### 2.2 Multi-Model Embedder

```elixir
defmodule PortfolioIndex.Adapters.MultiModelEmbedder do
  @moduledoc """
  Embedder that supports multiple models and routes based on content.
  """

  use PortfolioIndex.Adapter, port: PortfolioCore.Ports.EmbedderPort

  defstruct [:models, :default_model, :cache]

  @impl PortfolioCore.Ports.EmbedderPort
  def init(config) do
    models = Map.new(config[:models], fn {id, model_config} ->
      {id, init_model(model_config)}
    end)

    {:ok, %__MODULE__{
      models: models,
      default_model: config[:default_model] || :text_embedding_3_small,
      cache: init_cache()
    }}
  end

  @impl PortfolioCore.Ports.EmbedderPort
  def embed(content, opts) do
    model_id = Keyword.get(opts, :model) || select_model(content)

    with {:ok, model} <- get_model(model_id),
         {:ok, embedding} <- cached_embed(content, model) do
      {:ok, maybe_normalize(embedding, opts)}
    end
  end

  @impl PortfolioCore.Ports.EmbedderPort
  def embed_batch(contents, opts) do
    model_id = Keyword.get(opts, :model) || :default
    batch_size = Keyword.get(opts, :batch_size, 100)

    with {:ok, model} <- get_model(model_id) do
      contents
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(fn batch ->
        case model.embed_batch(batch) do
          {:ok, embeddings} -> embeddings
          {:error, _} -> Enum.map(batch, fn _ -> nil end)
        end
      end)
      |> Enum.map(&maybe_normalize(&1, opts))
      |> then(&{:ok, &1})
    end
  end

  @impl PortfolioCore.Ports.EmbedderPort
  def list_models do
    {:ok, [
      %{id: :text_embedding_3_large, dimensions: 3072, max_tokens: 8191},
      %{id: :text_embedding_3_small, dimensions: 1536, max_tokens: 8191},
      %{id: :voyage_code_2, dimensions: 1536, max_tokens: 16000},
      %{id: :nomic_embed_text, dimensions: 768, max_tokens: 8192}
    ]}
  end

  @impl PortfolioCore.Ports.EmbedderPort
  def dimensions(model_id) do
    case model_id do
      :text_embedding_3_large -> {:ok, 3072}
      :text_embedding_3_small -> {:ok, 1536}
      :voyage_code_2 -> {:ok, 1536}
      :nomic_embed_text -> {:ok, 768}
      :splade_v3 -> {:ok, 30522}
      _ -> {:error, :unknown_model}
    end
  end

  defp select_model(content) do
    cond do
      looks_like_code?(content) -> :voyage_code_2
      String.length(content) > 4000 -> :text_embedding_3_small  # Faster for long docs
      true -> :text_embedding_3_large
    end
  end

  defp looks_like_code?(content) do
    code_patterns = [
      ~r/def\s+\w+\s*\(/,           # Function definitions
      ~r/class\s+\w+/,               # Class definitions
      ~r/import\s+[\w.]+/,           # Import statements
      ~r/fn\s*\(.*\)\s*->/,          # Elixir anonymous functions
      ~r/defmodule\s+\w+/            # Elixir modules
    ]

    Enum.any?(code_patterns, &Regex.match?(&1, content))
  end

  defp cached_embed(content, model) do
    cache_key = :erlang.phash2({content, model.id})

    case get_from_cache(cache_key) do
      {:ok, embedding} -> {:ok, embedding}
      :miss ->
        case model.embed(content) do
          {:ok, embedding} = result ->
            put_in_cache(cache_key, embedding)
            result
          error -> error
        end
    end
  end

  defp maybe_normalize(nil, _), do: nil
  defp maybe_normalize(embedding, opts) do
    if Keyword.get(opts, :normalize, true) do
      normalize_l2(embedding)
    else
      embedding
    end
  end

  defp normalize_l2(embedding) do
    norm = :math.sqrt(Enum.reduce(embedding, 0, fn x, acc -> acc + x * x end))
    if norm > 0, do: Enum.map(embedding, &(&1 / norm)), else: embedding
  end

  defp init_model(_config), do: %{}
  defp get_model(_id), do: {:ok, %{}}
  defp init_cache, do: %{}
  defp get_from_cache(_key), do: :miss
  defp put_in_cache(_key, _value), do: :ok
end
```

### 2.3 Embedding Versioning

```elixir
defmodule PortfolioManager.EmbeddingVersioning do
  @moduledoc """
  Track embedding versions for re-embedding on model updates.
  """

  @doc """
  Store embedding with version metadata.
  """
  def store_with_version(chunk, embedding, model_id) do
    %{
      chunk_id: chunk.id,
      embedding: embedding,
      model_id: model_id,
      model_version: get_model_version(model_id),
      embedded_at: DateTime.utc_now(),
      content_hash: hash_content(chunk.content)
    }
  end

  @doc """
  Check if chunk needs re-embedding.
  """
  def needs_reembedding?(stored, current_model_version) do
    stored.model_version != current_model_version ||
      stored.content_hash != hash_content(get_current_content(stored.chunk_id))
  end

  @doc """
  Get chunks that need re-embedding for a model upgrade.
  """
  def get_stale_chunks(model_id, new_version) do
    # Query for chunks where model_version != new_version
    {:ok, []}
  end

  defp get_model_version(model_id) do
    # Return current version of model
    "v1.0"
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp get_current_content(_chunk_id), do: ""
end
```

---

## 3. Chunking Strategies Deep Dive

### 3.1 Chunking Strategy Matrix

| Strategy | Best For | Chunk Size | Overlap | Coherence |
|----------|----------|------------|---------|-----------|
| **Character** | Fixed-size needs | 500-2000 | 50-200 | Low |
| **Sentence** | Natural text | 3-10 sentences | 1-2 sentences | Medium |
| **Paragraph** | Well-structured docs | 1-5 paragraphs | 1 paragraph | High |
| **Recursive** | Mixed content | Adaptive | Adaptive | High |
| **Semantic** | Quality-critical | Variable | Context-aware | Highest |
| **Code-Aware** | Source code | Function/class | Imports | High |

### 3.2 Advanced Chunker Implementation

```elixir
defmodule PortfolioIndex.Adapters.AdvancedChunker do
  @moduledoc """
  Multi-strategy chunker with code awareness and semantic boundaries.
  """

  use PortfolioIndex.Adapter, port: PortfolioCore.Ports.ChunkerPort

  @impl PortfolioCore.Ports.ChunkerPort
  def chunk(content, opts) do
    strategy = Keyword.get(opts, :strategy, :recursive)

    case strategy do
      :character -> chunk_character(content, opts)
      :sentence -> chunk_sentence(content, opts)
      :paragraph -> chunk_paragraph(content, opts)
      :recursive -> chunk_recursive(content, opts)
      :semantic -> chunk_semantic(content, opts)
      :code -> chunk_code(content, opts)
    end
  end

  # Character-based chunking
  defp chunk_character(content, opts) do
    size = Keyword.get(opts, :chunk_size, 1000)
    overlap = Keyword.get(opts, :chunk_overlap, 200)

    chunks = do_character_chunk(content, size, overlap, 0, [])
    {:ok, chunks}
  end

  defp do_character_chunk(content, size, overlap, offset, acc) when byte_size(content) <= size do
    chunk = %{
      content: content,
      index: length(acc),
      start_offset: offset,
      end_offset: offset + byte_size(content),
      metadata: %{strategy: :character}
    }
    {:ok, Enum.reverse([chunk | acc])}
  end

  defp do_character_chunk(content, size, overlap, offset, acc) do
    {chunk_content, rest} = String.split_at(content, size)

    chunk = %{
      content: chunk_content,
      index: length(acc),
      start_offset: offset,
      end_offset: offset + size,
      metadata: %{strategy: :character}
    }

    # Overlap: include last `overlap` characters in next chunk
    overlap_content = String.slice(chunk_content, -overlap, overlap)
    next_content = overlap_content <> rest
    next_offset = offset + size - overlap

    do_character_chunk(next_content, size, overlap, next_offset, [chunk | acc])
  end

  # Recursive chunking with multiple separators
  defp chunk_recursive(content, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    overlap = Keyword.get(opts, :chunk_overlap, 200)

    separators = Keyword.get(opts, :separators, [
      "\n\n\n",      # Triple newline (major sections)
      "\n\n",        # Double newline (paragraphs)
      "\n",          # Single newline
      ". ",          # Sentences
      ", ",          # Clauses
      " "            # Words
    ])

    chunks = recursive_split(content, separators, chunk_size, overlap)
    indexed = Enum.with_index(chunks, fn chunk, idx ->
      Map.put(chunk, :index, idx)
    end)

    {:ok, indexed}
  end

  defp recursive_split(content, [], chunk_size, overlap) do
    # Fallback to character chunking
    {:ok, chunks} = chunk_character(content, chunk_size: chunk_size, chunk_overlap: overlap)
    chunks
  end

  defp recursive_split(content, [separator | rest_separators], chunk_size, overlap) do
    parts = String.split(content, separator)

    if Enum.all?(parts, &(String.length(&1) <= chunk_size)) do
      # All parts fit, merge small parts
      merge_small_chunks(parts, separator, chunk_size, overlap)
    else
      # Some parts too big, recurse with next separator
      Enum.flat_map(parts, fn part ->
        if String.length(part) <= chunk_size do
          [%{content: part, start_offset: 0, end_offset: String.length(part), metadata: %{}}]
        else
          recursive_split(part, rest_separators, chunk_size, overlap)
        end
      end)
    end
  end

  defp merge_small_chunks(parts, separator, chunk_size, _overlap) do
    {chunks, current, _} = Enum.reduce(parts, {[], "", 0}, fn part, {chunks, current, offset} ->
      candidate = if current == "", do: part, else: current <> separator <> part

      if String.length(candidate) <= chunk_size do
        {chunks, candidate, offset}
      else
        chunk = %{
          content: current,
          start_offset: offset,
          end_offset: offset + String.length(current),
          metadata: %{strategy: :recursive}
        }
        new_offset = offset + String.length(current) + String.length(separator)
        {[chunk | chunks], part, new_offset}
      end
    end)

    # Don't forget the last chunk
    final_chunk = %{
      content: current,
      start_offset: 0,
      end_offset: String.length(current),
      metadata: %{strategy: :recursive}
    }

    Enum.reverse([final_chunk | chunks])
  end

  # Code-aware chunking
  defp chunk_code(content, opts) do
    language = Keyword.get(opts, :language) || detect_language(content)

    case language do
      :elixir -> chunk_elixir(content, opts)
      :python -> chunk_python(content, opts)
      :javascript -> chunk_javascript(content, opts)
      :typescript -> chunk_javascript(content, opts)
      _ -> chunk_recursive(content, opts)
    end
  end

  defp chunk_elixir(content, opts) do
    # Split on module and function boundaries
    patterns = [
      ~r/\n(?=defmodule\s)/,        # Module boundaries
      ~r/\n(?=def\s+\w+)/,          # Public functions
      ~r/\n(?=defp\s+\w+)/          # Private functions
    ]

    chunks = split_by_patterns(content, patterns, opts)
    {:ok, add_context_to_chunks(chunks, content, :elixir)}
  end

  defp chunk_python(content, opts) do
    patterns = [
      ~r/\n(?=class\s+\w+)/,        # Class boundaries
      ~r/\n(?=def\s+\w+)/,          # Function boundaries
      ~r/\n(?=async\s+def\s+\w+)/   # Async functions
    ]

    chunks = split_by_patterns(content, patterns, opts)
    {:ok, add_context_to_chunks(chunks, content, :python)}
  end

  defp chunk_javascript(content, opts) do
    patterns = [
      ~r/\n(?=class\s+\w+)/,                    # Classes
      ~r/\n(?=function\s+\w+)/,                 # Named functions
      ~r/\n(?=const\s+\w+\s*=\s*(?:async\s*)?\()/,  # Arrow functions
      ~r/\n(?=export\s+)/                       # Exports
    ]

    chunks = split_by_patterns(content, patterns, opts)
    {:ok, add_context_to_chunks(chunks, content, :javascript)}
  end

  defp split_by_patterns(content, patterns, opts) do
    max_size = Keyword.get(opts, :chunk_size, 2000)

    # Combine patterns into one regex
    combined = patterns
    |> Enum.map(&Regex.source/1)
    |> Enum.join("|")

    parts = Regex.split(~r/#{combined}/, content, include_captures: true)

    parts
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {part, idx} ->
      if String.length(part) > max_size do
        # Too big, fall back to recursive
        {:ok, sub_chunks} = chunk_recursive(part, chunk_size: max_size)
        sub_chunks
      else
        [%{
          content: part,
          index: idx,
          start_offset: 0,
          end_offset: String.length(part),
          metadata: %{strategy: :code}
        }]
      end
    end)
    |> List.flatten()
  end

  defp add_context_to_chunks(chunks, full_content, language) do
    # Add imports/module context to each chunk
    context = extract_file_context(full_content, language)

    Enum.map(chunks, fn chunk ->
      %{chunk | metadata: Map.put(chunk.metadata, :file_context, context)}
    end)
  end

  defp extract_file_context(content, :elixir) do
    # Extract module name and aliases
    module = case Regex.run(~r/defmodule\s+([\w.]+)/, content) do
      [_, name] -> name
      _ -> nil
    end

    aliases = Regex.scan(~r/alias\s+([\w.]+)/, content)
    |> Enum.map(fn [_, alias] -> alias end)

    %{module: module, aliases: aliases}
  end

  defp extract_file_context(content, :python) do
    imports = Regex.scan(~r/^(?:from\s+[\w.]+\s+)?import\s+.+$/m, content)
    |> Enum.map(fn [import] -> import end)

    %{imports: imports}
  end

  defp extract_file_context(content, :javascript) do
    imports = Regex.scan(~r/^import\s+.+$/m, content)
    |> Enum.map(fn [import] -> import end)

    %{imports: imports}
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, "defmodule") -> :elixir
      String.contains?(content, "def ") and String.contains?(content, ":") -> :python
      String.contains?(content, "function") or String.contains?(content, "=>") -> :javascript
      true -> :unknown
    end
  end

  # Semantic chunking (requires embedding model)
  defp chunk_semantic(content, opts) do
    # First split into sentences
    sentences = split_into_sentences(content)

    # Embed each sentence
    embeddings = embed_sentences(sentences)

    # Group by semantic similarity
    groups = group_by_similarity(sentences, embeddings, opts)

    chunks = Enum.with_index(groups, fn group, idx ->
      %{
        content: Enum.join(group.sentences, " "),
        index: idx,
        start_offset: group.start_offset,
        end_offset: group.end_offset,
        metadata: %{strategy: :semantic, coherence_score: group.coherence}
      }
    end)

    {:ok, chunks}
  end

  defp split_into_sentences(content) do
    # Simple sentence splitting
    content
    |> String.split(~r/(?<=[.!?])\s+/)
    |> Enum.reject(&(&1 == ""))
  end

  defp embed_sentences(_sentences) do
    # Would call embedder
    []
  end

  defp group_by_similarity(sentences, _embeddings, opts) do
    threshold = Keyword.get(opts, :similarity_threshold, 0.8)
    max_size = Keyword.get(opts, :chunk_size, 1000)

    # Group sentences until similarity drops or size exceeded
    # Simplified implementation
    sentences
    |> Enum.chunk_every(5)
    |> Enum.map(fn group ->
      %{
        sentences: group,
        start_offset: 0,
        end_offset: 0,
        coherence: threshold
      }
    end)
  end

  @impl PortfolioCore.Ports.ChunkerPort
  def list_strategies do
    [:character, :sentence, :paragraph, :recursive, :semantic, :code]
  end

  @impl PortfolioCore.Ports.ChunkerPort
  def strategy_info(strategy) do
    info = case strategy do
      :character -> %{description: "Fixed character-based splitting", preserves_context: false}
      :sentence -> %{description: "Sentence boundary splitting", preserves_context: true}
      :paragraph -> %{description: "Paragraph boundary splitting", preserves_context: true}
      :recursive -> %{description: "Hierarchical splitting with fallback", preserves_context: true}
      :semantic -> %{description: "Embedding-based semantic grouping", preserves_context: true}
      :code -> %{description: "Language-aware code splitting", preserves_context: true}
    end

    {:ok, info}
  end

  @impl PortfolioCore.Ports.ChunkerPort
  def estimate_chunks(content, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, 1000)
    overlap = Keyword.get(opts, :chunk_overlap, 200)

    content_length = String.length(content)
    effective_chunk = chunk_size - overlap

    count = max(1, ceil(content_length / effective_chunk))
    {:ok, count}
  end
end
```

---

## 4. Vector Index Types

### 4.1 Index Type Comparison

| Index Type | Build Time | Query Time | Memory | Recall | Best For |
|------------|------------|------------|--------|--------|----------|
| **Flat (Exact)** | O(1) | O(n) | Low | 100% | < 10K vectors |
| **IVF** | O(n log n) | O(√n) | Medium | 95-99% | 10K - 1M vectors |
| **HNSW** | O(n log n) | O(log n) | High | 98-99.9% | Quality-critical |
| **PQ** | O(n) | O(n) | Very Low | 90-95% | Memory-constrained |
| **ScaNN** | O(n log n) | O(log n) | Medium | 98%+ | Large scale |

### 4.2 pgvector Index Configuration

```sql
-- IVF index for larger datasets
CREATE INDEX ON doc_chunks
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);  -- sqrt(n) is a good starting point

-- HNSW index for better recall
CREATE INDEX ON doc_chunks
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Query with ef_search parameter
SET hnsw.ef_search = 100;
SELECT * FROM doc_chunks
ORDER BY embedding <=> $1
LIMIT 10;
```

### 4.3 Index Selection Logic

```elixir
defmodule PortfolioManager.IndexSelector do
  @moduledoc """
  Select optimal index type based on data characteristics.
  """

  def recommend_index(opts) do
    vector_count = Keyword.get(opts, :vector_count, 0)
    dimensions = Keyword.get(opts, :dimensions, 1536)
    recall_requirement = Keyword.get(opts, :recall, 0.95)
    memory_budget_gb = Keyword.get(opts, :memory_budget_gb, 8)

    cond do
      vector_count < 10_000 ->
        {:flat, %{reason: "Small dataset, exact search is fast enough"}}

      vector_count < 100_000 and recall_requirement < 0.98 ->
        lists = trunc(:math.sqrt(vector_count))
        {:ivfflat, %{lists: lists, reason: "Medium dataset, IVF provides good balance"}}

      recall_requirement >= 0.98 ->
        {:hnsw, %{m: 16, ef_construction: 100, reason: "High recall requirement"}}

      memory_constrained?(vector_count, dimensions, memory_budget_gb) ->
        {:pq, %{segments: 8, reason: "Memory constrained, use product quantization"}}

      true ->
        {:hnsw, %{m: 16, ef_construction: 64, reason: "Default high-performance index"}}
    end
  end

  defp memory_constrained?(count, dims, budget_gb) do
    # Estimate memory: count * dims * 4 bytes (float32)
    estimated_gb = count * dims * 4 / (1024 * 1024 * 1024)
    estimated_gb > budget_gb * 0.5  # Leave room for index overhead
  end
end
```

---

## 5. Hybrid Search Architecture

### 5.1 Dense + Sparse Fusion

```elixir
defmodule PortfolioManager.HybridSearch do
  @moduledoc """
  Hybrid search combining dense vectors with sparse (BM25/SPLADE).
  """

  @doc """
  Execute hybrid search with RRF fusion.
  """
  def search(query, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, 0.7)  # Dense weight
    limit = Keyword.get(opts, :limit, 20)

    with {:ok, dense_results} <- dense_search(query, opts),
         {:ok, sparse_results} <- sparse_search(query, opts) do

      fused = reciprocal_rank_fusion([
        {dense_results, alpha},
        {sparse_results, 1 - alpha}
      ], k: 60)

      {:ok, Enum.take(fused, limit)}
    end
  end

  @doc """
  Reciprocal Rank Fusion (RRF) algorithm.
  """
  def reciprocal_rank_fusion(ranked_lists, opts \\ []) do
    k = Keyword.get(opts, :k, 60)

    # Calculate RRF score for each document
    scores = Enum.reduce(ranked_lists, %{}, fn {results, weight}, acc ->
      results
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {result, rank}, inner_acc ->
        doc_id = result.chunk_id
        rrf_score = weight / (k + rank)

        Map.update(inner_acc, doc_id, {result, rrf_score}, fn {doc, existing_score} ->
          {doc, existing_score + rrf_score}
        end)
      end)
    end)

    # Sort by fused score
    scores
    |> Map.values()
    |> Enum.sort_by(fn {_doc, score} -> score end, :desc)
    |> Enum.map(fn {doc, score} -> Map.put(doc, :rrf_score, score) end)
  end

  defp dense_search(query, opts) do
    with {:ok, embedding} <- embed_query(query),
         {:ok, results} <- vector_search(embedding, opts) do
      {:ok, results}
    end
  end

  defp sparse_search(query, opts) do
    # BM25 or SPLADE search
    {:ok, []}
  end

  defp embed_query(_query), do: {:ok, []}
  defp vector_search(_embedding, _opts), do: {:ok, []}
end
```

### 5.2 ColBERT-Style Late Interaction

```elixir
defmodule PortfolioManager.LateInteraction do
  @moduledoc """
  ColBERT-style late interaction for fine-grained matching.
  """

  @doc """
  Compute MaxSim score between query tokens and document tokens.
  """
  def maxsim_score(query_embeddings, doc_embeddings) do
    # For each query token, find max similarity with any doc token
    # Sum these max similarities

    query_embeddings
    |> Enum.map(fn q_emb ->
      doc_embeddings
      |> Enum.map(&cosine_similarity(q_emb, &1))
      |> Enum.max()
    end)
    |> Enum.sum()
  end

  @doc """
  Two-stage retrieval with late interaction reranking.
  """
  def search_with_late_interaction(query, opts \\ []) do
    first_stage_k = Keyword.get(opts, :first_stage_k, 100)
    final_k = Keyword.get(opts, :limit, 20)

    with {:ok, query_embeddings} <- embed_query_tokens(query),
         {:ok, candidates} <- first_stage_retrieval(query, first_stage_k),
         {:ok, reranked} <- rerank_with_maxsim(candidates, query_embeddings) do
      {:ok, Enum.take(reranked, final_k)}
    end
  end

  defp embed_query_tokens(_query) do
    # Embed each token separately for late interaction
    {:ok, []}
  end

  defp first_stage_retrieval(query, k) do
    # Fast dense retrieval to get candidates
    {:ok, []}
  end

  defp rerank_with_maxsim(candidates, query_embeddings) do
    reranked = candidates
    |> Enum.map(fn candidate ->
      score = maxsim_score(query_embeddings, candidate.token_embeddings)
      Map.put(candidate, :maxsim_score, score)
    end)
    |> Enum.sort_by(& &1.maxsim_score, :desc)

    {:ok, reranked}
  end

  defp cosine_similarity(a, b) do
    dot = Enum.zip(a, b) |> Enum.reduce(0, fn {x, y}, acc -> acc + x * y end)
    norm_a = :math.sqrt(Enum.reduce(a, 0, fn x, acc -> acc + x * x end))
    norm_b = :math.sqrt(Enum.reduce(b, 0, fn x, acc -> acc + x * x end))

    if norm_a > 0 and norm_b > 0, do: dot / (norm_a * norm_b), else: 0
  end
end
```

---

## 6. Vector Store Comparison

### 6.1 Feature Matrix

| Feature | pgvector | Qdrant | Pinecone | Weaviate | Milvus |
|---------|----------|--------|----------|----------|--------|
| **Self-hosted** | Yes | Yes | No | Yes | Yes |
| **Managed** | Via cloud | Qdrant Cloud | Yes | Weaviate Cloud | Zilliz |
| **Max Dimensions** | 2000 | 65535 | 20000 | 65535 | 32768 |
| **Filtering** | SQL | Rich | Basic | GraphQL | Expr |
| **Hybrid Search** | Manual | Built-in | Sparse | BM25 | Yes |
| **Sharding** | Manual | Auto | Auto | Auto | Auto |
| **Cost** | Low | Medium | High | Medium | Medium |

### 6.2 When to Use Each

```elixir
defmodule PortfolioManager.VectorStoreSelector do
  @doc """
  Recommend vector store based on requirements.
  """
  def recommend(requirements) do
    cond do
      requirements[:managed] and requirements[:scale] == :large ->
        {:pinecone, "Fully managed, scales to billions of vectors"}

      requirements[:self_hosted] and requirements[:postgres_existing] ->
        {:pgvector, "Leverage existing Postgres, simpler ops"}

      requirements[:hybrid_search] and requirements[:filtering] == :complex ->
        {:qdrant, "Best filtering and hybrid search capabilities"}

      requirements[:graphql] or requirements[:multi_modal] ->
        {:weaviate, "GraphQL API and multi-modal support"}

      requirements[:scale] == :massive and requirements[:self_hosted] ->
        {:milvus, "Designed for massive scale distributed deployments"}

      true ->
        {:pgvector, "Good default for most use cases"}
    end
  end
end
```

---

## 7. Query-Time Optimizations

### 7.1 Query Expansion

```elixir
defmodule PortfolioManager.QueryExpansion do
  @doc """
  Expand query with synonyms and related terms.
  """
  def expand(query, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :llm)

    case strategy do
      :llm -> llm_expansion(query)
      :embedding -> embedding_expansion(query)
      :thesaurus -> thesaurus_expansion(query)
    end
  end

  defp llm_expansion(query) do
    prompt = """
    Generate 3-5 alternative phrasings for this search query.
    Original: #{query}
    Alternatives (one per line):
    """

    # Call LLM and parse response
    {:ok, [query]}
  end

  defp embedding_expansion(query) do
    # Find similar queries from query log
    {:ok, [query]}
  end

  defp thesaurus_expansion(query) do
    # Expand with synonyms
    {:ok, [query]}
  end
end
```

### 7.2 Hypothetical Document Embedding (HyDE)

```elixir
defmodule PortfolioManager.HyDE do
  @moduledoc """
  Hypothetical Document Embeddings for improved retrieval.
  """

  @doc """
  Generate a hypothetical answer, embed it, and search.
  """
  def search_with_hyde(query, opts \\ []) do
    with {:ok, hypothetical} <- generate_hypothetical_answer(query),
         {:ok, embedding} <- embed(hypothetical),
         {:ok, results} <- vector_search(embedding, opts) do
      {:ok, results}
    end
  end

  defp generate_hypothetical_answer(query) do
    prompt = """
    Write a short paragraph that would be a good answer to this question.
    Write as if you are writing documentation.

    Question: #{query}

    Answer:
    """

    # Call LLM
    {:ok, "Hypothetical answer..."}
  end

  defp embed(_text), do: {:ok, []}
  defp vector_search(_embedding, _opts), do: {:ok, []}
end
```

### 7.3 Iterative Retrieval

```elixir
defmodule PortfolioManager.IterativeRetrieval do
  @moduledoc """
  Multi-round retrieval with refinement.
  """

  @doc """
  Iteratively refine retrieval based on initial results.
  """
  def iterative_search(query, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 3)
    target_count = Keyword.get(opts, :target_count, 10)

    do_iterative_search(query, [], 0, max_iterations, target_count)
  end

  defp do_iterative_search(_query, results, iteration, max_iter, _target)
       when iteration >= max_iter do
    {:ok, results}
  end

  defp do_iterative_search(_query, results, _iteration, _max_iter, target)
       when length(results) >= target do
    {:ok, Enum.take(results, target)}
  end

  defp do_iterative_search(query, existing_results, iteration, max_iter, target) do
    # Search with current query
    {:ok, new_results} = search_round(query, existing_results)

    # Combine and deduplicate
    combined = (existing_results ++ new_results)
    |> Enum.uniq_by(& &1.chunk_id)

    # Generate refined query based on results
    refined_query = refine_query(query, combined)

    do_iterative_search(refined_query, combined, iteration + 1, max_iter, target)
  end

  defp search_round(_query, _existing), do: {:ok, []}

  defp refine_query(original_query, _results) do
    # Use LLM to generate better query based on results
    original_query
  end
end
```

---

## Summary

This multi-vector architecture provides:

1. **Index Registry**: Route queries to appropriate indexes by content type
2. **Multi-Model Support**: Different embedding models for code vs docs
3. **Advanced Chunking**: Code-aware, semantic, and recursive strategies
4. **Index Selection**: Automatic index type recommendation
5. **Hybrid Search**: Dense + sparse fusion with RRF
6. **Query Optimizations**: HyDE, expansion, iterative refinement

The architecture enables infinite scaling through multiple specialized indexes while maintaining retrieval quality across diverse content types.
