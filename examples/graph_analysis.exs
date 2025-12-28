# Graph Analysis Example
# Run: mix run examples/graph_analysis.exs

Mix.Task.run("app.start")

alias PortfolioManager.Graph

graph_id = "analysis_demo"

IO.puts("Creating graph: #{graph_id}")
:ok = Graph.create_graph(graph_id, %{type: :knowledge})

IO.puts("Adding nodes and edges...")
{:ok, _} = Graph.add_node(graph_id, %{id: "node_a", labels: ["Module"], properties: %{name: "A"}})
{:ok, _} = Graph.add_node(graph_id, %{id: "node_b", labels: ["Module"], properties: %{name: "B"}})

{:ok, _} =
  Graph.add_edge(graph_id, %{
    id: "edge_ab",
    from_id: "node_a",
    to_id: "node_b",
    type: "CALLS",
    properties: %{}
  })

case Graph.stats(graph_id) do
  {:ok, stats} ->
    IO.puts("Nodes: #{stats.node_count}")
    IO.puts("Edges: #{stats.edge_count}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
