defmodule Mix.Tasks.Portfolio.Scan do
  @moduledoc """
  Discover and add repositories from directories.

  ## Usage

      mix portfolio.scan [directories...]

  ## Options

    * `--dry-run` - Show what would be added without making changes
    * `--help` - Show help message

  ## Examples

      mix portfolio.scan
      mix portfolio.scan ~/projects
      mix portfolio.scan ~/work ~/personal --dry-run

  """
  @shortdoc "Discover repositories in directories"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, dirs, _} =
      OptionParser.parse(args,
        strict: [
          dry_run: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

      case PortfolioManager.init(portfolio_path) do
        {:ok, portfolio} ->
          directories = if Enum.empty?(dirs), do: ["."], else: dirs

          if opts[:dry_run] do
            dry_run_scan(directories)
          else
            do_scan(portfolio, directories)
          end

        {:error, :not_initialized} ->
          Mix.shell().error("""
          Portfolio not found at #{portfolio_path}
          Run `mix portfolio.init` first.
          """)
      end
    end
  end

  defp dry_run_scan(directories) do
    Mix.shell().info("Dry run - discovering repositories...")

    repos =
      directories
      |> Enum.flat_map(fn dir ->
        expanded = Path.expand(dir)

        if File.dir?(expanded) do
          PortfolioManager.Adapters.LocalGit.discover_repos(expanded)
        else
          Mix.shell().info("  Skipping #{dir} (not a directory)")
          []
        end
      end)

    if Enum.empty?(repos) do
      Mix.shell().info("No repositories found.")
    else
      Mix.shell().info("Found #{length(repos)} repositories:")

      Enum.each(repos, fn path ->
        {:ok, lang} = PortfolioManager.Adapters.FileDetector.detect_language(path)
        id = Path.basename(path)
        Mix.shell().info("  #{id} (#{lang}) - #{path}")
      end)

      Mix.shell().info("")
      Mix.shell().info("Run without --dry-run to add these to the portfolio.")
    end
  end

  defp do_scan(portfolio, directories) do
    Mix.shell().info("Scanning directories...")

    expanded_dirs = Enum.map(directories, &Path.expand/1)

    case PortfolioManager.scan(portfolio, expanded_dirs) do
      {:ok, added_repos} ->
        if Enum.empty?(added_repos) do
          Mix.shell().info("No new repositories found.")
        else
          Mix.shell().info(
            "#{IO.ANSI.green()}Added #{length(added_repos)} repositories:#{IO.ANSI.reset()}"
          )

          Enum.each(added_repos, fn repo ->
            Mix.shell().info("  #{repo.id} (#{repo.language}) - #{repo.type}")
          end)
        end

      {:error, reason} ->
        Mix.shell().error("Scan failed: #{inspect(reason)}")
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.scan [directories...]

    Discover and add repositories from directories.

    Options:
      --dry-run    Show what would be added without changes
      --help       Show this help message

    Examples:
      mix portfolio.scan
      mix portfolio.scan ~/projects ~/work
      mix portfolio.scan --dry-run
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
