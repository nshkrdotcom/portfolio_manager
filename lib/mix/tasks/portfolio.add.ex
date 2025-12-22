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
        if PortfolioManager.Adapters.LocalGit.is_repo?(expanded) do
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
    detect? =
      case {opts[:detect], opts[:no_detect]} do
        {_, true} -> false
        {false, _} -> false
        _ -> true
      end

    add_opts = []
    add_opts = if opts[:id], do: Keyword.put(add_opts, :id, opts[:id]), else: add_opts
    add_opts = if opts[:type], do: Keyword.put(add_opts, :type, opts[:type]), else: add_opts
    add_opts = if opts[:status], do: Keyword.put(add_opts, :status, opts[:status]), else: add_opts
    add_opts = Keyword.put(add_opts, :detect, detect?)

    case PortfolioManager.add(portfolio, path, add_opts) do
      {:ok, repo} ->
        case PortfolioManager.sync(portfolio) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
            Exit.halt(:error)
        end

        if opts[:json] do
          output_json(repo)
        else
          Mix.shell().info("""
          #{IO.ANSI.green()}Added repository: #{repo.id}#{IO.ANSI.reset()}

            Type:     #{repo.type}
            Language: #{repo.language}
            Path:     #{repo.path}

          Run `mix portfolio.show #{repo.id}` to see details.
          """)
        end

      {:error, :already_exists} ->
        Mix.shell().error("Repository already exists in portfolio.")
        Exit.halt(:error)

      {:error, reason} ->
        Mix.shell().error("Failed to add repository: #{inspect(reason)}")
        Exit.halt(:error)
    end
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
