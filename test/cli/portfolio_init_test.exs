defmodule Mix.Tasks.Portfolio.InitTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Portfolio.Init
  alias PortfolioManager.Adapters.YAMLStorage

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "portfolio_cli_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "mix portfolio.init" do
    test "creates portfolio in specified path", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          Init.run([tmp_dir])
        end)

      assert output =~ "Initialized portfolio"
      assert File.exists?(Path.join(tmp_dir, "registry.yml"))
      assert File.exists?(Path.join(tmp_dir, "config.yml"))
      assert File.dir?(Path.join(tmp_dir, "repos"))
    end

    test "fails if directory already exists and is a portfolio", %{tmp_dir: tmp_dir} do
      # Create portfolio first
      YAMLStorage.create(tmp_dir)

      output =
        capture_io(:stderr, fn ->
          Init.run([tmp_dir])
        end)

      assert output =~ "already" or output =~ "exists"
    end

    test "shows help with --help" do
      output =
        capture_io(fn ->
          Init.run(["--help"])
        end)

      assert output =~ "Usage"
      assert output =~ "portfolio.init"
    end

    test "uses PORTFOLIO_DIR when no path is provided", %{tmp_dir: tmp_dir} do
      System.put_env("PORTFOLIO_DIR", tmp_dir)

      on_exit(fn -> System.delete_env("PORTFOLIO_DIR") end)

      output =
        capture_io(fn ->
          Init.run([])
        end)

      assert output =~ tmp_dir
      assert File.exists?(Path.join(tmp_dir, "registry.yml"))
      assert File.exists?(Path.join(tmp_dir, "config.yml"))
      assert File.dir?(Path.join(tmp_dir, "repos"))
    end
  end
end
