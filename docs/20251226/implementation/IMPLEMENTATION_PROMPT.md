# Portfolio Manager Implementation Prompt

## Overview

You are building `portfolio_manager` from scratch as the application layer on top of `portfolio_core` (hexagonal primitives) and `portfolio_index` (adapters and pipelines). This package provides the CLI interface, web API, workflow engine, and domain-specific logic for managing code portfolios with RAG capabilities.

**Note:** The `lib/` and `test/` directories will be deleted before you begin. You are building the codebase from the ground up. The previous implementation is preserved in git history for reference.

---

## Required Reading

Before implementation, read these files in order:

### Architecture Documentation
```
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/00_executive_summary.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/01_beam_otp_architecture.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/02_hexagonal_core_design.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/05_pipeline_orchestration.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/06_advanced_rag_patterns.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/08_security_observability.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/09_implementation_roadmap.md
```

### Existing Source Code (Current Implementation)
```
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/portfolio.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/domain/registry.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/domain/repo.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/domain/context.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/adapters/local_git.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/adapters/yaml_storage.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/adapters/file_detector.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/graph.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/rag.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/views.ex
```

### Existing CLI Tasks
```
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.add.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.ask.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.config.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.edit.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.graph.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.init.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.list.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.remove.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.repl.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.review.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.run.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.scan.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.search.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.show.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.status.ex
/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.sync.ex
```

### Workflow Engine
```
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/engine.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/parser.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/context.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/agent_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/context_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/control_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/detection_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/file_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/git_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/update_step.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/workflow/steps/workflow_step.ex
```

### Existing Tests
```
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_add_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_edit_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_init_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_remove_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_review_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_scan_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_search_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_show_test.exs
/home/home/p/g/n/portfolio_manager/test/cli/portfolio_sync_test.exs
/home/home/p/g/n/portfolio_manager/test/domain/registry_test.exs
/home/home/p/g/n/portfolio_manager/test/graph/graph_test.exs
/home/home/p/g/n/portfolio_manager/test/portfolio_manager_test.exs
/home/home/p/g/n/portfolio_manager/test/views/views_test.exs
```

### Port Specifications (from portfolio_core)
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/vector_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/graph_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/document_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_core/ports/llm.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/retriever.ex
```

### Sibling Package Source Code

The source code for the core dependencies is available locally for reference:
- `../portfolio_core` - Hexagonal primitives, ports, and domain types
- `../portfolio_index` - Adapters, Broadway pipelines, and RAG strategies

Read these as needed to understand the APIs you're integrating with. If you encounter bugs or missing functionality in these packages, switch from hex deps to path deps in mix.exs and fix the issues directly in those codebases.

---

## Package Scope

### What portfolio_manager IS:
- CLI interface (Mix tasks) for portfolio operations
- Web API (Phoenix-based) for remote access
- Workflow engine for multi-step operations
- Domain logic specific to code portfolio management
- Manifest files for environment configuration
- Integration layer connecting portfolio_core and portfolio_index

### What portfolio_manager IS NOT:
- No port definitions (those are in portfolio_core)
- No adapter implementations (those are in portfolio_index)
- No Broadway pipelines (those are in portfolio_index)
- No RAG strategy implementations (those are in portfolio_index)

---

## Implementation Tasks

### 1. Update mix.exs

Update dependencies to use portfolio_core and portfolio_index:

```elixir
defmodule PortfolioManager.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :portfolio_manager,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :unknown, :unmatched_returns]
      ],
      preferred_cli_env: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioManager.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core packages (published on Hex)
      # Source available at ../portfolio_core and ../portfolio_index for reference.
      # If you encounter bugs in these packages, switch to path deps and fix them:
      #   {:portfolio_core, path: "../portfolio_core"},
      #   {:portfolio_index, path: "../portfolio_index"},
      {:portfolio_core, "~> 0.1.0"},
      {:portfolio_index, "~> 0.1.0"},

      # Web framework (optional, for API)
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 0.20", optional: true},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},

      # CLI utilities
      {:optimus, "~> 0.5"},

      # YAML for manifests
      {:yaml_elixir, "~> 2.9"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Dev/test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
```

### 2. Manifest Configuration

Create manifest files for each environment:

#### 2.1 config/manifests/development.yml

```yaml
version: "1.0"
environment: development

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      repo: PortfolioManager.Repo
      index_type: ivfflat
      lists: 100

  graph_store:
    adapter: PortfolioIndex.Adapters.GraphStore.Neo4j
    config:
      uri: ${NEO4J_URI:-bolt://localhost:7687}
      username: ${NEO4J_USER:-neo4j}
      password: ${NEO4J_PASSWORD:-password}
      pool_size: 5

  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.OpenAI
    config:
      model: text-embedding-3-small
      api_key: ${OPENAI_API_KEY}
      rate_limit:
        requests_per_minute: 3000
        tokens_per_minute: 1000000

  llm:
    adapter: PortfolioIndex.Adapters.LLM.Anthropic
    config:
      model: claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}
      max_tokens: 4096

  chunker:
    adapter: PortfolioIndex.Adapters.Chunker.Recursive
    config:
      chunk_size: 1000
      chunk_overlap: 200

pipelines:
  ingestion:
    enabled: true
    concurrency: 10
    batch_size: 50

  embedding:
    enabled: true
    concurrency: 5
    rate_limit: 100

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

rag:
  default_strategy: hybrid
  strategies:
    hybrid:
      vector_weight: 0.7
      keyword_weight: 0.3
    self_rag:
      critique_threshold: 3

telemetry:
  enabled: true
  exporters:
    - console
```

#### 2.2 config/manifests/test.yml

```yaml
version: "1.0"
environment: test

adapters:
  vector_store:
    adapter: PortfolioManager.Mocks.VectorStore
    config: {}

  graph_store:
    adapter: PortfolioManager.Mocks.GraphStore
    config: {}

  embedder:
    adapter: PortfolioManager.Mocks.Embedder
    config: {}

  llm:
    adapter: PortfolioManager.Mocks.LLM
    config: {}

  chunker:
    adapter: PortfolioManager.Mocks.Chunker
    config: {}

pipelines:
  ingestion:
    enabled: false

  embedding:
    enabled: false

telemetry:
  enabled: false
```

### 3. Refactor Application Module

`lib/portfolio_manager/application.ex`

```elixir
defmodule PortfolioManager.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      PortfolioManager.Repo,

      # Manifest engine (loads configuration)
      {PortfolioCore.Manifest.Engine, manifest_opts()},

      # Domain registry
      PortfolioManager.Domain.Registry,

      # Pipelines (if enabled)
      pipeline_children()
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: PortfolioManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp manifest_opts do
    env = Application.get_env(:portfolio_manager, :env, :dev)
    path = Path.join(["config", "manifests", "#{env}.yml"])

    [manifest_path: path]
  end

  defp pipeline_children do
    manifest = Application.get_env(:portfolio_manager, :manifest, %{})

    children = []

    children = if get_in(manifest, [:pipelines, :ingestion, :enabled]) do
      [{PortfolioIndex.Pipelines.Ingestion, ingestion_opts(manifest)} | children]
    else
      children
    end

    children = if get_in(manifest, [:pipelines, :embedding, :enabled]) do
      [{PortfolioIndex.Pipelines.Embedding, embedding_opts(manifest)} | children]
    else
      children
    end

    children
  end

  defp ingestion_opts(manifest) do
    config = get_in(manifest, [:pipelines, :ingestion]) || %{}
    [
      concurrency: config[:concurrency] || 10,
      batch_size: config[:batch_size] || 50
    ]
  end

  defp embedding_opts(manifest) do
    config = get_in(manifest, [:pipelines, :embedding]) || %{}
    [
      concurrency: config[:concurrency] || 5,
      rate_limit: config[:rate_limit] || 100
    ]
  end
end
```

### 4. Refactor RAG Module

Refactor to use portfolio_index strategies via portfolio_core registry:

`lib/portfolio_manager/rag.ex`

```elixir
defmodule PortfolioManager.RAG do
  @moduledoc """
  RAG interface for portfolio queries.
  Delegates to portfolio_index strategies via portfolio_core registry.
  """

  alias PortfolioCore.Registry
  alias PortfolioCore.Manifest.Engine

  @doc """
  Query the portfolio using RAG.

  ## Options
    - `:strategy` - RAG strategy to use (default from manifest)
    - `:k` - Number of results to retrieve (default: 10)
    - `:index_id` - Vector index to search (default: "default")
    - `:graph_id` - Graph to use for context (default: "default")
  """
  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(question, opts \\ []) do
    strategy_name = Keyword.get(opts, :strategy, default_strategy())
    strategy = get_strategy(strategy_name)

    context = build_context(opts)

    case strategy.retrieve(question, context, opts) do
      {:ok, result} ->
        emit_telemetry(:query, result)
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Ask a question and get a generated answer.
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    case query(question, opts) do
      {:ok, %{answer: answer}} when is_binary(answer) ->
        {:ok, answer}

      {:ok, %{items: items}} ->
        # Generate answer from retrieved items
        generate_answer(question, items, opts)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Search for relevant documents without generating an answer.
  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query_text, opts \\ []) do
    case query(query_text, Keyword.put(opts, :strategy, :hybrid)) do
      {:ok, %{items: items}} -> {:ok, items}
      {:error, _} = err -> err
    end
  end

  @doc """
  Index a repository for RAG queries.
  """
  @spec index_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_repo(repo_path, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")

    # Ensure index exists
    vector_store = get_adapter(:vector_store)
    embedder = get_adapter(:embedder)

    config = %{
      dimensions: embedder.dimensions(embedder_model()),
      metric: :cosine,
      index_type: :ivfflat
    }

    case vector_store.create_index(index_id, config) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, _} = err -> err
    end

    # Scan and enqueue files for ingestion
    files = scan_repo_files(repo_path, opts)

    Enum.each(files, fn file ->
      PortfolioIndex.Pipelines.Ingestion.enqueue(file)
    end)

    {:ok, %{files_queued: length(files), index_id: index_id}}
  end

  # Private functions

  defp default_strategy do
    manifest = Engine.get_manifest()
    get_in(manifest, [:rag, :default_strategy]) || :hybrid
  end

  defp get_strategy(:hybrid), do: PortfolioIndex.RAG.Strategies.Hybrid
  defp get_strategy(:self_rag), do: PortfolioIndex.RAG.Strategies.SelfRAG
  defp get_strategy(:graph_rag), do: PortfolioIndex.RAG.Strategies.GraphRAG
  defp get_strategy(:agentic), do: PortfolioIndex.RAG.Strategies.Agentic
  defp get_strategy(name), do: raise "Unknown RAG strategy: #{name}"

  defp get_adapter(port_name) do
    case Registry.get(port_name) do
      {module, _config} -> module
      nil -> raise "Adapter not configured for #{port_name}"
    end
  end

  defp build_context(opts) do
    %{
      index_id: Keyword.get(opts, :index_id, "default"),
      graph_id: Keyword.get(opts, :graph_id, "default"),
      tenant_id: Keyword.get(opts, :tenant_id)
    }
  end

  defp generate_answer(question, items, opts) do
    llm = get_adapter(:llm)

    context = items
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n---\n\n")

    messages = [
      %{role: :system, content: "Answer the question based on the provided context. Be concise and accurate."},
      %{role: :user, content: "Context:\n#{context}\n\nQuestion: #{question}"}
    ]

    case llm.complete(messages, opts) do
      {:ok, %{content: answer}} -> {:ok, answer}
      {:error, _} = err -> err
    end
  end

  defp embedder_model do
    manifest = Engine.get_manifest()
    get_in(manifest, [:adapters, :embedder, :config, :model]) || "text-embedding-3-small"
  end

  defp scan_repo_files(repo_path, opts) do
    extensions = Keyword.get(opts, :extensions, [".ex", ".exs", ".md", ".txt"])
    exclude = Keyword.get(opts, :exclude, ["deps/", "_build/", ".git/"])

    repo_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      File.regular?(path) and
      Enum.any?(extensions, &String.ends_with?(path, &1)) and
      not Enum.any?(exclude, &String.contains?(path, &1))
    end)
    |> Enum.map(fn path ->
      %{
        path: path,
        type: detect_file_type(path)
      }
    end)
  end

  defp detect_file_type(path) do
    cond do
      String.ends_with?(path, [".ex", ".exs"]) -> :elixir
      String.ends_with?(path, ".md") -> :markdown
      String.ends_with?(path, [".py"]) -> :python
      String.ends_with?(path, [".js", ".ts"]) -> :javascript
      true -> :plain
    end
  end

  defp emit_telemetry(event, result) do
    :telemetry.execute(
      [:portfolio_manager, :rag, event],
      %{
        timing_ms: result[:timing_ms] || 0,
        items_count: length(result[:items] || [])
      },
      %{strategy: result[:strategy]}
    )
  end
end
```

### 5. Refactor Graph Module

`lib/portfolio_manager/graph.ex`

```elixir
defmodule PortfolioManager.Graph do
  @moduledoc """
  Graph interface for code analysis and knowledge representation.
  """

  alias PortfolioCore.Registry
  alias PortfolioCore.Manifest.Engine

  @doc """
  Create a new graph.
  """
  @spec create_graph(String.t(), map()) :: :ok | {:error, term()}
  def create_graph(graph_id, config \\ %{}) do
    adapter = get_adapter()
    adapter.create_graph(graph_id, config)
  end

  @doc """
  Add a node to the graph.
  """
  @spec add_node(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def add_node(graph_id, node) do
    adapter = get_adapter()
    adapter.create_node(graph_id, node)
  end

  @doc """
  Add an edge between two nodes.
  """
  @spec add_edge(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def add_edge(graph_id, edge) do
    adapter = get_adapter()
    adapter.create_edge(graph_id, edge)
  end

  @doc """
  Get neighbors of a node.
  """
  @spec neighbors(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def neighbors(graph_id, node_id, opts \\ []) do
    adapter = get_adapter()
    adapter.get_neighbors(graph_id, node_id, opts)
  end

  @doc """
  Execute a raw query on the graph.
  """
  @spec query(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def query(graph_id, cypher, params \\ %{}) do
    adapter = get_adapter()
    adapter.query(graph_id, cypher, params)
  end

  @doc """
  Get graph statistics.
  """
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(graph_id) do
    adapter = get_adapter()
    adapter.graph_stats(graph_id)
  end

  @doc """
  Build dependency graph from repository analysis.
  """
  @spec build_dependency_graph(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build_dependency_graph(graph_id, repo_path, opts \\ []) do
    with :ok <- create_graph(graph_id, %{type: :dependency}),
         {:ok, deps} <- analyze_dependencies(repo_path, opts),
         :ok <- populate_graph(graph_id, deps) do
      stats(graph_id)
    end
  end

  # Private

  defp get_adapter do
    case Registry.get(:graph_store) do
      {module, _config} -> module
      nil -> raise "Graph store adapter not configured"
    end
  end

  defp analyze_dependencies(repo_path, opts) do
    language = Keyword.get(opts, :language, :elixir)

    case language do
      :elixir -> analyze_elixir_deps(repo_path)
      :python -> analyze_python_deps(repo_path)
      _ -> {:error, {:unsupported_language, language}}
    end
  end

  defp analyze_elixir_deps(repo_path) do
    mix_exs = Path.join(repo_path, "mix.exs")

    if File.exists?(mix_exs) do
      # Parse mix.exs for deps
      {:ok, content} = File.read(mix_exs)

      # Simple regex-based extraction (production would use AST)
      deps = Regex.scan(~r/{:(\w+),/, content)
      |> Enum.map(fn [_, name] -> %{name: name, type: :dependency} end)

      {:ok, deps}
    else
      {:error, :mix_exs_not_found}
    end
  end

  defp analyze_python_deps(repo_path) do
    requirements = Path.join(repo_path, "requirements.txt")

    if File.exists?(requirements) do
      {:ok, content} = File.read(requirements)

      deps = content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
      |> Enum.map(fn line ->
        name = line |> String.split(~r/[=<>]/) |> List.first() |> String.trim()
        %{name: name, type: :dependency}
      end)

      {:ok, deps}
    else
      {:error, :requirements_not_found}
    end
  end

  defp populate_graph(graph_id, deps) do
    Enum.each(deps, fn dep ->
      node = %{
        id: dep.name,
        labels: ["Dependency"],
        properties: Map.drop(dep, [:name])
      }
      add_node(graph_id, node)
    end)

    :ok
  end
end
```

### 6. Update CLI Tasks

Refactor CLI tasks to use the new architecture:

#### 6.1 lib/mix/tasks/portfolio.ask.ex

```elixir
defmodule Mix.Tasks.Portfolio.Ask do
  @moduledoc """
  Ask a question using RAG.

  ## Usage

      mix portfolio.ask "What does the User module do?"
      mix portfolio.ask "How is authentication handled?" --strategy self_rag

  ## Options

    * `--strategy` - RAG strategy to use (hybrid, self_rag, graph_rag)
    * `--index` - Vector index to query (default: default)
    * `--k` - Number of results to retrieve (default: 10)
  """

  use Mix.Task

  @shortdoc "Ask a question using RAG"

  @impl true
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, switches: [
      strategy: :string,
      index: :string,
      k: :integer
    ])

    Mix.Task.run("app.start")

    question = Enum.join(args, " ")

    if String.trim(question) == "" do
      Mix.shell().error("Usage: mix portfolio.ask \"your question\"")
      exit({:shutdown, 1})
    end

    query_opts = [
      strategy: String.to_atom(opts[:strategy] || "hybrid"),
      index_id: opts[:index] || "default",
      k: opts[:k] || 10
    ]

    Mix.shell().info("Querying: #{question}")
    Mix.shell().info("Strategy: #{query_opts[:strategy]}")

    case PortfolioManager.RAG.ask(question, query_opts) do
      {:ok, answer} ->
        Mix.shell().info("\n#{answer}")

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
```

#### 6.2 lib/mix/tasks/portfolio.index.ex (new)

```elixir
defmodule Mix.Tasks.Portfolio.Index do
  @moduledoc """
  Index a repository for RAG queries.

  ## Usage

      mix portfolio.index /path/to/repo
      mix portfolio.index . --index my_project

  ## Options

    * `--index` - Index name (default: default)
    * `--extensions` - File extensions to include (default: .ex,.exs,.md)
  """

  use Mix.Task

  @shortdoc "Index a repository for RAG"

  @impl true
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, switches: [
      index: :string,
      extensions: :string
    ])

    Mix.Task.run("app.start")

    repo_path = case args do
      [path | _] -> Path.expand(path)
      [] -> File.cwd!()
    end

    extensions = case opts[:extensions] do
      nil -> [".ex", ".exs", ".md"]
      ext -> String.split(ext, ",") |> Enum.map(&String.trim/1)
    end

    index_opts = [
      index_id: opts[:index] || "default",
      extensions: extensions
    ]

    Mix.shell().info("Indexing: #{repo_path}")
    Mix.shell().info("Index: #{index_opts[:index_id]}")
    Mix.shell().info("Extensions: #{Enum.join(extensions, ", ")}")

    case PortfolioManager.RAG.index_repo(repo_path, index_opts) do
      {:ok, result} ->
        Mix.shell().info("\nQueued #{result.files_queued} files for indexing")
        Mix.shell().info("Index ID: #{result.index_id}")

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
```

### 7. Test Refactoring

#### 7.1 test/support/mocks.ex

```elixir
defmodule PortfolioManager.Mocks do
  @moduledoc """
  Mox mock definitions for testing.
  """
end

# Define mocks for all ports
Mox.defmock(PortfolioManager.Mocks.VectorStore, for: PortfolioCore.Ports.VectorStore)
Mox.defmock(PortfolioManager.Mocks.GraphStore, for: PortfolioCore.Ports.GraphStore)
Mox.defmock(PortfolioManager.Mocks.DocumentStore, for: PortfolioCore.Ports.DocumentStore)
Mox.defmock(PortfolioManager.Mocks.Embedder, for: PortfolioCore.Ports.Embedder)
Mox.defmock(PortfolioManager.Mocks.LLM, for: PortfolioCore.Ports.LLM)
Mox.defmock(PortfolioManager.Mocks.Chunker, for: PortfolioCore.Ports.Chunker)
```

#### 7.2 test/rag_test.exs

```elixir
defmodule PortfolioManager.RAGTest do
  use ExUnit.Case, async: true

  import Mox

  alias PortfolioManager.RAG
  alias PortfolioManager.Mocks

  setup :verify_on_exit!

  setup do
    # Register mock adapters
    PortfolioCore.Registry.register(:vector_store, {Mocks.VectorStore, []})
    PortfolioCore.Registry.register(:embedder, {Mocks.Embedder, []})
    PortfolioCore.Registry.register(:llm, {Mocks.LLM, []})

    on_exit(fn ->
      PortfolioCore.Registry.clear()
    end)

    :ok
  end

  describe "query/2" do
    test "returns results using hybrid strategy" do
      # Mock embedder
      Mocks.Embedder
      |> expect(:embed, fn text, _opts ->
        assert text == "test query"
        {:ok, %{vector: List.duplicate(0.1, 1536), token_count: 2, model: "test", dimensions: 1536}}
      end)

      # Mock vector store
      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, k, _opts ->
        assert k == 10
        {:ok, [
          %{id: "doc1", score: 0.95, metadata: %{content: "result 1"}, vector: nil}
        ]}
      end)

      assert {:ok, result} = RAG.query("test query", strategy: :hybrid)
      assert length(result.items) == 1
      assert result.strategy == :hybrid
    end
  end

  describe "ask/2" do
    test "generates answer from retrieved context" do
      # Mock embedder
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 1536), token_count: 2, model: "test", dimensions: 1536}}
      end)

      # Mock vector store
      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok, [
          %{id: "doc1", score: 0.95, metadata: %{}, vector: nil, content: "Elixir is a functional language."}
        ]}
      end)

      # Mock LLM
      Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 2
        {:ok, %{content: "Elixir is a functional programming language.", usage: %{input_tokens: 10, output_tokens: 8}, finish_reason: :stop}}
      end)

      assert {:ok, answer} = RAG.ask("What is Elixir?")
      assert String.contains?(answer, "Elixir")
    end
  end
end
```

#### 7.3 test/graph_test.exs

```elixir
defmodule PortfolioManager.GraphTest do
  use ExUnit.Case, async: true

  import Mox

  alias PortfolioManager.Graph
  alias PortfolioManager.Mocks

  setup :verify_on_exit!

  setup do
    PortfolioCore.Registry.register(:graph_store, {Mocks.GraphStore, []})

    on_exit(fn ->
      PortfolioCore.Registry.clear()
    end)

    :ok
  end

  describe "create_graph/2" do
    test "creates a new graph" do
      Mocks.GraphStore
      |> expect(:create_graph, fn graph_id, config ->
        assert graph_id == "test_graph"
        assert config == %{type: :knowledge}
        :ok
      end)

      assert :ok = Graph.create_graph("test_graph", %{type: :knowledge})
    end
  end

  describe "add_node/2" do
    test "adds a node to the graph" do
      node = %{id: "node1", labels: ["Entity"], properties: %{name: "Test"}}

      Mocks.GraphStore
      |> expect(:create_node, fn graph_id, n ->
        assert graph_id == "test_graph"
        assert n.id == "node1"
        {:ok, n}
      end)

      assert {:ok, _} = Graph.add_node("test_graph", node)
    end
  end

  describe "neighbors/3" do
    test "returns neighbors of a node" do
      Mocks.GraphStore
      |> expect(:get_neighbors, fn graph_id, node_id, opts ->
        assert graph_id == "test_graph"
        assert node_id == "node1"
        {:ok, [%{id: "node2", labels: [], properties: %{}}]}
      end)

      assert {:ok, neighbors} = Graph.neighbors("test_graph", "node1")
      assert length(neighbors) == 1
    end
  end
end
```

### 8. Examples

#### 8.1 examples/README.md

```markdown
# Portfolio Manager Examples

## Setup

Ensure dependencies are installed and configured:

```bash
# Set environment variables
export OPENAI_API_KEY=your-key
export ANTHROPIC_API_KEY=your-key
export NEO4J_URI=bolt://localhost:7687

# Start dependencies
docker-compose up -d postgres neo4j

# Setup database
mix ecto.setup
```

## Running Examples

```bash
# Basic RAG query
mix run examples/rag_query.exs

# Index a repository
mix run examples/index_repo.exs

# Graph analysis
mix run examples/graph_analysis.exs

# Full workflow
mix run examples/full_workflow.exs
```
```

#### 8.2 examples/rag_query.exs

```elixir
# RAG Query Example
# Run: mix run examples/rag_query.exs

Mix.Task.run("app.start")

alias PortfolioManager.RAG

# Simple question
question = "How does the workflow engine process steps?"

IO.puts("Question: #{question}")
IO.puts("Strategy: hybrid\n")

case RAG.ask(question, strategy: :hybrid, k: 5) do
  {:ok, answer} ->
    IO.puts("Answer:")
    IO.puts(answer)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

#### 8.3 examples/index_repo.exs

```elixir
# Index Repository Example
# Run: mix run examples/index_repo.exs

Mix.Task.run("app.start")

alias PortfolioManager.RAG

repo_path = File.cwd!()
index_id = "portfolio_manager"

IO.puts("Indexing: #{repo_path}")
IO.puts("Index ID: #{index_id}")

case RAG.index_repo(repo_path, index_id: index_id, extensions: [".ex", ".exs", ".md"]) do
  {:ok, result} ->
    IO.puts("\nSuccess!")
    IO.puts("Files queued: #{result.files_queued}")
    IO.puts("Index ID: #{result.index_id}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

#### 8.4 examples/full_workflow.exs

```elixir
# Full Workflow Example
# Demonstrates: Index -> Query -> Graph -> Answer
# Run: mix run examples/full_workflow.exs

Mix.Task.run("app.start")

alias PortfolioManager.{RAG, Graph}

IO.puts("=== Portfolio Manager Full Workflow Demo ===\n")

# Step 1: Create knowledge graph
IO.puts("Step 1: Creating knowledge graph...")
:ok = Graph.create_graph("demo", %{type: :knowledge})
IO.puts("  Created graph: demo")

# Step 2: Add some nodes
IO.puts("\nStep 2: Adding nodes...")
nodes = [
  %{id: "workflow_engine", labels: ["Module"], properties: %{name: "WorkflowEngine", description: "Executes workflow steps"}},
  %{id: "step", labels: ["Module"], properties: %{name: "Step", description: "Base step behavior"}},
  %{id: "agent_step", labels: ["Module"], properties: %{name: "AgentStep", description: "LLM agent execution"}}
]

Enum.each(nodes, fn node ->
  {:ok, _} = Graph.add_node("demo", node)
  IO.puts("  Added: #{node.id}")
end)

# Step 3: Add edges
IO.puts("\nStep 3: Adding relationships...")
edges = [
  %{id: "e1", from_id: "workflow_engine", to_id: "step", type: "USES", properties: %{}},
  %{id: "e2", from_id: "agent_step", to_id: "step", type: "IMPLEMENTS", properties: %{}}
]

Enum.each(edges, fn edge ->
  {:ok, _} = Graph.add_edge("demo", edge)
  IO.puts("  Added: #{edge.from_id} -[#{edge.type}]-> #{edge.to_id}")
end)

# Step 4: Query the graph
IO.puts("\nStep 4: Querying graph...")
{:ok, stats} = Graph.stats("demo")
IO.puts("  Node count: #{stats.node_count}")
IO.puts("  Edge count: #{stats.edge_count}")

# Step 5: Ask a question using RAG
IO.puts("\nStep 5: RAG Query...")
question = "What components does the workflow engine use?"

case RAG.ask(question, strategy: :hybrid, k: 3) do
  {:ok, answer} ->
    IO.puts("  Question: #{question}")
    IO.puts("  Answer: #{answer}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

IO.puts("\n=== Demo Complete ===")
```

---

## Quality Requirements

### All tests must pass:
```bash
mix test
```

### No compiler warnings:
```bash
mix compile --warnings-as-errors
```

### Credo strict must pass:
```bash
mix credo --strict
```

### Dialyzer must pass:
```bash
mix dialyzer
```

### Test coverage > 80%:
```bash
mix coveralls.html
```

---

## Deliverables Checklist

### Core Refactoring
- [ ] mix.exs updated with portfolio_core and portfolio_index deps
- [ ] Application module refactored to use manifest engine
- [ ] RAG module delegates to portfolio_index strategies
- [ ] Graph module delegates to portfolio_index adapters

### Manifests
- [ ] config/manifests/development.yml
- [ ] config/manifests/test.yml
- [ ] config/manifests/production.yml

### CLI Tasks
- [ ] portfolio.ask refactored
- [ ] portfolio.index (new) created
- [ ] portfolio.search refactored
- [ ] portfolio.graph refactored

### Tests
- [ ] All existing tests pass with mocks
- [ ] New RAG tests with mocks
- [ ] New Graph tests with mocks
- [ ] Integration tests for CLI

### Examples
- [ ] examples/README.md
- [ ] examples/rag_query.exs
- [ ] examples/index_repo.exs
- [ ] examples/graph_analysis.exs
- [ ] examples/full_workflow.exs

### Documentation
- [ ] README.md updated
- [ ] CHANGELOG.md updated

### Quality
- [ ] No compiler warnings
- [ ] Credo --strict passes
- [ ] Dialyzer passes
- [ ] Test coverage > 80%
