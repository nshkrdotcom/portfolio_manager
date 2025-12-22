defmodule Mix.Tasks.Portfolio.Remove do
  @moduledoc """
  Remove a repository from the portfolio.

  ## Usage

      mix portfolio.remove <id>

  ## Options

    * `--force`, `-f` - Skip confirmation prompt
    * `--keep-docs` - Keep repos/{id}/ documents (default: delete)
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.remove my-app
      mix portfolio.remove my-app --force
      mix portfolio.remove my-app --keep-docs

  """
  @shortdoc "Remove a repository from the portfolio"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          force: :boolean,
          keep_docs: :boolean,
          json: :boolean,
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
          Exit.halt(:invalid_args)

        _ ->
          Mix.shell().error("Error: Too many arguments")
          show_help()
          Exit.halt(:invalid_args)
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
                  docs_removed = maybe_remove_docs(portfolio, repo_id, opts)

                  case PortfolioManager.sync(portfolio) do
                    :ok ->
                      :ok

                    {:error, reason} ->
                      Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
                      Exit.halt(:error)
                  end

                  if opts[:json] do
                    output_json(repo_id, docs_removed)
                  else
                    Mix.shell().info("""
                    #{IO.ANSI.green()}Removed #{repo_id} from portfolio#{IO.ANSI.reset()}
                    """)
                  end

                {:error, reason} ->
                  Mix.shell().error("Failed to remove #{repo_id}: #{inspect(reason)}")
                  Exit.halt(:error)
              end
            else
              Mix.shell().info("Cancelled")
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
            Exit.halt(:not_found)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)

        Exit.halt(:config)
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

    This will untrack the repository. Portfolio documents will be deleted unless --keep-docs is set.
    Continue?
    """)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.remove <id> [options]

    Remove a repository from the portfolio.

    Options:
      --force, -f    Skip confirmation prompt
      --keep-docs    Keep repos/{id}/ documents (default: delete)
      --json         Output as JSON
      --help         Show this help message

    Examples:
      mix portfolio.remove my-app
      mix portfolio.remove my-app --force
      mix portfolio.remove my-app --keep-docs
    """)
  end

  defp maybe_remove_docs(portfolio, repo_id, opts) do
    if opts[:keep_docs] do
      false
    else
      remove_docs(portfolio, repo_id)
      true
    end
  end

  defp remove_docs(portfolio, repo_id) do
    state = PortfolioManager.Portfolio.get_storage_state(portfolio)
    repo_path = Path.join([state.path, "repos", repo_id])
    File.rm_rf(repo_path)
  end

  defp output_json(repo_id, docs_removed) do
    data = %{
      id: repo_id,
      removed: true,
      docs_removed: docs_removed
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
