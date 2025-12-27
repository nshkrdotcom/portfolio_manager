# Multi-Graph Architecture: Federation, Neo4j, and Graph-of-Graphs

**Expert:** Dr. Sarah Okonkwo, Senior Fellow Graph Database Architect
**Experience:** 15+ years at Neo4j, TigerGraph, Enterprise Knowledge Graphs

---

## Table of Contents

1. [Multi-Graph Concepts](#multi-graph-concepts)
2. [Graph Namespace Architecture](#graph-namespace-architecture)
3. [Graph-of-Graphs Design](#graph-of-graphs-design)
4. [Neo4j Integration Patterns](#neo4j-integration-patterns)
5. [GraphRAG at Scale](#graphrag-at-scale)
6. [Cross-Graph Query Patterns](#cross-graph-query-patterns)
7. [Complete Schema Design](#complete-schema-design)

---

## 1. Multi-Graph Concepts

### 1.1 Why Multi-Graph?

In a portfolio-scale RAG system, a single monolithic graph becomes:
- **Unmanageable**: Millions of entities across hundreds of repos
- **Polluted**: Unrelated concepts from different domains intermix
- **Slow**: Global queries traverse irrelevant subgraphs
- **Inflexible**: Cannot apply different schemas per domain

**Solution**: Hierarchical multi-graph architecture with explicit boundaries.

### 1.2 Graph Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ECOSYSTEM GRAPH                                │
│  Purpose: Connect all domain graphs, track dependencies                  │
│  Entities: DomainNode, RepoNode, LibraryNode                            │
│  Edges: DEPENDS_ON, SHARES_SCHEMA, IMPORTS, USES_LIBRARY                │
└─────────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  DOMAIN GRAPH   │  │  DOMAIN GRAPH   │  │  DOMAIN GRAPH   │
│  (e.g., Auth)   │  │  (e.g., API)    │  │  (e.g., Data)   │
│                 │  │                 │  │                 │
│  Concepts,      │  │  Concepts,      │  │  Concepts,      │
│  Relationships  │  │  Relationships  │  │  Relationships  │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
    ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
    ▼         ▼          ▼         ▼          ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│ REPO  │ │ REPO  │ │ REPO  │ │ REPO  │ │ REPO  │ │ REPO  │
│ GRAPH │ │ GRAPH │ │ GRAPH │ │ GRAPH │ │ GRAPH │ │ GRAPH │
│ (1)   │ │ (2)   │ │ (3)   │ │ (4)   │ │ (5)   │ │ (6)   │
└───────┘ └───────┘ └───────┘ └───────┘ └───────┘ └───────┘
```

### 1.3 Graph Types

| Graph Type | Purpose | Typical Size | Update Frequency |
|------------|---------|--------------|------------------|
| **Repo Graph** | Code entities for one repository | 1K-100K entities | On commit |
| **Domain Graph** | Cross-repo concepts for a domain | 10K-1M entities | Daily |
| **Ecosystem Graph** | Meta-relationships between domains/repos | 100-10K entities | Weekly |
| **Community Graph** | Detected communities and summaries | 100-10K entities | On demand |

---

## 2. Graph Namespace Architecture

### 2.1 Namespace Schema

Every graph operation includes a `graph_id` to ensure isolation:

```elixir
defmodule PortfolioCore.Domain.GraphNamespace do
  @moduledoc """
  Represents a graph namespace with its configuration.
  """

  @type t :: %__MODULE__{
    id: String.t(),
    type: :repo | :domain | :ecosystem | :community,
    parent_id: String.t() | nil,
    config: map(),
    metadata: map()
  }

  defstruct [:id, :type, :parent_id, config: %{}, metadata: %{}]

  @doc """
  Generate a canonical graph_id for a repository.
  """
  def repo_graph_id(repo_id) do
    "repo:#{repo_id}"
  end

  @doc """
  Generate a canonical graph_id for a domain.
  """
  def domain_graph_id(domain_name) do
    "domain:#{domain_name}"
  end

  @doc """
  Get the ecosystem graph_id.
  """
  def ecosystem_graph_id do
    "ecosystem:main"
  end
end
```

### 2.2 Namespace Registry

```elixir
defmodule PortfolioManager.GraphRegistry do
  @moduledoc """
  Registry for managing graph namespaces and their adapters.
  """

  use GenServer

  defstruct namespaces: %{}, adapters: %{}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @doc """
  Register a new graph namespace.
  """
  def register_namespace(namespace) do
    GenServer.call(__MODULE__, {:register, namespace})
  end

  @doc """
  Get the adapter for a graph namespace.
  """
  def get_adapter(graph_id) do
    GenServer.call(__MODULE__, {:get_adapter, graph_id})
  end

  @doc """
  List all namespaces of a given type.
  """
  def list_namespaces(type) do
    GenServer.call(__MODULE__, {:list, type})
  end

  @impl true
  def handle_call({:register, namespace}, _from, state) do
    new_namespaces = Map.put(state.namespaces, namespace.id, namespace)
    {:reply, :ok, %{state | namespaces: new_namespaces}}
  end

  def handle_call({:get_adapter, graph_id}, _from, state) do
    case Map.get(state.namespaces, graph_id) do
      nil -> {:reply, {:error, :not_found}, state}
      namespace ->
        adapter = resolve_adapter(namespace, state)
        {:reply, {:ok, adapter}, state}
    end
  end

  def handle_call({:list, type}, _from, state) do
    namespaces = state.namespaces
    |> Map.values()
    |> Enum.filter(&(&1.type == type))
    {:reply, {:ok, namespaces}, state}
  end

  defp resolve_adapter(namespace, state) do
    # Return cached adapter or create new one
    Map.get(state.adapters, namespace.id) ||
      create_adapter(namespace)
  end

  defp create_adapter(namespace) do
    # Would create and cache adapter based on namespace config
    namespace
  end
end
```

### 2.3 Namespace-Aware Operations

```elixir
defmodule PortfolioManager.GraphOperations do
  @moduledoc """
  High-level graph operations that respect namespace boundaries.
  """

  alias PortfolioManager.GraphRegistry
  alias PortfolioCore.Ports.GraphStorePort

  @doc """
  Insert an entity into the appropriate graph based on context.
  """
  def insert_entity(entity, opts \\ []) do
    graph_id = entity.graph_id || determine_graph_id(entity, opts)

    with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id),
         entity = %{entity | graph_id: graph_id} do
      adapter.insert_entity(entity)
    end
  end

  @doc """
  Traverse within a single graph namespace.
  """
  def traverse(graph_id, entity_id, opts \\ []) do
    with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id) do
      adapter.traverse(graph_id, entity_id, opts)
    end
  end

  @doc """
  Traverse across graph namespaces (cross-graph).
  """
  def traverse_cross_graph(start_graph_id, entity_id, opts \\ []) do
    max_depth = Keyword.get(opts, :depth, 3)
    max_graphs = Keyword.get(opts, :max_graphs, 5)

    do_cross_graph_traversal(start_graph_id, entity_id, max_depth, max_graphs, MapSet.new())
  end

  defp do_cross_graph_traversal(_, _, 0, _, _visited), do: {:ok, []}
  defp do_cross_graph_traversal(graph_id, entity_id, depth, max_graphs, visited) do
    if MapSet.size(visited) >= max_graphs do
      {:ok, []}
    else
      with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id),
           {:ok, local_results} <- adapter.traverse(graph_id, entity_id, depth: 1),
           {:ok, cross_edges} <- get_cross_graph_edges(graph_id, entity_id) do

        # Follow cross-graph edges
        cross_results = Enum.flat_map(cross_edges, fn edge ->
          new_visited = MapSet.put(visited, graph_id)

          case do_cross_graph_traversal(edge.to_graph_id, edge.to_entity_id,
                                         depth - 1, max_graphs, new_visited) do
            {:ok, results} -> results
            _ -> []
          end
        end)

        {:ok, local_results ++ cross_results}
      end
    end
  end

  defp get_cross_graph_edges(graph_id, entity_id) do
    # Query ecosystem graph for cross-graph edges
    ecosystem_id = PortfolioCore.Domain.GraphNamespace.ecosystem_graph_id()

    with {:ok, adapter} <- GraphRegistry.get_adapter(ecosystem_id) do
      adapter.get_edges_from(ecosystem_id, "#{graph_id}:#{entity_id}")
    end
  end

  defp determine_graph_id(entity, opts) do
    cond do
      opts[:repo_id] -> "repo:#{opts[:repo_id]}"
      opts[:domain] -> "domain:#{opts[:domain]}"
      entity.metadata[:repo_id] -> "repo:#{entity.metadata[:repo_id]}"
      true -> "repo:default"
    end
  end
end
```

---

## 3. Graph-of-Graphs Design

### 3.1 Meta-Graph Structure

The ecosystem graph treats other graphs as first-class entities:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ECOSYSTEM META-GRAPH                             │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐     DEPENDS_ON      ┌─────────────┐                   │
│  │ GraphNode   │ ─────────────────▶  │ GraphNode   │                   │
│  │ repo:auth   │                     │ repo:core   │                   │
│  └──────┬──────┘                     └──────┬──────┘                   │
│         │                                   │                           │
│         │ BELONGS_TO                        │ BELONGS_TO                │
│         ▼                                   ▼                           │
│  ┌─────────────┐                     ┌─────────────┐                   │
│  │ DomainNode  │ ◀───SHARES_SCHEMA───│ DomainNode  │                   │
│  │ domain:auth │                     │ domain:core │                   │
│  └─────────────┘                     └─────────────┘                   │
│                                                                         │
│  Cross-Graph Entity Links:                                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ EntityRef{graph:repo:auth, entity:User}                          │   │
│  │     │                                                            │   │
│  │     │ SAME_AS                                                    │   │
│  │     ▼                                                            │   │
│  │ EntityRef{graph:repo:api, entity:AuthenticatedUser}              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Meta-Graph Entity Types

```elixir
defmodule PortfolioCore.Domain.MetaGraph do
  @moduledoc """
  Entity types for the ecosystem meta-graph.
  """

  defmodule GraphNode do
    @moduledoc "Represents a graph namespace in the meta-graph"

    defstruct [
      :id,
      :graph_id,
      :type,
      :name,
      :description,
      :entity_count,
      :edge_count,
      :created_at,
      :updated_at,
      metadata: %{}
    ]
  end

  defmodule DomainNode do
    @moduledoc "Represents a domain grouping in the meta-graph"

    defstruct [
      :id,
      :name,
      :description,
      :repo_graph_ids,
      :concept_summary,
      metadata: %{}
    ]
  end

  defmodule EntityRef do
    @moduledoc "Reference to an entity in another graph"

    defstruct [
      :id,
      :source_graph_id,
      :source_entity_id,
      :source_entity_type,
      :source_entity_name
    ]
  end

  defmodule CrossGraphEdge do
    @moduledoc "Edge connecting entities across different graphs"

    defstruct [
      :id,
      :from_graph_id,
      :from_entity_id,
      :to_graph_id,
      :to_entity_id,
      :type,
      :weight,
      :evidence,  # Why this link exists
      metadata: %{}
    ]
  end
end
```

### 3.3 Meta-Graph Operations

```elixir
defmodule PortfolioManager.MetaGraph do
  @moduledoc """
  Operations on the ecosystem meta-graph.
  """

  alias PortfolioCore.Domain.MetaGraph.{GraphNode, DomainNode, CrossGraphEdge, EntityRef}
  alias PortfolioCore.Domain.GraphNamespace

  @ecosystem_id GraphNamespace.ecosystem_graph_id()

  @doc """
  Register a new repo graph in the ecosystem.
  """
  def register_repo_graph(repo_id, opts \\ []) do
    graph_node = %GraphNode{
      id: UUID.uuid4(),
      graph_id: GraphNamespace.repo_graph_id(repo_id),
      type: :repo,
      name: repo_id,
      description: opts[:description],
      entity_count: 0,
      edge_count: 0,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }

    with {:ok, adapter} <- get_ecosystem_adapter() do
      adapter.insert_entity(to_entity(graph_node))
    end
  end

  @doc """
  Create a cross-graph link between entities.
  """
  def link_entities(from_graph, from_entity, to_graph, to_entity, type, opts \\ []) do
    edge = %CrossGraphEdge{
      id: UUID.uuid4(),
      from_graph_id: from_graph,
      from_entity_id: from_entity,
      to_graph_id: to_graph,
      to_entity_id: to_entity,
      type: type,
      weight: opts[:weight] || 1.0,
      evidence: opts[:evidence],
      metadata: opts[:metadata] || %{}
    }

    with {:ok, adapter} <- get_ecosystem_adapter() do
      # Store as edge in ecosystem graph
      adapter.insert_edge(to_edge(edge))
    end
  end

  @doc """
  Find all graphs that a given graph depends on.
  """
  def get_dependencies(graph_id) do
    with {:ok, adapter} <- get_ecosystem_adapter() do
      adapter.traverse(@ecosystem_id, graph_id, [
        edge_types: ["DEPENDS_ON", "IMPORTS", "USES_LIBRARY"],
        direction: :outgoing,
        depth: 1
      ])
    end
  end

  @doc """
  Find all graphs that depend on a given graph.
  """
  def get_dependents(graph_id) do
    with {:ok, adapter} <- get_ecosystem_adapter() do
      adapter.traverse(@ecosystem_id, graph_id, [
        edge_types: ["DEPENDS_ON", "IMPORTS", "USES_LIBRARY"],
        direction: :incoming,
        depth: 1
      ])
    end
  end

  @doc """
  Find related entities across graphs.
  """
  def find_related_entities(graph_id, entity_id, opts \\ []) do
    with {:ok, adapter} <- get_ecosystem_adapter(),
         entity_ref = build_entity_ref(graph_id, entity_id),
         {:ok, edges} <- adapter.neighbors(@ecosystem_id, entity_ref.id, opts) do
      # Resolve each reference back to the actual entity
      resolve_entity_refs(edges)
    end
  end

  @doc """
  Detect and create cross-graph links based on entity similarity.
  """
  def detect_cross_graph_links(opts \\ []) do
    threshold = opts[:similarity_threshold] || 0.85

    # Get all entity embeddings from all graphs
    # Compare across graphs to find similar entities
    # Create SAME_AS or SIMILAR_TO edges

    {:ok, :not_implemented}
  end

  defp get_ecosystem_adapter do
    PortfolioManager.GraphRegistry.get_adapter(@ecosystem_id)
  end

  defp to_entity(%GraphNode{} = node) do
    %{
      id: node.id,
      graph_id: @ecosystem_id,
      type: "GraphNode",
      name: node.name,
      properties: Map.from_struct(node)
    }
  end

  defp to_edge(%CrossGraphEdge{} = edge) do
    %{
      id: edge.id,
      graph_id: @ecosystem_id,
      from_id: "#{edge.from_graph_id}:#{edge.from_entity_id}",
      to_id: "#{edge.to_graph_id}:#{edge.to_entity_id}",
      type: edge.type,
      weight: edge.weight,
      properties: %{evidence: edge.evidence, metadata: edge.metadata}
    }
  end

  defp build_entity_ref(graph_id, entity_id) do
    %EntityRef{
      id: "#{graph_id}:#{entity_id}",
      source_graph_id: graph_id,
      source_entity_id: entity_id
    }
  end

  defp resolve_entity_refs(edges) do
    # Resolve references to actual entities
    {:ok, edges}
  end
end
```

---

## 4. Neo4j Integration Patterns

### 4.1 Neo4j Adapter with Multi-Database Support

```elixir
defmodule PortfolioIndex.Adapters.Neo4j do
  @moduledoc """
  Neo4j adapter supporting multi-database for graph isolation.

  Each graph_id maps to a Neo4j database (Enterprise) or
  a label prefix (Community Edition).
  """

  use PortfolioIndex.Adapter, port: PortfolioCore.Ports.GraphStorePort
  use GenServer

  alias Bolt.Sips, as: Bolt

  defstruct [:conn, :config, :multi_db, :database_map]

  @impl PortfolioIndex.Adapter
  def capabilities do
    [:multi_database, :cypher, :traversal, :community_detection, :full_text_search]
  end

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl GenServer
  def init(config) do
    bolt_config = [
      url: config[:uri],
      basic_auth: [username: config[:username], password: config[:password]],
      pool_size: config[:pool_size] || 20
    ]

    case Bolt.start_link(bolt_config) do
      {:ok, conn} ->
        state = %__MODULE__{
          conn: conn,
          config: config,
          multi_db: config[:multi_database] || false,
          database_map: %{}
        }
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # GraphStorePort Implementation

  @impl PortfolioCore.Ports.GraphStorePort
  def create_graph(graph_id, opts) do
    GenServer.call(__MODULE__, {:create_graph, graph_id, opts})
  end

  @impl GenServer
  def handle_call({:create_graph, graph_id, opts}, _from, %{multi_db: true} = state) do
    # Create a new database for this graph (Neo4j Enterprise)
    db_name = sanitize_db_name(graph_id)
    query = "CREATE DATABASE $db_name IF NOT EXISTS"

    case execute(state.conn, query, %{db_name: db_name}, database: "system") do
      {:ok, _} ->
        new_map = Map.put(state.database_map, graph_id, db_name)
        {:reply, {:ok, graph_id}, %{state | database_map: new_map}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_graph, graph_id, _opts}, _from, %{multi_db: false} = state) do
    # Community Edition: Use label prefixes
    new_map = Map.put(state.database_map, graph_id, graph_id)
    {:reply, {:ok, graph_id}, %{state | database_map: new_map}}
  end

  @impl PortfolioCore.Ports.GraphStorePort
  def insert_entity(entity) do
    GenServer.call(__MODULE__, {:insert_entity, entity})
  end

  @impl GenServer
  def handle_call({:insert_entity, entity}, _from, state) do
    db = get_database(state, entity.graph_id)
    label = entity_label(state, entity)

    query = """
    CREATE (e:#{label} {
      id: $id,
      type: $type,
      name: $name,
      properties: $properties,
      embedding: $embedding,
      source_chunk_ids: $source_chunk_ids
    })
    RETURN e.id as id
    """

    params = %{
      id: entity.id || UUID.uuid4(),
      type: entity.type,
      name: entity.name,
      properties: Jason.encode!(entity.properties),
      embedding: entity.embedding,
      source_chunk_ids: entity.source_chunk_ids
    }

    case execute(state.conn, query, params, database: db) do
      {:ok, [%{"id" => id}]} -> {:reply, {:ok, id}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl PortfolioCore.Ports.GraphStorePort
  def insert_edge(edge) do
    GenServer.call(__MODULE__, {:insert_edge, edge})
  end

  @impl GenServer
  def handle_call({:insert_edge, edge}, _from, state) do
    db = get_database(state, edge.graph_id)
    from_label = entity_label(state, %{graph_id: edge.graph_id})
    to_label = from_label

    query = """
    MATCH (from:#{from_label} {id: $from_id})
    MATCH (to:#{to_label} {id: $to_id})
    CREATE (from)-[r:#{edge.type} {
      id: $id,
      weight: $weight,
      properties: $properties
    }]->(to)
    RETURN r.id as id
    """

    params = %{
      id: edge.id || UUID.uuid4(),
      from_id: edge.from_id,
      to_id: edge.to_id,
      weight: edge.weight,
      properties: Jason.encode!(edge.properties)
    }

    case execute(state.conn, query, params, database: db) do
      {:ok, [%{"id" => id}]} -> {:reply, {:ok, id}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl PortfolioCore.Ports.GraphStorePort
  def traverse(graph_id, entity_id, opts) do
    GenServer.call(__MODULE__, {:traverse, graph_id, entity_id, opts})
  end

  @impl GenServer
  def handle_call({:traverse, graph_id, entity_id, opts}, _from, state) do
    db = get_database(state, graph_id)
    label = entity_label(state, %{graph_id: graph_id})
    depth = Keyword.get(opts, :depth, 2)
    edge_types = Keyword.get(opts, :edge_types, [])
    direction = Keyword.get(opts, :direction, :both)

    rel_pattern = build_relationship_pattern(edge_types, direction)

    query = """
    MATCH (start:#{label} {id: $entity_id})
    MATCH path = (start)#{rel_pattern}*1..#{depth}(end:#{label})
    RETURN DISTINCT end {
      .id, .type, .name, .properties, .embedding, .source_chunk_ids
    } as entity
    LIMIT $limit
    """

    params = %{
      entity_id: entity_id,
      limit: Keyword.get(opts, :limit, 100)
    }

    case execute(state.conn, query, params, database: db) do
      {:ok, results} ->
        entities = Enum.map(results, &parse_entity/1)
        {:reply, {:ok, entities}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl PortfolioCore.Ports.GraphStorePort
  def search_by_embedding(graph_id, embedding, opts) do
    GenServer.call(__MODULE__, {:search_embedding, graph_id, embedding, opts})
  end

  @impl GenServer
  def handle_call({:search_embedding, graph_id, embedding, opts}, _from, state) do
    db = get_database(state, graph_id)
    label = entity_label(state, %{graph_id: graph_id})
    limit = Keyword.get(opts, :limit, 10)

    # Requires Neo4j vector index
    query = """
    CALL db.index.vector.queryNodes($index_name, $limit, $embedding)
    YIELD node, score
    WHERE node:#{label}
    RETURN node {.id, .type, .name, .properties} as entity, score
    """

    params = %{
      index_name: "#{label}_embedding_index",
      limit: limit,
      embedding: embedding
    }

    case execute(state.conn, query, params, database: db) do
      {:ok, results} ->
        entities = Enum.map(results, fn r ->
          %{entity: parse_entity(r), score: r["score"]}
        end)
        {:reply, {:ok, entities}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl PortfolioCore.Ports.GraphStorePort
  def detect_communities(graph_id, algorithm, opts) do
    GenServer.call(__MODULE__, {:detect_communities, graph_id, algorithm, opts}, 60_000)
  end

  @impl GenServer
  def handle_call({:detect_communities, graph_id, algorithm, opts}, _from, state) do
    db = get_database(state, graph_id)
    label = entity_label(state, %{graph_id: graph_id})

    # Using Neo4j Graph Data Science library
    query = case algorithm do
      :louvain -> build_louvain_query(label, opts)
      :leiden -> build_leiden_query(label, opts)
      :label_propagation -> build_lpa_query(label, opts)
    end

    case execute(state.conn, query, %{}, database: db) do
      {:ok, results} ->
        communities = parse_communities(results, graph_id)
        {:reply, {:ok, communities}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Cross-Graph Operations

  @impl PortfolioCore.Ports.GraphStorePort
  def create_cross_graph_edge(from_graph, from_entity, to_graph, to_entity, edge_type) do
    GenServer.call(__MODULE__, {:cross_graph_edge, from_graph, from_entity, to_graph, to_entity, edge_type})
  end

  @impl GenServer
  def handle_call({:cross_graph_edge, from_graph, from_entity, to_graph, to_entity, edge_type}, _from, state) do
    # For Neo4j Enterprise with Fabric, we can query across databases
    # For Community, store in ecosystem graph

    if state.multi_db do
      query = """
      USE fabric
      MATCH (from:Entity {id: $from_id}) IN `#{from_graph}`
      MATCH (to:Entity {id: $to_id}) IN `#{to_graph}`
      CREATE (from)-[r:#{edge_type} {cross_graph: true}]->(to)
      RETURN id(r) as id
      """

      case execute(state.conn, query, %{from_id: from_entity, to_id: to_entity}) do
        {:ok, [%{"id" => id}]} -> {:reply, {:ok, id}, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      # Store in ecosystem graph as entity references
      edge = %{
        id: UUID.uuid4(),
        graph_id: "ecosystem:main",
        from_id: "#{from_graph}:#{from_entity}",
        to_id: "#{to_graph}:#{to_entity}",
        type: edge_type,
        weight: 1.0,
        properties: %{cross_graph: true}
      }

      handle_call({:insert_edge, edge}, nil, state)
    end
  end

  # Private Helpers

  defp get_database(state, graph_id) do
    if state.multi_db do
      Map.get(state.database_map, graph_id, "neo4j")
    else
      "neo4j"
    end
  end

  defp entity_label(state, entity) do
    if state.multi_db do
      "Entity"
    else
      # Prefix labels for isolation in single database
      prefix = String.replace(entity.graph_id, ":", "_")
      "#{prefix}_Entity"
    end
  end

  defp sanitize_db_name(graph_id) do
    graph_id
    |> String.replace(":", "_")
    |> String.replace("-", "_")
    |> String.downcase()
  end

  defp build_relationship_pattern([], :both), do: "-[]-"
  defp build_relationship_pattern([], :outgoing), do: "->[]"
  defp build_relationship_pattern([], :incoming), do: "<-[]"
  defp build_relationship_pattern(types, :both) do
    types_str = Enum.join(types, "|")
    "-[:#{types_str}]-"
  end
  defp build_relationship_pattern(types, :outgoing) do
    types_str = Enum.join(types, "|")
    "-[:#{types_str}]->"
  end
  defp build_relationship_pattern(types, :incoming) do
    types_str = Enum.join(types, "|")
    "<-[:#{types_str}]-"
  end

  defp build_louvain_query(label, _opts) do
    """
    CALL gds.louvain.stream({
      nodeQuery: 'MATCH (n:#{label}) RETURN id(n) AS id',
      relationshipQuery: 'MATCH (n:#{label})-[r]->(m:#{label}) RETURN id(n) AS source, id(m) AS target'
    })
    YIELD nodeId, communityId
    RETURN gds.util.asNode(nodeId).id AS entityId, communityId
    ORDER BY communityId
    """
  end

  defp build_leiden_query(label, _opts) do
    """
    CALL gds.leiden.stream({
      nodeQuery: 'MATCH (n:#{label}) RETURN id(n) AS id',
      relationshipQuery: 'MATCH (n:#{label})-[r]->(m:#{label}) RETURN id(n) AS source, id(m) AS target'
    })
    YIELD nodeId, communityId
    RETURN gds.util.asNode(nodeId).id AS entityId, communityId
    ORDER BY communityId
    """
  end

  defp build_lpa_query(label, _opts) do
    """
    CALL gds.labelPropagation.stream({
      nodeQuery: 'MATCH (n:#{label}) RETURN id(n) AS id',
      relationshipQuery: 'MATCH (n:#{label})-[r]->(m:#{label}) RETURN id(n) AS source, id(m) AS target'
    })
    YIELD nodeId, communityId
    RETURN gds.util.asNode(nodeId).id AS entityId, communityId
    ORDER BY communityId
    """
  end

  defp parse_entity(%{"entity" => entity}) do
    %{
      id: entity["id"],
      type: entity["type"],
      name: entity["name"],
      properties: Jason.decode!(entity["properties"] || "{}"),
      embedding: entity["embedding"],
      source_chunk_ids: entity["source_chunk_ids"]
    }
  end

  defp parse_communities(results, graph_id) do
    results
    |> Enum.group_by(& &1["communityId"])
    |> Enum.map(fn {community_id, members} ->
      %{
        id: "#{graph_id}:community:#{community_id}",
        graph_id: graph_id,
        level: 0,
        entity_ids: Enum.map(members, & &1["entityId"]),
        summary: nil  # Would be generated by LLM
      }
    end)
  end

  defp execute(conn, query, params, opts \\ []) do
    Bolt.query(conn, query, params, opts)
  end
end
```

---

## 5. GraphRAG at Scale

### 5.1 Community Detection Pipeline

```elixir
defmodule PortfolioManager.GraphRAG.CommunityPipeline do
  @moduledoc """
  Pipeline for detecting communities and generating summaries.
  """

  alias PortfolioManager.GraphRegistry
  alias PortfolioCore.Ports.GraphStorePort

  @doc """
  Run community detection on a graph and generate hierarchical summaries.
  """
  def detect_and_summarize(graph_id, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :louvain)
    levels = Keyword.get(opts, :levels, 3)

    with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id),
         {:ok, communities} <- adapter.detect_communities(graph_id, algorithm, opts),
         {:ok, summarized} <- summarize_communities(communities, adapter, opts),
         {:ok, hierarchical} <- build_hierarchy(summarized, levels, adapter, opts) do
      {:ok, hierarchical}
    end
  end

  defp summarize_communities(communities, _adapter, opts) do
    summarizer = Keyword.get(opts, :summarizer, &default_summarizer/1)

    summarized = Enum.map(communities, fn community ->
      summary = summarizer.(community)
      %{community | summary: summary}
    end)

    {:ok, summarized}
  end

  defp build_hierarchy(communities, max_levels, adapter, opts) do
    # Build hierarchical communities by recursively clustering
    do_build_hierarchy(communities, 1, max_levels, adapter, opts)
  end

  defp do_build_hierarchy(communities, level, max_levels, _adapter, _opts)
       when level >= max_levels do
    {:ok, communities}
  end

  defp do_build_hierarchy(communities, level, max_levels, adapter, opts) do
    # Cluster communities at this level to form next level
    # This creates a meta-community structure
    {:ok, communities}
  end

  defp default_summarizer(community) do
    # Would call LLM to generate summary
    "Community with #{length(community.entity_ids)} entities"
  end
end
```

### 5.2 Graph-Aware Retrieval

```elixir
defmodule PortfolioManager.GraphRAG.Retriever do
  @moduledoc """
  Hybrid retriever combining vector search with graph traversal.
  """

  alias PortfolioManager.GraphRegistry
  alias PortfolioManager.VectorRegistry

  @doc """
  Retrieve relevant context using combined vector + graph strategies.
  """
  def retrieve(query, opts \\ []) do
    mode = Keyword.get(opts, :mode, :hybrid)

    case mode do
      :local -> retrieve_local(query, opts)
      :global -> retrieve_global(query, opts)
      :hybrid -> retrieve_hybrid(query, opts)
    end
  end

  @doc """
  Local retrieval: Vector search + entity expansion.
  """
  def retrieve_local(query, opts) do
    graph_id = Keyword.get(opts, :graph_id)
    expansion_depth = Keyword.get(opts, :expansion_depth, 2)

    with {:ok, embedding} <- embed_query(query),
         {:ok, chunks} <- vector_search(embedding, opts),
         {:ok, entities} <- extract_related_entities(chunks, graph_id),
         {:ok, expanded} <- expand_entities(entities, graph_id, expansion_depth) do
      {:ok, %{
        chunks: chunks,
        entities: entities,
        expanded_entities: expanded,
        mode: :local
      }}
    end
  end

  @doc """
  Global retrieval: Community summaries + high-level context.
  """
  def retrieve_global(query, opts) do
    graph_id = Keyword.get(opts, :graph_id)

    with {:ok, embedding} <- embed_query(query),
         {:ok, communities} <- search_communities(embedding, graph_id, opts),
         {:ok, context} <- build_global_context(communities) do
      {:ok, %{
        communities: communities,
        context: context,
        mode: :global
      }}
    end
  end

  @doc """
  Hybrid retrieval: Combine local and global.
  """
  def retrieve_hybrid(query, opts) do
    local_weight = Keyword.get(opts, :local_weight, 0.6)
    global_weight = Keyword.get(opts, :global_weight, 0.4)

    with {:ok, local} <- retrieve_local(query, opts),
         {:ok, global} <- retrieve_global(query, opts) do
      {:ok, %{
        local: local,
        global: global,
        weights: %{local: local_weight, global: global_weight},
        mode: :hybrid
      }}
    end
  end

  defp embed_query(query) do
    # Use embedder port
    {:ok, []}
  end

  defp vector_search(embedding, opts) do
    index_id = Keyword.get(opts, :index_id, :default)

    with {:ok, adapter} <- VectorRegistry.get_adapter(index_id) do
      adapter.search(embedding, opts)
    end
  end

  defp extract_related_entities(chunks, graph_id) do
    # Find entities mentioned in chunks
    {:ok, []}
  end

  defp expand_entities(entities, graph_id, depth) do
    with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id) do
      Enum.flat_map(entities, fn entity ->
        case adapter.traverse(graph_id, entity.id, depth: depth) do
          {:ok, neighbors} -> neighbors
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.id)
      |> then(&{:ok, &1})
    end
  end

  defp search_communities(embedding, graph_id, opts) do
    with {:ok, adapter} <- GraphRegistry.get_adapter(graph_id) do
      adapter.search_by_embedding(graph_id, embedding, opts)
    end
  end

  defp build_global_context(communities) do
    context = communities
    |> Enum.map(& &1.summary)
    |> Enum.join("\n\n")

    {:ok, context}
  end
end
```

---

## 6. Cross-Graph Query Patterns

### 6.1 Query Router

```elixir
defmodule PortfolioManager.GraphQuery.Router do
  @moduledoc """
  Routes queries to appropriate graphs based on query analysis.
  """

  @doc """
  Analyze query and determine which graphs to query.
  """
  def route(query, opts \\ []) do
    # Analyze query to determine scope
    scope = analyze_query_scope(query)

    case scope do
      {:repo, repo_id} ->
        {:single, PortfolioCore.Domain.GraphNamespace.repo_graph_id(repo_id)}

      {:domain, domain} ->
        # Query all repos in domain
        with {:ok, repo_graphs} <- get_domain_repos(domain) do
          {:multi, repo_graphs}
        end

      :ecosystem ->
        # Cross-domain query
        {:ecosystem, PortfolioCore.Domain.GraphNamespace.ecosystem_graph_id()}

      :unknown ->
        # Default to all accessible graphs
        with {:ok, all_graphs} <- list_accessible_graphs(opts) do
          {:multi, all_graphs}
        end
    end
  end

  defp analyze_query_scope(query) do
    cond do
      String.contains?(query, "@repo:") ->
        repo_id = extract_repo_id(query)
        {:repo, repo_id}

      String.contains?(query, "@domain:") ->
        domain = extract_domain(query)
        {:domain, domain}

      String.contains?(query, "@ecosystem") ->
        :ecosystem

      true ->
        :unknown
    end
  end

  defp extract_repo_id(query) do
    case Regex.run(~r/@repo:(\S+)/, query) do
      [_, repo_id] -> repo_id
      _ -> nil
    end
  end

  defp extract_domain(query) do
    case Regex.run(~r/@domain:(\S+)/, query) do
      [_, domain] -> domain
      _ -> nil
    end
  end

  defp get_domain_repos(domain) do
    PortfolioManager.MetaGraph.get_domain_repos(domain)
  end

  defp list_accessible_graphs(_opts) do
    PortfolioManager.GraphRegistry.list_namespaces(:repo)
  end
end
```

### 6.2 Federated Query Executor

```elixir
defmodule PortfolioManager.GraphQuery.Federated do
  @moduledoc """
  Executes queries across multiple graphs and merges results.
  """

  @doc """
  Execute a query across multiple graphs in parallel.
  """
  def execute(query, graph_ids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    merge_strategy = Keyword.get(opts, :merge, :union)

    tasks = Enum.map(graph_ids, fn graph_id ->
      Task.async(fn ->
        execute_on_graph(query, graph_id, opts)
      end)
    end)

    results = Task.await_many(tasks, timeout)

    merge_results(results, merge_strategy)
  end

  defp execute_on_graph(query, graph_id, opts) do
    with {:ok, adapter} <- PortfolioManager.GraphRegistry.get_adapter(graph_id) do
      case query do
        {:search, embedding} ->
          adapter.search_by_embedding(graph_id, embedding, opts)

        {:traverse, entity_id, traverse_opts} ->
          adapter.traverse(graph_id, entity_id, traverse_opts)

        {:neighbors, entity_id} ->
          adapter.neighbors(graph_id, entity_id, opts)
      end
    end
  end

  defp merge_results(results, :union) do
    results
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.flat_map(fn {:ok, items} -> items end)
    |> Enum.uniq_by(&entity_key/1)
    |> then(&{:ok, &1})
  end

  defp merge_results(results, :intersection) do
    [first | rest] = results
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, items} -> MapSet.new(items, &entity_key/1) end)

    common = Enum.reduce(rest, first, &MapSet.intersection/2)

    results
    |> Enum.flat_map(fn {:ok, items} -> items end)
    |> Enum.filter(fn item -> MapSet.member?(common, entity_key(item)) end)
    |> Enum.uniq_by(&entity_key/1)
    |> then(&{:ok, &1})
  end

  defp entity_key(%{id: id}), do: id
  defp entity_key(%{entity_id: id}), do: id
  defp entity_key(other), do: :erlang.phash2(other)
end
```

---

## 7. Complete Schema Design

### 7.1 PostgreSQL Graph Tables

```sql
-- Graph namespaces registry
CREATE TABLE graph_namespaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id VARCHAR(255) UNIQUE NOT NULL,
  type VARCHAR(50) NOT NULL CHECK (type IN ('repo', 'domain', 'ecosystem', 'community')),
  parent_id VARCHAR(255) REFERENCES graph_namespaces(graph_id),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  config JSONB DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  entity_count INTEGER DEFAULT 0,
  edge_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_namespaces_type ON graph_namespaces(type);
CREATE INDEX idx_namespaces_parent ON graph_namespaces(parent_id);

-- Graph entities with graph_id namespace
CREATE TABLE graph_entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(graph_id),
  type VARCHAR(100) NOT NULL,
  name VARCHAR(500) NOT NULL,
  properties JSONB DEFAULT '{}',
  embedding vector(1536),
  source_chunk_ids UUID[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(graph_id, id)
);

-- Partition entities by graph_id for large scale
CREATE INDEX idx_entities_graph ON graph_entities(graph_id);
CREATE INDEX idx_entities_type ON graph_entities(graph_id, type);
CREATE INDEX idx_entities_name ON graph_entities(graph_id, name);
CREATE INDEX idx_entities_embedding ON graph_entities USING ivfflat (embedding vector_cosine_ops);

-- Graph edges with graph_id namespace
CREATE TABLE graph_edges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(graph_id),
  from_id UUID NOT NULL,
  to_id UUID NOT NULL,
  type VARCHAR(100) NOT NULL,
  weight FLOAT DEFAULT 1.0,
  properties JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  FOREIGN KEY (graph_id, from_id) REFERENCES graph_entities(graph_id, id),
  FOREIGN KEY (graph_id, to_id) REFERENCES graph_entities(graph_id, id)
);

CREATE INDEX idx_edges_graph ON graph_edges(graph_id);
CREATE INDEX idx_edges_from ON graph_edges(graph_id, from_id);
CREATE INDEX idx_edges_to ON graph_edges(graph_id, to_id);
CREATE INDEX idx_edges_type ON graph_edges(graph_id, type);

-- Cross-graph edges (stored in ecosystem namespace)
CREATE TABLE cross_graph_edges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_graph_id VARCHAR(255) NOT NULL,
  from_entity_id UUID NOT NULL,
  to_graph_id VARCHAR(255) NOT NULL,
  to_entity_id UUID NOT NULL,
  type VARCHAR(100) NOT NULL,
  weight FLOAT DEFAULT 1.0,
  evidence TEXT,
  properties JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_cross_edges_from ON cross_graph_edges(from_graph_id, from_entity_id);
CREATE INDEX idx_cross_edges_to ON cross_graph_edges(to_graph_id, to_entity_id);
CREATE INDEX idx_cross_edges_type ON cross_graph_edges(type);

-- Communities with hierarchy
CREATE TABLE graph_communities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  graph_id VARCHAR(255) NOT NULL REFERENCES graph_namespaces(graph_id),
  level INTEGER NOT NULL DEFAULT 0,
  parent_community_id UUID REFERENCES graph_communities(id),
  summary TEXT,
  entity_ids UUID[] NOT NULL,
  centroid vector(1536),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_communities_graph ON graph_communities(graph_id);
CREATE INDEX idx_communities_level ON graph_communities(graph_id, level);
CREATE INDEX idx_communities_parent ON graph_communities(parent_community_id);
```

### 7.2 Neo4j Schema (Cypher)

```cypher
// Constraints for entity uniqueness per graph
CREATE CONSTRAINT entity_unique IF NOT EXISTS
FOR (e:Entity) REQUIRE (e.graph_id, e.id) IS UNIQUE;

// Index for graph_id lookups
CREATE INDEX entity_graph_idx IF NOT EXISTS
FOR (e:Entity) ON (e.graph_id);

// Index for entity type
CREATE INDEX entity_type_idx IF NOT EXISTS
FOR (e:Entity) ON (e.type);

// Vector index for embeddings (Neo4j 5.x+)
CREATE VECTOR INDEX entity_embedding_idx IF NOT EXISTS
FOR (e:Entity) ON (e.embedding)
OPTIONS {indexConfig: {
  `vector.dimensions`: 1536,
  `vector.similarity_function`: 'cosine'
}};

// Community node type
CREATE CONSTRAINT community_unique IF NOT EXISTS
FOR (c:Community) REQUIRE (c.graph_id, c.id) IS UNIQUE;

// Meta-graph nodes
CREATE CONSTRAINT graph_node_unique IF NOT EXISTS
FOR (g:GraphNode) REQUIRE g.graph_id IS UNIQUE;

CREATE CONSTRAINT domain_node_unique IF NOT EXISTS
FOR (d:DomainNode) REQUIRE d.name IS UNIQUE;
```

---

## Summary

This multi-graph architecture provides:

1. **Graph Namespacing**: Every entity belongs to exactly one `graph_id`
2. **Hierarchical Graphs**: Repo → Domain → Ecosystem structure
3. **Graph-of-Graphs**: Meta-graph tracks relationships between graphs
4. **Neo4j Integration**: Multi-database support with fallback to label prefixes
5. **Cross-Graph Queries**: Federated query execution with merge strategies
6. **GraphRAG**: Community detection and hierarchical summarization
7. **Complete Schemas**: Both PostgreSQL and Neo4j implementations

The architecture scales from single-repo graphs to ecosystem-wide knowledge graphs while maintaining query isolation and performance.
