defmodule Mix.Tasks.Portfolio.Remove do
  @moduledoc """
  Remove a repository from the portfolio.

  ## Usage

      mix portfolio.remove <id>

  ## Options

    * `--force`, `-f` - Skip confirmation prompt
    * `--help` - Show help message

  ## Examples

      mix portfolio.remove my-app
      mix portfolio.remove my-app --force

  """
  @shortdoc "Remove a repository from the portfolio"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          force: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [f: :force, d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      case args do
        [repo_id] ->
          remove_repo(repo_id, opts)

        [] ->
          Mix.shell().error("Error: Repository ID is required")
          show_help()

        _ ->
          Mix.shell().error("Error: Too many arguments")
          show_help()
      end
    end
  end

  defp remove_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, repo} ->
            if opts[:force] || confirm_removal(repo) do
              case PortfolioManager.remove(portfolio, repo_id) do
                :ok ->
                  PortfolioManager.sync(portfolio)

                  Mix.shell().info("""
                  #{IO.ANSI.green()}Removed #{repo_id} from portfolio#{IO.ANSI.reset()}
                  """)

                {:error, reason} ->
                  Mix.shell().error("Failed to remove #{repo_id}: #{inspect(reason)}")
              end
            else
              Mix.shell().info("Cancelled")
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)
    end
  end

  defp confirm_removal(repo) do
    Mix.shell().yes?("""
    Remove repository?

      ID:       #{repo.id}
      Name:     #{repo.name}
      Path:     #{repo.path}
      Type:     #{repo.type}
      Language: #{repo.language}

    This will untrack the repository. The actual files will not be deleted.
    Continue?
    """)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.remove <id> [options]

    Remove a repository from the portfolio.

    Options:
      --force, -f    Skip confirmation prompt
      --help         Show this help message

    Examples:
      mix portfolio.remove my-app
      mix portfolio.remove my-app --force
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
