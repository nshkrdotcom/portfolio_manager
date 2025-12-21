# Example 14: Relationship Graph
#
# This example demonstrates:
# - Building a relationship graph from portfolio
# - Graph visualization (ASCII and DOT format)
# - Path finding between repositories
# - Cycle detection
# - Topological sorting
# - Reachability analysis
# - Centrality metrics
#
# Run with: mix run examples/14_relationship_graph.exs

alias PortfolioManager.Graph

IO.puts("""
================================================================================
Example 14: Relationship Graph
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_PATH") || "/tmp/portfolio_manager_examples"

case PortfolioManager.init(portfolio_path) do
  {:ok, portfolio} ->
    repos = PortfolioManager.list_repos(portfolio)

    IO.puts("Portfolio has #{length(repos)} repositories\n")

    # For a meaningful graph demo, we need multiple repos with relationships
    # Let's create some if we only have one
    if length(repos) < 3 do
      IO.puts("--- Creating Demo Repositories for Graph ---")
      IO.puts("(Need at least 3 repos to demonstrate graph features)")
      IO.puts("")

      # Create temporary repos
      base_dir = System.tmp_dir!()

      demo_repos =
        for name <- ["core-lib", "api-service", "web-frontend"] do
          dir = Path.join(base_dir, "graph_demo_#{name}_#{:rand.uniform(1000)}")
          File.mkdir_p!(dir)
          File.write!(Path.join(dir, "README.md"), "# #{name}")

          {_, 0} = System.cmd("git", ["init"], cd: dir, stderr_to_stdout: true)
          {_, 0} = System.cmd("git", ["add", "."], cd: dir, stderr_to_stdout: true)
          {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: dir, stderr_to_stdout: true)

          case PortfolioManager.add(portfolio, dir) do
            {:ok, repo} ->
              IO.puts("  Added: #{repo.id}")
              repo

            {:error, _} ->
              nil
          end
        end
        |> Enum.reject(&is_nil/1)

      if length(demo_repos) >= 3 do
        [core, api, web] = demo_repos

        # Create relationships
        IO.puts("\n  Creating relationships...")
        PortfolioManager.add_relationship(portfolio, api.id, core.id, :depends_on)
        PortfolioManager.add_relationship(portfolio, web.id, api.id, :depends_on)
        PortfolioManager.add_relationship(portfolio, web.id, core.id, :depends_on)
        IO.puts("  #{api.id} -> #{core.id} (depends_on)")
        IO.puts("  #{web.id} -> #{api.id} (depends_on)")
        IO.puts("  #{web.id} -> #{core.id} (depends_on)")
      end

      IO.puts("")
    end

    # --- Build the graph ---
    IO.puts("--- Building Relationship Graph ---")
    graph = Graph.build(portfolio)

    IO.puts("  Nodes: #{MapSet.size(graph.nodes)}")
    IO.puts("  Edges: #{length(graph.edges)}")
    IO.puts("")

    # --- ASCII Visualization ---
    IO.puts("--- ASCII Tree Visualization ---")

    if length(graph.edges) > 0 do
      ascii = Graph.to_ascii(graph, max_depth: 5)
      IO.puts(ascii)
    else
      IO.puts("  (No relationships to visualize)")
      IO.puts("  Add relationships with PortfolioManager.add_relationship/4")
    end

    IO.puts("")

    # --- DOT Format (for Graphviz) ---
    IO.puts("--- DOT Format (Graphviz) ---")
    dot = Graph.to_dot(graph)
    IO.puts(dot)

    # Save to file
    dot_file = Path.join(portfolio_path, "portfolio_graph.dot")
    File.write!(dot_file, dot)
    IO.puts("  Saved to: #{dot_file}")
    IO.puts("  View with: dot -Tpng #{dot_file} -o graph.png")
    IO.puts("")

    # --- Path Finding ---
    IO.puts("--- Path Finding ---")

    nodes = MapSet.to_list(graph.nodes)

    if length(nodes) >= 2 do
      [from | rest] = nodes
      to = List.last(rest)

      IO.puts("  Finding path from '#{from}' to '#{to}'...")

      case Graph.find_path(graph, from, to) do
        nil ->
          IO.puts("  No path found")

        path ->
          IO.puts("  Path: #{Enum.join(path, " -> ")}")
      end
    else
      IO.puts("  Need at least 2 nodes for path finding")
    end

    IO.puts("")

    # --- Cycle Detection ---
    IO.puts("--- Cycle Detection ---")
    cycles = Graph.find_cycles(graph)

    if Enum.empty?(cycles) do
      IO.puts("  No cycles detected (graph is acyclic)")
    else
      IO.puts("  Found #{length(cycles)} cycle(s):")

      Enum.each(cycles, fn cycle ->
        IO.puts("    #{Enum.join(cycle, " -> ")} -> #{List.first(cycle)}")
      end)
    end

    IO.puts("")

    # --- Topological Sort ---
    IO.puts("--- Topological Sort (Build Order) ---")

    case Graph.topo_sort(graph) do
      {:ok, order} ->
        IO.puts("  Build order:")

        order
        |> Enum.with_index(1)
        |> Enum.each(fn {node, idx} ->
          IO.puts("    #{idx}. #{node}")
        end)

      {:error, :has_cycle} ->
        IO.puts("  Cannot sort - graph has cycles")
    end

    IO.puts("")

    # --- Reachability ---
    IO.puts("--- Reachability Analysis ---")

    if length(nodes) > 0 do
      node = List.first(nodes)

      reachable = Graph.reachable_from(graph, node)
      IO.puts("  From '#{node}' can reach: #{inspect(reachable)}")

      can_reach = Graph.can_reach(graph, node)
      IO.puts("  Can reach '#{node}': #{inspect(can_reach)}")
    end

    IO.puts("")

    # --- Centrality ---
    IO.puts("--- Centrality Metrics ---")
    centrality = Graph.centrality(graph)

    centrality
    |> Enum.sort_by(fn {_, score} -> -score end)
    |> Enum.each(fn {node, score} ->
      bar = String.duplicate("#", round(score * 20))
      IO.puts("  #{String.pad_trailing(node, 20)} #{Float.round(score, 2)} #{bar}")
    end)

    # Save portfolio
    PortfolioManager.sync(portfolio)

  {:error, reason} ->
    IO.puts("Failed to initialize portfolio: #{inspect(reason)}")
    IO.puts("Run example 01 first to set up the portfolio.")
end

IO.puts("""

================================================================================
Example 14 Complete!
================================================================================
Demonstrated relationship graph operations:
- Building graphs from portfolio relationships
- ASCII and DOT visualization
- Path finding, cycle detection, topological sort
- Reachability analysis and centrality metrics
""")
