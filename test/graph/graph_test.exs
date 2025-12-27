defmodule PortfolioManager.GraphTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Graph

  import PortfolioManager.TestHelpers

  setup do
    path = create_populated_portfolio()
    {:ok, portfolio} = PortfolioManager.init(path)

    on_exit(fn -> cleanup_test_portfolio(path) end)

    {:ok, portfolio: portfolio}
  end

  test "build/1 includes nodes and edges", %{portfolio: portfolio} do
    graph = Graph.build(portfolio)

    assert MapSet.member?(graph.nodes, "repo-a")
    assert MapSet.member?(graph.nodes, "repo-b")

    assert Enum.any?(graph.edges, fn edge ->
             edge.from == "repo-b" and edge.to == "repo-a"
           end)
  end

  test "to_ascii/2 renders graph output", %{portfolio: portfolio} do
    graph = Graph.build(portfolio)
    ascii = Graph.to_ascii(graph)

    assert is_binary(ascii)
    assert String.contains?(ascii, "repo-a")
  end

  test "to_dot/1 renders dot format", %{portfolio: portfolio} do
    graph = Graph.build(portfolio)
    dot = Graph.to_dot(graph)

    assert String.contains?(dot, "digraph portfolio")
    assert String.contains?(dot, "\"repo-b\" -> \"repo-a\"")
  end

  test "find_path/3 returns a path when one exists", %{portfolio: portfolio} do
    graph = Graph.build(portfolio)

    assert Graph.find_path(graph, "repo-b", "repo-a") == ["repo-b", "repo-a"]
  end

  test "find_cycles/1 detects cycles", %{portfolio: portfolio} do
    {:ok, _} = PortfolioManager.add_relationship(portfolio, "repo-a", "repo-b", :depends_on)
    graph = Graph.build(portfolio)

    cycles = Graph.find_cycles(graph)
    assert cycles != []
    assert Enum.any?(cycles, fn cycle -> Enum.sort(cycle) == ["repo-a", "repo-b"] end)
  end

  test "topo_sort/1 returns error on cycles", %{portfolio: portfolio} do
    {:ok, _} = PortfolioManager.add_relationship(portfolio, "repo-a", "repo-b", :depends_on)
    graph = Graph.build(portfolio)

    assert {:error, :has_cycle} = Graph.topo_sort(graph)
  end

  test "topo_sort/1 returns order when acyclic", %{portfolio: portfolio} do
    graph = Graph.build(portfolio)

    assert {:ok, order} = Graph.topo_sort(graph)
    assert "repo-b" in order
    assert "repo-a" in order
  end
end
