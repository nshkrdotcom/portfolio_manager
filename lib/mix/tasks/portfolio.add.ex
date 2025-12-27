defmodule Mix.Tasks.Portfolio.Add do
  @moduledoc """
  Manually add a repository to the portfolio.

  ## Usage

      mix portfolio.add <path>

  ## Options

    * `--id` - Override auto-generated ID
    * `--type` - Set type (library, application, port)
    * `--status` - Set status (active, stale, etc.)
    * `--detect` - Run detection after add (default: true)
    * `--no-detect` - Skip detection
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.add .
      mix portfolio.add ~/projects/my-app
      mix portfolio.add . --id=my-custom-id --type=library --status=active

  """
  @shortdoc "Add a repository to the portfolio"

  use Mix.Task

  alias PortfolioManager.Adapters.LocalGit
  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          id: :string,
          type: :string,
          status: :string,
          detect: :boolean,
          no_detect: :boolean,
          json: :boolean,
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
          Exit.halt(:invalid_args)
      end
    end
  end

  defp add_repo(path, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    expanded = Path.expand(path)

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        if LocalGit.is_repo?(expanded) do
          do_add(portfolio, expanded, opts)
        else
          Mix.shell().error("#{expanded} is not a git repository.")
          Exit.halt(:git)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
        Exit.halt(:config)
    end
  end

  defp do_add(portfolio, path, opts) do
    add_opts = build_add_opts(opts)

    case PortfolioManager.add(portfolio, path, add_opts) do
      {:ok, repo} -> handle_add_success(portfolio, repo, opts)
      {:error, :already_exists} -> handle_add_error(:already_exists)
      {:error, reason} -> handle_add_error(reason)
    end
  end

  defp build_add_opts(opts) do
    detect? = should_detect?(opts)

    []
    |> maybe_put_opt(:id, opts[:id])
    |> maybe_put_opt(:type, opts[:type])
    |> maybe_put_opt(:status, opts[:status])
    |> Keyword.put(:detect, detect?)
  end

  defp should_detect?(opts) do
    case {opts[:detect], opts[:no_detect]} do
      {_, true} -> false
      {false, _} -> false
      _ -> true
    end
  end

  defp maybe_put_opt(add_opts, _key, nil), do: add_opts
  defp maybe_put_opt(add_opts, key, value), do: Keyword.put(add_opts, key, value)

  defp handle_add_success(portfolio, repo, opts) do
    sync_portfolio(portfolio)
    output_add_result(repo, opts)
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

  defp output_add_result(repo, opts) do
    if opts[:json] do
      output_json(repo)
    else
      output_add_text(repo)
    end
  end

  defp output_add_text(repo) do
    Mix.shell().info("""
    #{IO.ANSI.green()}Added repository: #{repo.id}#{IO.ANSI.reset()}

      Type:     #{repo.type}
      Language: #{repo.language}
      Path:     #{repo.path}

    Run `mix portfolio.show #{repo.id}` to see details.
    """)
  end

  defp handle_add_error(:already_exists) do
    Mix.shell().error("Repository already exists in portfolio.")
    Exit.halt(:error)
  end

  defp handle_add_error(reason) do
    Mix.shell().error("Failed to add repository: #{inspect(reason)}")
    Exit.halt(:error)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.add <path>

    Manually add a repository to the portfolio.

    Options:
      --id           Override auto-generated ID
      --type         Set type (library, application, port)
      --status       Set status (active, stale, etc.)
      --detect       Run detection after add (default: true)
      --no-detect    Skip detection
      --json         Output as JSON
      --help         Show this help message

    Examples:
      mix portfolio.add .
      mix portfolio.add ~/projects/my-app
      mix portfolio.add . --id=my-custom-id --type=library --status=active
    """)
  end

  defp output_json(repo) do
    data = %{
      id: repo.id,
      name: repo.name,
      type: repo.type,
      status: repo.status,
      language: repo.language,
      path: repo.path
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
