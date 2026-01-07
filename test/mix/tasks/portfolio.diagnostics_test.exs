defmodule Mix.Tasks.Portfolio.DiagnosticsTest do
  use PortfolioManager.SupertesterCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Portfolio.Diagnostics

  describe "run/1" do
    test "prints diagnostics header" do
      output =
        capture_io(fn ->
          # Use --dry-run to avoid needing database
          Diagnostics.run(["--dry-run"])
        end)

      assert output =~ "Diagnostics"
    end

    test "shows help with --help flag" do
      output =
        capture_io(fn ->
          Diagnostics.run(["--help"])
        end)

      assert output =~ "diagnostics"
      assert output =~ "Usage"
    end
  end

  describe "option parsing" do
    test "parses options correctly" do
      {opts, _args, _errors} =
        OptionParser.parse(
          ["--format", "json", "--help"],
          strict: [
            format: :string,
            help: :boolean
          ]
        )

      assert opts[:format] == "json"
      assert opts[:help] == true
    end
  end
end
