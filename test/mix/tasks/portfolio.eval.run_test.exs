defmodule Mix.Tasks.Portfolio.Eval.RunTest do
  use PortfolioManager.SupertesterCase, async: true

  alias Mix.Tasks.Portfolio.Eval.Run

  describe "parse_args/1" do
    test "parses mode option" do
      {opts, _args, _} = Run.parse_args(["--mode", "semantic"])
      assert opts[:mode] == "semantic"
    end

    test "parses collection option" do
      {opts, _args, _} = Run.parse_args(["--collection", "my-docs"])
      assert opts[:collection] == "my-docs"
    end

    test "parses generate flag" do
      {opts, _args, _} = Run.parse_args(["--generate"])
      assert opts[:generate] == true
    end

    test "parses format option" do
      {opts, _args, _} = Run.parse_args(["--format", "json"])
      assert opts[:format] == "json"
    end

    test "parses fail-under option" do
      {opts, _args, _} = Run.parse_args(["--fail-under", "0.8"])
      assert opts[:fail_under] == 0.8
    end

    test "parses help flag" do
      {opts, _args, _} = Run.parse_args(["--help"])
      assert opts[:help] == true
    end

    test "parses multiple options" do
      {opts, _args, _} =
        Run.parse_args([
          "--mode",
          "hybrid",
          "--collection",
          "docs",
          "--format",
          "json",
          "--fail-under",
          "0.9"
        ])

      assert opts[:mode] == "hybrid"
      assert opts[:collection] == "docs"
      assert opts[:format] == "json"
      assert opts[:fail_under] == 0.9
    end
  end

  describe "parse_mode/1" do
    test "converts semantic string to atom" do
      assert Run.parse_mode("semantic") == :semantic
    end

    test "converts fulltext string to atom" do
      assert Run.parse_mode("fulltext") == :fulltext
    end

    test "converts hybrid string to atom" do
      assert Run.parse_mode("hybrid") == :hybrid
    end

    test "defaults to semantic for nil" do
      assert Run.parse_mode(nil) == :semantic
    end

    test "raises for invalid mode" do
      assert_raise RuntimeError, fn ->
        Run.parse_mode("invalid")
      end
    end
  end

  describe "format_percentage/1" do
    test "formats float as percentage" do
      assert Run.format_percentage(0.856) == "85.6%"
    end

    test "formats 1.0 as 100%" do
      assert Run.format_percentage(1.0) == "100.0%"
    end

    test "formats 0.0 as 0%" do
      assert Run.format_percentage(0.0) == "0.0%"
    end
  end

  describe "check_threshold/2" do
    test "returns :ok when above threshold" do
      metrics = %{recall_at_k: %{5 => 0.9}}
      assert Run.check_threshold(metrics, 0.8) == :ok
    end

    test "returns :ok when no threshold set" do
      metrics = %{recall_at_k: %{5 => 0.5}}
      assert Run.check_threshold(metrics, nil) == :ok
    end

    test "returns :fail when below threshold" do
      metrics = %{recall_at_k: %{5 => 0.7}}
      assert Run.check_threshold(metrics, 0.8) == :fail
    end

    test "handles string keys in metrics" do
      metrics = %{"recall_at_k" => %{5 => 0.9}}
      assert Run.check_threshold(metrics, 0.8) == :ok
    end
  end
end
