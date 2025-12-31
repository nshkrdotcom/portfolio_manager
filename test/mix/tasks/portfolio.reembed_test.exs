defmodule Mix.Tasks.Portfolio.ReembedTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Portfolio.Reembed

  describe "run/1" do
    test "prints help when --help is passed" do
      output =
        capture_io(fn ->
          Reembed.run(["--help"])
        end)

      assert output =~ "Re-embed"
      assert output =~ "--collection"
      assert output =~ "--batch-size"
    end

    test "prints dry-run message when --dry-run is passed" do
      output =
        capture_io(fn ->
          Reembed.run(["--dry-run"])
        end)

      assert output =~ "Dry run"
    end

    test "accepts --collection option" do
      output =
        capture_io(fn ->
          Reembed.run(["--collection", "docs", "--dry-run"])
        end)

      assert output =~ "docs"
    end

    test "accepts --batch-size option" do
      output =
        capture_io(fn ->
          Reembed.run(["--batch-size", "50", "--dry-run"])
        end)

      assert output =~ "50"
    end
  end

  describe "option parsing" do
    test "parses all options correctly" do
      {opts, _args, _errors} =
        OptionParser.parse(
          ["--collection", "docs", "--batch-size", "100", "--verbose", "--dry-run"],
          strict: [
            collection: :string,
            batch_size: :integer,
            verbose: :boolean,
            dry_run: :boolean
          ],
          aliases: [c: :collection, b: :batch_size, v: :verbose]
        )

      assert opts[:collection] == "docs"
      assert opts[:batch_size] == 100
      assert opts[:verbose] == true
      assert opts[:dry_run] == true
    end
  end
end
