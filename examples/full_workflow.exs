# Full Workflow Example
# Demonstrates: Index -> Graph -> Answer
# Run: mix run examples/full_workflow.exs

Mix.Task.run("app.start")

alias PortfolioManager.{RAG, Graph}

IO.puts("=== Portfolio Manager Full Workflow Demo ===\n")

repo_path = File.cwd!()
index_id = System.get_env("PORTFOLIO_INDEX_ID") || "default"

# Step 1: Index repository (enqueue ingestion)
IO.puts("Step 1: Indexing repository...")

index_ready? =
  case RAG.index_repo(repo_path, index_id: index_id, extensions: [".ex", ".exs", ".md"]) do
    {:ok, result} ->
      IO.puts("  Queued #{result.files_queued} files for ingestion")
      IO.puts("  Index ID: #{result.index_id}")
      true

    {:error, reason} ->
      IO.puts("  Error: #{inspect(reason)}")
      false
  end

# Step 2: Create knowledge graph
IO.puts("\nStep 2: Creating knowledge graph...")
:ok = Graph.create_graph("demo", %{type: :knowledge})
IO.puts("  Created graph: demo")

# Step 3: Add some nodes
IO.puts("\nStep 3: Adding nodes...")

nodes = [
  %{
    id: "workflow_engine",
    labels: ["Module"],
    properties: %{name: "WorkflowEngine", description: "Executes workflow steps"}
  },
  %{
    id: "step",
    labels: ["Module"],
    properties: %{name: "Step", description: "Base step behavior"}
  },
  %{
    id: "agent_step",
    labels: ["Module"],
    properties: %{name: "AgentStep", description: "LLM agent execution"}
  }
]

Enum.each(nodes, fn node ->
  {:ok, _} = Graph.add_node("demo", node)
  IO.puts("  Added: #{node.id}")
end)

# Step 4: Add edges
IO.puts("\nStep 4: Adding relationships...")

edges = [
  %{id: "e1", from_id: "workflow_engine", to_id: "step", type: "USES", properties: %{}},
  %{id: "e2", from_id: "agent_step", to_id: "step", type: "IMPLEMENTS", properties: %{}}
]

Enum.each(edges, fn edge ->
  {:ok, _} = Graph.add_edge("demo", edge)
  IO.puts("  Added: #{edge.from_id} -[#{edge.type}]-> #{edge.to_id}")
end)

# Step 5: Query the graph
IO.puts("\nStep 5: Querying graph...")
{:ok, stats} = Graph.stats("demo")
IO.puts("  Node count: #{stats.node_count}")
IO.puts("  Edge count: #{stats.edge_count}")

# Step 6: Ask a question using RAG
if index_ready? do
  IO.puts("\nStep 6: RAG Query...")
  question = "What components does the workflow engine use?"

  case RAG.ask(question, strategy: :hybrid, k: 3, index_id: index_id) do
    {:ok, answer} ->
      IO.puts("  Question: #{question}")
      IO.puts("  Answer: #{answer}")

    {:error, reason} ->
      IO.puts("  Error: #{inspect(reason)}")
  end
else
  IO.puts("\nStep 6: RAG Query skipped (indexing failed).")
end

IO.puts("\n=== Demo Complete ===")
