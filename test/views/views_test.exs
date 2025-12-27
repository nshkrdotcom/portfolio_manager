defmodule PortfolioManager.ViewsTest do
  @moduledoc """
  Tests for computed views generation.
  """

  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.YAMLStorage
  alias PortfolioManager.Views

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "views_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)
    YAMLStorage.create(tmp_dir)
    {:ok, portfolio} = PortfolioManager.init(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir, portfolio: portfolio}
  end

  describe "generate_all/2" do
    test "creates views directory and files", %{tmp_dir: tmp_dir, portfolio: portfolio} do
      :ok = Views.generate_all(portfolio)

      views_dir = Path.join(tmp_dir, "views")
      assert File.dir?(views_dir)
      assert File.exists?(Path.join(views_dir, "by-status.yml"))
      assert File.exists?(Path.join(views_dir, "by-type.yml"))
      assert File.exists?(Path.join(views_dir, "by-language.yml"))
      assert File.exists?(Path.join(views_dir, "stale-repos.yml"))
      assert File.exists?(Path.join(views_dir, "port-status.yml"))
    end

    test "generates valid YAML files", %{tmp_dir: tmp_dir, portfolio: portfolio} do
      :ok = Views.generate_all(portfolio)

      views_dir = Path.join(tmp_dir, "views")
      {:ok, content} = File.read(Path.join(views_dir, "by-status.yml"))

      assert String.contains?(content, "generated_at:")
      assert String.contains?(content, "summary:")
    end
  end

  describe "with repos" do
    setup %{tmp_dir: tmp_dir, portfolio: portfolio} do
      # Add some test repos
      repo1_dir = Path.join([tmp_dir, "test_repos", "repo1"])
      repo2_dir = Path.join([tmp_dir, "test_repos", "repo2"])

      File.mkdir_p!(repo1_dir)
      File.mkdir_p!(repo2_dir)

      # Make them git repos
      System.cmd("git", ["init", "-b", "main"], cd: repo1_dir)
      System.cmd("git", ["init", "-b", "main"], cd: repo2_dir)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: repo1_dir)
      System.cmd("git", ["config", "user.name", "Test"], cd: repo1_dir)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: repo2_dir)
      System.cmd("git", ["config", "user.name", "Test"], cd: repo2_dir)

      # Add mix.exs to make them Elixir repos
      mix_content = """
      defmodule Test.MixProject do
        use Mix.Project
        def project, do: [app: :test, version: "0.1.0"]
      end
      """

      File.write!(Path.join(repo1_dir, "mix.exs"), mix_content)
      File.write!(Path.join(repo2_dir, "mix.exs"), mix_content)

      # Commit
      System.cmd("git", ["add", "."], cd: repo1_dir)
      System.cmd("git", ["commit", "-m", "init"], cd: repo1_dir)
      System.cmd("git", ["add", "."], cd: repo2_dir)
      System.cmd("git", ["commit", "-m", "init"], cd: repo2_dir)

      # Scan to add them
      {:ok, _} = PortfolioManager.scan(portfolio, [Path.join(tmp_dir, "test_repos")])

      {:ok, portfolio: portfolio}
    end

    test "by-status view groups repos", %{tmp_dir: tmp_dir, portfolio: portfolio} do
      :ok = Views.generate_all(portfolio)

      views_dir = Path.join(tmp_dir, "views")
      {:ok, content} = File.read(Path.join(views_dir, "by-status.yml"))

      assert String.contains?(content, "results:")
    end

    test "by-type view groups repos", %{tmp_dir: tmp_dir, portfolio: portfolio} do
      :ok = Views.generate_all(portfolio)

      views_dir = Path.join(tmp_dir, "views")
      {:ok, content} = File.read(Path.join(views_dir, "by-type.yml"))

      assert String.contains?(content, "results:")
    end
  end

  describe "stale and port views" do
    test "stale view includes active repos with zero commits", %{
      tmp_dir: tmp_dir,
      portfolio: portfolio
    } do
      repo_dir = Path.join([tmp_dir, "stale_repo"])

      PortfolioManager.TestHelpers.create_test_repo(repo_dir,
        name: "stale_repo",
        language: :elixir
      )

      {:ok, repo} = PortfolioManager.add(portfolio, repo_dir)

      {:ok, _} =
        PortfolioManager.update_context(portfolio, repo.id, %{
          status: :active,
          computed: %{"commit_count_30d" => 0}
        })

      :ok = Views.generate_stale_repos(portfolio, PortfolioManager.list_repos(portfolio))

      views_dir = Path.join(tmp_dir, "views")
      {:ok, data} = YamlElixir.read_from_file(Path.join(views_dir, "stale-repos.yml"))

      results = Map.get(data, "results", [])
      assert Enum.any?(results, fn item -> item["id"] == repo.id end)
    end

    test "port-status view includes upstream metadata", %{
      tmp_dir: tmp_dir,
      portfolio: portfolio
    } do
      repo_dir = Path.join([tmp_dir, "port_repo"])

      PortfolioManager.TestHelpers.create_test_repo(repo_dir,
        name: "port_repo",
        language: :elixir
      )

      {:ok, repo} = PortfolioManager.add(portfolio, repo_dir)

      {:ok, _} =
        PortfolioManager.update_context(portfolio, repo.id, %{
          type: :port,
          port: %{
            "upstream_url" => "https://github.com/example/upstream",
            "upstream_version" => "v2.0.0",
            "synced_version" => "v1.0.0",
            "commits_behind" => 5
          }
        })

      :ok = Views.generate_port_status(portfolio, PortfolioManager.list_repos(portfolio))

      views_dir = Path.join(tmp_dir, "views")
      {:ok, data} = YamlElixir.read_from_file(Path.join(views_dir, "port-status.yml"))

      results = Map.get(data, "results", [])

      assert Enum.any?(results, fn item ->
               item["id"] == repo.id and item["upstream"] == "https://github.com/example/upstream" and
                 item["status"] == "needs_sync"
             end)
    end
  end
end
