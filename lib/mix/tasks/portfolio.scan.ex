defmodule Mix.Tasks.Portfolio.Scan do
  @moduledoc """
  Discover and add repositories from directories.

  ## Usage

      mix portfolio.scan [directories...]

  ## Options

    * `--dry-run` - Show what would be added without making changes
    * `--detect` - Run deterministic detection (default: true)
    * `--no-detect` - Skip deterministic detection
    * `--agentic` - Run agentic detection
    * `--no-agentic` - Skip agentic detection
    * `--review` - Immediately review agentic detections
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.scan
      mix portfolio.scan ~/projects
      mix portfolio.scan ~/work ~/personal --dry-run
      mix portfolio.scan --no-agentic

  """
  @shortdoc "Discover repositories in directories"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @dialyzer {:nowarn_function, [run: 1, dry_run_scan: 2, do_scan: 6, resolve_directories: 2]}

  @impl Mix.Task
  def run(args) do
    {opts, dirs, _} =
      OptionParser.parse(args,
        strict: [
          dry_run: :boolean,
          detect: :boolean,
          no_detect: :boolean,
          agentic: :boolean,
          no_agentic: :boolean,
          review: :boolean,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    help? = Keyword.get(opts, :help, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    case help? do
      true ->
        show_help()

      _ ->
        portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
        config = load_config(portfolio_path)
        directories = resolve_directories(dirs, config)
        exclude = scan_exclude_patterns(config)

        case PortfolioManager.init(portfolio_path) do
          {:ok, portfolio} ->
            case dry_run? do
              true ->
                dry_run_scan(directories, exclude)

              _ ->
                do_scan(portfolio, portfolio_path, directories, exclude, config, opts)
            end

          {:error, :not_initialized} ->
            Mix.shell().error("""
            Portfolio not found at #{portfolio_path}
            Run `mix portfolio.init` first.
            """)

            Exit.halt(:config)
        end
    end
  end

  defp dry_run_scan(directories, exclude) do
    Mix.shell().info("Dry run - discovering repositories...")

    repos =
      directories
      |> Enum.flat_map(fn dir ->
        expanded = Path.expand(dir)

        case File.dir?(expanded) do
          true ->
            PortfolioManager.Adapters.LocalGit.discover_repos(expanded, exclude: exclude)

          _ ->
            Mix.shell().info("  Skipping #{dir} (not a directory)")
            []
        end
      end)

    case Enum.empty?(repos) do
      true ->
        Mix.shell().info("No repositories found.")

      _ ->
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

  defp do_scan(portfolio, portfolio_path, directories, exclude, config, opts) do
    Mix.shell().info("Scanning directories...")

    expanded_dirs = Enum.map(directories, &Path.expand/1)

    no_detect? = Keyword.get(opts, :no_detect, false)
    detect? = no_detect? != true

    agentic_default = agents_auto_detect?(config)
    no_agentic? = Keyword.get(opts, :no_agentic, false)
    agentic_flag = Keyword.get(opts, :agentic, false)
    json? = Keyword.get(opts, :json, false)
    review? = Keyword.get(opts, :review, false)

    agentic? =
      cond do
        no_agentic? -> false
        agentic_flag -> true
        true -> agentic_default
      end

    case PortfolioManager.scan(portfolio, expanded_dirs, detect: detect?, exclude: exclude) do
      {:ok, added_repos} ->
        {agentic_result, pending_count} =
          case agentic? do
            true -> run_agentic_detection(portfolio, added_repos, opts)
            _ -> {:ok, 0}
          end

        case PortfolioManager.sync(portfolio) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
            Exit.halt(:error)
        end

        case json? do
          true ->
            output_json(added_repos, pending_count)

          _ ->
            case Enum.empty?(added_repos) do
              true ->
                Mix.shell().info("No new repositories found.")

              _ ->
                Mix.shell().info(
                  "#{IO.ANSI.green()}Added #{length(added_repos)} repositories:#{IO.ANSI.reset()}"
                )

                Enum.each(added_repos, fn repo ->
                  Mix.shell().info("  #{repo.id} (#{repo.language}) - #{repo.type}")
                end)
            end

            case agentic_result == :ok and pending_count > 0 do
              true ->
                Mix.shell().info("")
                Mix.shell().info("Queued #{pending_count} agentic detections for review.")

              _ ->
                :ok
            end
        end

        case review? do
          true -> Mix.Tasks.Portfolio.Review.run(["--portfolio-dir", portfolio_path])
          _ -> :ok
        end

      {:error, reason} ->
        Mix.shell().error("Scan failed: #{inspect(reason)}")
        Exit.halt(:error)
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.scan [directories...]

    Discover and add repositories from directories.

    If no directories are provided, uses scan.directories from config.yml.

    Options:
      --dry-run    Show what would be added without changes
      --detect     Run deterministic detection (default: true)
      --no-detect  Skip deterministic detection
      --agentic    Run agentic detection
      --no-agentic Skip agentic detection
      --review     Immediately review agentic detections
      --json       Output as JSON
      --help       Show this help message

    Examples:
      mix portfolio.scan
      mix portfolio.scan ~/projects ~/work
      mix portfolio.scan --dry-run
      mix portfolio.scan --no-agentic
    """)
  end

  defp run_agentic_detection(portfolio, repos, _opts) do
    results =
      Enum.map(repos, fn repo ->
        PortfolioManager.Detection.Agentic.analyze_with_review(repo.path, portfolio,
          repo_id: repo.id,
          auto_accept_threshold: 0.9
        )
      end)

    pending =
      results
      |> Enum.filter(&match?({:ok, %{pending: _}}, &1))
      |> Enum.map(fn {:ok, %{pending: pending}} -> pending end)
      |> Enum.sum()

    {:ok, pending}
  end

  defp output_json(repos, pending) do
    data = %{
      added: Enum.map(repos, & &1.id),
      count: length(repos),
      pending_review: pending
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end

  defp resolve_directories(dirs, config) do
    case dirs do
      [] ->
        config_dirs = get_in(config, ["scan", "directories"]) || []

        case config_dirs do
          [] -> ["."]
          _ -> config_dirs
        end

      _ ->
        dirs
    end
  end

  defp scan_exclude_patterns(config) do
    get_in(config, ["scan", "exclude_patterns"]) ||
      get_in(config, ["scan", "exclude"]) ||
      []
  end

  defp agents_auto_detect?(config) do
    enabled? = get_in(config, ["agents", "enabled"]) == true
    auto_detect? = get_in(config, ["agents", "auto_detect"]) == true

    enabled? and auto_detect?
  end

  defp load_config(portfolio_path) do
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} -> config
      {:error, _} -> %{}
    end
  end
end
