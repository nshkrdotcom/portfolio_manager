defmodule PortfolioManager.TestHelpers do
  @moduledoc """
  Helper functions for testing PortfolioManager.
  """

  @doc """
  Creates a temporary portfolio directory for testing.
  Returns the path to the directory.
  """
  def create_test_portfolio do
    tmp_dir = System.tmp_dir!()
    portfolio_path = Path.join(tmp_dir, "portfolio_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(portfolio_path)
    File.mkdir_p!(Path.join(portfolio_path, "repos"))

    # Create minimal registry
    File.write!(
      Path.join(portfolio_path, "registry.yml"),
      "repos: []\n"
    )

    # Create minimal relationships
    File.write!(
      Path.join(portfolio_path, "relationships.yml"),
      "relationships: []\n"
    )

    # Create config
    File.write!(
      Path.join(portfolio_path, "config.yml"),
      """
      version: "1.0"
      scan:
        directories: []
      """
    )

    portfolio_path
  end

  @doc """
  Creates a test git repository at the given path.
  """
  def create_test_repo(path, opts \\ []) do
    name = Keyword.get(opts, :name, "test-repo")
    language = Keyword.get(opts, :language, :elixir)

    File.mkdir_p!(path)

    # Initialize git repo
    System.cmd("git", ["init"], cd: path)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: path)
    System.cmd("git", ["config", "user.name", "Test User"], cd: path)

    # Create language-specific files
    case language do
      :elixir ->
        File.write!(Path.join(path, "mix.exs"), """
        defmodule #{Macro.camelize(name)}.MixProject do
          use Mix.Project

          def project do
            [app: :#{name}, version: "0.1.0"]
          end
        end
        """)

        File.mkdir_p!(Path.join(path, "lib"))

        File.write!(Path.join(path, "lib/#{name}.ex"), """
        defmodule #{Macro.camelize(name)} do
        end
        """)

      :python ->
        File.write!(Path.join(path, "setup.py"), """
        from setuptools import setup
        setup(name='#{name}', version='0.1.0')
        """)

      :javascript ->
        File.write!(Path.join(path, "package.json"), """
        {"name": "#{name}", "version": "0.1.0"}
        """)

      _ ->
        File.write!(Path.join(path, "README.md"), "# #{name}\n")
    end

    # Commit files
    System.cmd("git", ["add", "-A"], cd: path)
    System.cmd("git", ["commit", "-m", "Initial commit"], cd: path)

    path
  end

  @doc """
  Cleans up a test portfolio directory.
  """
  def cleanup_test_portfolio(path) do
    File.rm_rf!(path)
  end

  @doc """
  Cleans up a test repo directory.
  """
  def cleanup_test_repo(path) do
    File.rm_rf!(path)
  end

  @doc """
  Creates a test portfolio with some pre-populated repos.
  """
  def create_populated_portfolio do
    portfolio_path = create_test_portfolio()

    # Create registry with some repos
    repos = [
      %{
        "id" => "repo-a",
        "name" => "Repo A",
        "path" => "/tmp/repo-a",
        "type" => "library",
        "status" => "active",
        "language" => "elixir"
      },
      %{
        "id" => "repo-b",
        "name" => "Repo B",
        "path" => "/tmp/repo-b",
        "type" => "application",
        "status" => "active",
        "language" => "elixir"
      },
      %{
        "id" => "repo-c",
        "name" => "Repo C",
        "path" => "/tmp/repo-c",
        "type" => "port",
        "status" => "stale",
        "language" => "python"
      }
    ]

    File.write!(
      Path.join(portfolio_path, "registry.yml"),
      "repos:\n" <> encode_repos(repos)
    )

    # Create relationships
    rels = [
      %{
        "from" => "repo-b",
        "to" => "repo-a",
        "type" => "depends_on"
      }
    ]

    File.write!(
      Path.join(portfolio_path, "relationships.yml"),
      "relationships:\n" <> encode_rels(rels)
    )

    # Create context files for each repo
    for repo <- repos do
      repo_dir = Path.join([portfolio_path, "repos", repo["id"]])
      File.mkdir_p!(repo_dir)

      File.write!(
        Path.join(repo_dir, "context.yml"),
        """
        id: #{repo["id"]}
        name: #{repo["name"]}
        type: #{repo["type"]}
        status: #{repo["status"]}
        language: #{repo["language"]}
        """
      )
    end

    portfolio_path
  end

  defp encode_repos(repos) do
    repos
    |> Enum.map(fn repo ->
      """
        - id: #{repo["id"]}
          name: #{repo["name"]}
          path: #{repo["path"]}
          type: #{repo["type"]}
          status: #{repo["status"]}
          language: #{repo["language"]}
      """
    end)
    |> Enum.join("")
  end

  defp encode_rels(rels) do
    rels
    |> Enum.map(fn rel ->
      """
        - from: #{rel["from"]}
          to: #{rel["to"]}
          type: #{rel["type"]}
      """
    end)
    |> Enum.join("")
  end
end
