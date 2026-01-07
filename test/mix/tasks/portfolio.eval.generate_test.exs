defmodule Mix.Tasks.Portfolio.Eval.GenerateTest do
  use PortfolioManager.SupertesterCase, async: true

  alias Mix.Tasks.Portfolio.Eval.Generate

  describe "parse_args/1" do
    test "parses sample-size option" do
      {opts, _args, _} = Generate.parse_args(["--sample-size", "50"])
      assert opts[:sample_size] == 50
    end

    test "parses collection option" do
      {opts, _args, _} = Generate.parse_args(["--collection", "my-docs"])
      assert opts[:collection] == "my-docs"
    end

    test "parses source-id option" do
      {opts, _args, _} = Generate.parse_args(["--source-id", "project-a"])
      assert opts[:source_id] == "project-a"
    end

    test "parses help flag" do
      {opts, _args, _} = Generate.parse_args(["--help"])
      assert opts[:help] == true
    end

    test "parses multiple options" do
      {opts, _args, _} =
        Generate.parse_args([
          "--sample-size",
          "100",
          "--collection",
          "docs",
          "--source-id",
          "proj"
        ])

      assert opts[:sample_size] == 100
      assert opts[:collection] == "docs"
      assert opts[:source_id] == "proj"
    end

    test "defaults sample-size to nil when not provided" do
      {opts, _args, _} = Generate.parse_args([])
      assert opts[:sample_size] == nil
    end
  end

  describe "build_generator_opts/1" do
    test "includes sample_size when provided" do
      parsed = [sample_size: 50]
      opts = Generate.build_generator_opts(parsed)
      assert opts[:sample_size] == 50
    end

    test "excludes nil values" do
      parsed = [sample_size: nil, collection: "docs"]
      opts = Generate.build_generator_opts(parsed)
      refute Keyword.has_key?(opts, :sample_size)
      assert opts[:collection] == "docs"
    end
  end
end
