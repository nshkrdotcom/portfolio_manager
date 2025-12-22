defmodule PortfolioManager.CLI.HistoryTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.CLI.History

  setup do
    tmp_dir = System.tmp_dir!()
    path = Path.join(tmp_dir, "portfolio_history_test_#{:erlang.unique_integer([:positive])}")
    history_path = Path.join(path, "repl_history")

    on_exit(fn -> File.rm_rf(path) end)

    {:ok, history_path: history_path}
  end

  test "load returns empty list when file is missing", %{history_path: history_path} do
    assert History.load(history_path) == []
  end

  test "append writes history entries to disk", %{history_path: history_path} do
    history = History.append([], history_path, "list")
    assert history == ["list"]

    history = History.append(history, history_path, "show repo")
    assert history == ["list", "show repo"]

    assert File.read!(history_path) == "list\nshow repo\n"
  end

  test "expand resolves !n commands" do
    history = ["list", "show repo", "status"]

    assert {:ok, "show repo"} == History.expand(history, "!2")
    assert {:ok, "status"} == History.expand(history, "!3")
    assert {:error, _message} = History.expand(history, "!4")
  end

  test "expand returns input for normal commands" do
    assert {:ok, "list"} == History.expand(["list"], "list")
  end

  test "recent returns indexed subset of history" do
    history = ["a", "b", "c", "d"]
    assert History.recent(history, 2) == [{3, "c"}, {4, "d"}]
  end

  test "parse_count returns nil when invalid" do
    assert History.parse_count("") == nil
    assert History.parse_count(" foo") == nil
    assert History.parse_count(" 0") == nil
  end

  test "parse_count parses positive integers" do
    assert History.parse_count(" 5") == 5
    assert History.parse_count("10") == 10
  end
end
