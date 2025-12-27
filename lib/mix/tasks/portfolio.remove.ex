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
      {:ok, portfolio} -> handle_remove(portfolio, repo_id, opts)
      {:error, :not_initialized} -> handle_not_initialized(portfolio_path)
    end
  end

  defp handle_remove(portfolio, repo_id, opts) do
    case PortfolioManager.get_repo(portfolio, repo_id) do
      {:ok, repo} -> maybe_confirm_and_remove(portfolio, repo, repo_id, opts)
      {:error, :not_found} -> handle_not_found(repo_id)
    end
  end

  defp maybe_confirm_and_remove(portfolio, repo, repo_id, opts) do
    if opts[:force] || confirm_removal(repo) do
      do_remove(portfolio, repo_id, opts)
    else
      Mix.shell().info("Cancelled")
    end
  end

  defp do_remove(portfolio, repo_id, opts) do
    case PortfolioManager.remove(portfolio, repo_id) do
      :ok -> finalize_removal(portfolio, repo_id, opts)
      {:error, reason} -> handle_remove_error(repo_id, reason)
    end
  end

  defp finalize_removal(portfolio, repo_id, opts) do
    docs_removed = maybe_remove_docs(portfolio, repo_id, opts)
    sync_portfolio(portfolio)
    output_removal_result(repo_id, docs_removed, opts)
  end

  defp sync_portfolio(portfolio) do
    case PortfolioManager.sync(portfolio) do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
        Exit.halt(:error)
    end
  end

  defp output_removal_result(repo_id, docs_removed, opts) do
    if opts[:json] do
      output_json(repo_id, docs_removed)
    else
      output_removal_text(repo_id)
    end
  end

  defp output_removal_text(repo_id) do
    Mix.shell().info("""
    #{IO.ANSI.green()}Removed #{repo_id} from portfolio#{IO.ANSI.reset()}
    """)
  end

  defp handle_remove_error(repo_id, reason) do
    Mix.shell().error("Failed to remove #{repo_id}: #{inspect(reason)}")
    Exit.halt(:error)
  end

  defp handle_not_found(repo_id) do
    Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
    Exit.halt(:not_found)
  end

  defp handle_not_initialized(portfolio_path) do
    Mix.shell().error("""
    Portfolio not found at #{portfolio_path}
    Run `mix portfolio.init` first.
    """)

    Exit.halt(:config)
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
