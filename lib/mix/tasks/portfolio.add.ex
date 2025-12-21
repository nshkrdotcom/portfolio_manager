defmodule Mix.Tasks.Portfolio.Add do
  @moduledoc """
  Manually add a repository to the portfolio.

  ## Usage

      mix portfolio.add <path>

  ## Options

    * `--id` - Override auto-generated ID
    * `--type` - Set type (library, application, port)
    * `--help` - Show help message

  ## Examples

      mix portfolio.add .
      mix portfolio.add ~/projects/my-app
      mix portfolio.add . --id=my-custom-id --type=library

  """
  @shortdoc "Add a repository to the portfolio"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          id: :string,
          type: :string,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      case args do
        [path | _] ->
          add_repo(path, opts)

        [] ->
          Mix.shell().error("Missing path. Usage: mix portfolio.add <path>")
      end
    end
  end

  defp add_repo(path, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    expanded = Path.expand(path)

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        if PortfolioManager.Adapters.LocalGit.is_repo?(expanded) do
          do_add(portfolio, expanded, opts)
        else
          Mix.shell().error("#{expanded} is not a git repository.")
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
    end
  end

  defp do_add(portfolio, path, _opts) do
    case PortfolioManager.add(portfolio, path) do
      {:ok, repo} ->
        Mix.shell().info("""
        #{IO.ANSI.green()}Added repository: #{repo.id}#{IO.ANSI.reset()}

          Type:     #{repo.type}
          Language: #{repo.language}
          Path:     #{repo.path}

        Run `mix portfolio.show #{repo.id}` to see details.
        """)

      {:error, :already_exists} ->
        Mix.shell().error("Repository already exists in portfolio.")

      {:error, reason} ->
        Mix.shell().error("Failed to add repository: #{inspect(reason)}")
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.add <path>

    Manually add a repository to the portfolio.

    Options:
      --id           Override auto-generated ID
      --type         Set type (library, application, port)
      --help         Show this help message

    Examples:
      mix portfolio.add .
      mix portfolio.add ~/projects/my-app
      mix portfolio.add . --id=my-custom-id --type=library
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
