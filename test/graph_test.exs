defmodule PortfolioManager.GraphTest do
  use PortfolioManager.SupertesterCase, async: false

  import Mox

  alias PortfolioManager.Graph
  alias PortfolioManager.Mocks

  setup :verify_on_exit!

  setup do
    PortfolioCore.Registry.register(:graph_store, Mocks.GraphStore, [])

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
      |> expect(:get_neighbors, fn graph_id, node_id, _opts ->
        assert graph_id == "test_graph"
        assert node_id == "node1"
        {:ok, [%{id: "node2", labels: [], properties: %{}}]}
      end)

      assert {:ok, neighbors} = Graph.neighbors("test_graph", "node1")
      assert length(neighbors) == 1
    end
  end
end
