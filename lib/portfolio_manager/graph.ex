defmodule PortfolioManager.Graph do
  @moduledoc """
  Relationship graph for repository dependencies and connections.

  Provides graph operations for understanding repo relationships.
  """

  # Suppress dialyzer warnings about MapSet and queue opaque types
  # These are known issues with dialyzer's handling of opaque types
  @dialyzer [
    {:nowarn_function, do_reachable: 3},
    {:nowarn_function, do_render_tree: 7},
    {:nowarn_function, do_kahn_sort: 4},
    {:nowarn_function, kahn_sort: 1},
    {:nowarn_function, reachable_from: 2}
  ]

  @type t :: %__MODULE__{
          nodes: MapSet.t(String.t()),
          edges: [edge()],
          adjacency: %{String.t() => [String.t()]}
        }

  @type edge :: %{
          from: String.t(),
          to: String.t(),
          type: atom(),
          weight: float()
        }

  defstruct nodes: MapSet.new(), edges: [], adjacency: %{}

  @doc """
  Builds a graph from portfolio relationships.

  ## Examples

      graph = PortfolioManager.Graph.build(portfolio)

  """
  @spec build(GenServer.server()) :: t()
  def build(portfolio) do
    repos = PortfolioManager.list_repos(portfolio)
    nodes = MapSet.new(Enum.map(repos, & &1.id))

    edges =
      repos
      |> Enum.flat_map(fn repo ->
        PortfolioManager.get_relationships(portfolio, repo.id)
        |> Enum.map(fn rel ->
          %{
            from: rel.from,
            to: rel.to,
            type: rel.type,
            weight: 1.0
          }
        end)
      end)
      |> Enum.uniq_by(fn e -> {e.from, e.to, e.type} end)

    adjacency = build_adjacency(edges)

    %__MODULE__{
      nodes: nodes,
      edges: edges,
      adjacency: adjacency
    }
  end

  @doc """
  Generates ASCII visualization of the graph.

  ## Options

    * `:max_depth` - Maximum depth to display (default: 3)
    * `:root` - Root node to start from (optional)

  """
  @spec to_ascii(t(), keyword()) :: String.t()
  def to_ascii(%__MODULE__{} = graph, opts \\ []) do
    root = Keyword.get(opts, :root)
    max_depth = Keyword.get(opts, :max_depth, 3)

    if root do
      render_tree(graph, root, max_depth)
    else
      # Find roots (nodes with no incoming edges)
      roots = find_roots(graph)

      if Enum.empty?(roots) do
        # No clear roots, just show all nodes
        render_flat(graph)
      else
        Enum.map_join(roots, "\n\n", &render_tree(graph, &1, max_depth))
      end
    end
  end

  @doc """
  Exports graph to DOT format for Graphviz visualization.
  """
  @spec to_dot(t()) :: String.t()
  def to_dot(%__MODULE__{} = graph) do
    nodes_str =
      Enum.map_join(graph.nodes, "\n", fn node -> "  \"#{node}\";" end)

    edges_str =
      Enum.map_join(graph.edges, "\n", fn edge ->
        label = to_string(edge.type)
        "  \"#{edge.from}\" -> \"#{edge.to}\" [label=\"#{label}\"];"
      end)

    """
    digraph portfolio {
      rankdir=LR;
      node [shape=box];

    #{nodes_str}

    #{edges_str}
    }
    """
  end

  @doc """
  Finds a path between two repositories.

  Returns nil if no path exists.
  """
  @spec find_path(t(), String.t(), String.t()) :: [String.t()] | nil
  def find_path(%__MODULE__{} = graph, from, to) do
    bfs(graph, from, to)
  end

  @doc """
  Finds all cycles in the graph.

  Returns a list of cycles, where each cycle is a list of node IDs.
  """
  @spec find_cycles(t()) :: [[String.t()]]
  def find_cycles(%__MODULE__{} = graph) do
    graph.nodes
    |> Enum.reduce({MapSet.new(), MapSet.new(), []}, fn node, {visited, rec_stack, cycles} ->
      if MapSet.member?(visited, node) do
        {visited, rec_stack, cycles}
      else
        dfs_cycles(graph, node, visited, rec_stack, [], cycles)
      end
    end)
    |> elem(2)
    |> Enum.uniq_by(&Enum.sort/1)
  end

  @doc """
  Returns nodes in topological order.

  Returns {:error, :has_cycle} if the graph contains cycles.
  """
  @spec topo_sort(t()) :: {:ok, [String.t()]} | {:error, :has_cycle}
  def topo_sort(%__MODULE__{} = graph) do
    case find_cycles(graph) do
      [] ->
        sorted = kahn_sort(graph)
        {:ok, sorted}

      _ ->
        {:error, :has_cycle}
    end
  end

  @doc """
  Gets all nodes reachable from a given node.
  """
  @spec reachable_from(t(), String.t()) :: [String.t()]
  def reachable_from(%__MODULE__{} = graph, node) do
    do_reachable(graph, [node], MapSet.new())
    |> MapSet.to_list()
    |> Enum.reject(&(&1 == node))
  end

  @doc """
  Gets all nodes that can reach a given node (reverse reachability).
  """
  @spec can_reach(t(), String.t()) :: [String.t()]
  def can_reach(%__MODULE__{} = graph, target) do
    # Build reverse adjacency
    reverse_adj =
      Enum.reduce(graph.edges, %{}, fn edge, acc ->
        Map.update(acc, edge.to, [edge.from], &[edge.from | &1])
      end)

    reverse_graph = %{graph | adjacency: reverse_adj}
    reachable_from(reverse_graph, target)
  end

  @doc """
  Calculates degree centrality for all nodes.

  Returns a map of node_id => centrality score.
  """
  @spec centrality(t()) :: %{String.t() => float()}
  def centrality(%__MODULE__{} = graph) do
    max_degree = MapSet.size(graph.nodes) - 1
    max_degree = max(max_degree, 1)

    graph.nodes
    |> Enum.map(fn node ->
      out_degree = length(Map.get(graph.adjacency, node, []))

      in_degree =
        Enum.count(graph.edges, fn e -> e.to == node end)

      degree = out_degree + in_degree
      {node, degree / max_degree}
    end)
    |> Map.new()
  end

  # Private helpers

  defp build_adjacency(edges) do
    Enum.reduce(edges, %{}, fn edge, acc ->
      Map.update(acc, edge.from, [edge.to], &[edge.to | &1])
    end)
  end

  defp find_roots(graph) do
    targets = MapSet.new(Enum.map(graph.edges, & &1.to))

    graph.nodes
    |> Enum.filter(&(not MapSet.member?(targets, &1)))
    |> Enum.sort()
  end

  defp render_tree(graph, root, max_depth) do
    lines = do_render_tree(graph, root, "", true, 0, max_depth, MapSet.new())
    Enum.join(lines, "\n")
  end

  defp do_render_tree(_graph, node, prefix, _is_last, depth, max_depth, _visited)
       when depth > max_depth do
    [prefix <> "... (max depth reached for #{node})"]
  end

  defp do_render_tree(graph, node, prefix, is_last, depth, max_depth, visited) do
    if MapSet.member?(visited, node) do
      [prefix <> if(is_last, do: "└── ", else: "├── ") <> node <> " (circular)"]
    else
      connector = if is_last, do: "└── ", else: "├── "
      line = prefix <> connector <> node

      children = Map.get(graph.adjacency, node, []) |> Enum.sort()
      new_visited = MapSet.put(visited, node)

      child_prefix = prefix <> if is_last, do: "    ", else: "│   "

      child_lines =
        children
        |> Enum.with_index()
        |> Enum.flat_map(fn {child, idx} ->
          child_is_last = idx == length(children) - 1

          do_render_tree(
            graph,
            child,
            child_prefix,
            child_is_last,
            depth + 1,
            max_depth,
            new_visited
          )
        end)

      [line | child_lines]
    end
  end

  defp render_flat(graph) do
    graph.nodes
    |> Enum.sort()
    |> Enum.map_join("\n", fn node ->
      children = Map.get(graph.adjacency, node, [])

      if Enum.empty?(children) do
        node
      else
        "#{node} -> [#{Enum.join(children, ", ")}]"
      end
    end)
  end

  defp bfs(graph, from, to) do
    do_bfs(graph, [{from, [from]}], MapSet.new([from]), to)
  end

  defp do_bfs(_graph, [], _visited, _target), do: nil

  defp do_bfs(graph, [{current, path} | rest], visited, target) do
    if current == target do
      Enum.reverse(path)
    else
      neighbors = Map.get(graph.adjacency, current, [])

      new_items =
        neighbors
        |> Enum.reject(&MapSet.member?(visited, &1))
        |> Enum.map(fn n -> {n, [n | path]} end)

      new_visited = Enum.reduce(neighbors, visited, &MapSet.put(&2, &1))
      do_bfs(graph, rest ++ new_items, new_visited, target)
    end
  end

  defp dfs_cycles(graph, node, visited, rec_stack, path, cycles) do
    visited = MapSet.put(visited, node)
    rec_stack = MapSet.put(rec_stack, node)
    path = path ++ [node]

    neighbors = Map.get(graph.adjacency, node, [])

    {visited, rec_stack, cycles} =
      Enum.reduce(neighbors, {visited, rec_stack, cycles}, fn neighbor, {v, r, c} ->
        cond do
          MapSet.member?(r, neighbor) ->
            # Found cycle
            cycle_start = Enum.find_index(path, &(&1 == neighbor))
            cycle = Enum.drop(path, cycle_start || 0)
            {v, r, [cycle | c]}

          not MapSet.member?(v, neighbor) ->
            dfs_cycles(graph, neighbor, v, r, path, c)

          true ->
            {v, r, c}
        end
      end)

    rec_stack = MapSet.delete(rec_stack, node)
    {visited, rec_stack, cycles}
  end

  defp kahn_sort(graph) do
    # Calculate in-degrees
    in_degree =
      Enum.reduce(graph.edges, %{}, fn edge, acc ->
        Map.update(acc, edge.to, 1, &(&1 + 1))
      end)

    # Start with nodes that have no incoming edges
    queue =
      graph.nodes
      |> Enum.filter(fn n -> Map.get(in_degree, n, 0) == 0 end)
      |> :queue.from_list()

    do_kahn_sort(graph, queue, in_degree, [])
  end

  defp do_kahn_sort(_graph, {[], []}, _in_degree, result) do
    Enum.reverse(result)
  end

  defp do_kahn_sort(graph, queue, in_degree, result) do
    case :queue.out(queue) do
      {:empty, _} ->
        Enum.reverse(result)

      {{:value, node}, rest} ->
        result = [node | result]
        neighbors = Map.get(graph.adjacency, node, [])
        {new_queue, new_in_degree} = update_neighbor_degrees(neighbors, rest, in_degree)
        do_kahn_sort(graph, new_queue, new_in_degree, result)
    end
  end

  defp update_neighbor_degrees(neighbors, queue, in_degree) do
    Enum.reduce(neighbors, {queue, in_degree}, fn neighbor, {q, deg} ->
      new_deg = Map.get(deg, neighbor, 1) - 1
      deg = Map.put(deg, neighbor, new_deg)
      if new_deg == 0, do: {:queue.in(neighbor, q), deg}, else: {q, deg}
    end)
  end

  defp do_reachable(_graph, [], visited), do: visited

  defp do_reachable(graph, [node | rest], visited) do
    if MapSet.member?(visited, node) do
      do_reachable(graph, rest, visited)
    else
      visited = MapSet.put(visited, node)
      neighbors = Map.get(graph.adjacency, node, [])
      do_reachable(graph, rest ++ neighbors, visited)
    end
  end
end
