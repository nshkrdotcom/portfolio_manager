defmodule Mix.Tasks.Portfolio.Status do
  @moduledoc """
  Show overall portfolio status.

  ## Usage

      mix portfolio.status

  ## Options

    * `--json` - Output as JSON
    * `--help` - Show help message

  """
  @shortdoc "Show portfolio status"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
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
          stats = gather_stats(portfolio)

          if opts[:json] do
            output_json(stats)
          else
            output_formatted(stats, portfolio_path)
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

  defp gather_stats(portfolio) do
    repos = PortfolioManager.list_repos(portfolio)

    by_status = Enum.group_by(repos, & &1.status)
    by_type = Enum.group_by(repos, & &1.type)
    by_language = Enum.group_by(repos, & &1.language)

    %{
      total: length(repos),
      by_status: Map.new(by_status, fn {k, v} -> {k, length(v)} end),
      by_type: Map.new(by_type, fn {k, v} -> {k, length(v)} end),
      by_language: Map.new(by_language, fn {k, v} -> {k, length(v)} end)
    }
  end

  defp output_json(stats) do
    Mix.shell().info(Jason.encode!(stats, pretty: true))
  end

  defp output_formatted(stats, portfolio_path) do
    Mix.shell().info("""
    #{IO.ANSI.bright()}Portfolio Status#{IO.ANSI.reset()}
    #{String.duplicate("═", 50)}

    Location:    #{portfolio_path}
    Total Repos: #{stats.total}

    #{IO.ANSI.bright()}By Status:#{IO.ANSI.reset()}
    #{format_counts(stats.by_status)}

    #{IO.ANSI.bright()}By Type:#{IO.ANSI.reset()}
    #{format_counts(stats.by_type)}

    #{IO.ANSI.bright()}By Language:#{IO.ANSI.reset()}
    #{format_counts(stats.by_language)}
    """)
  end

  defp format_counts(counts) do
    counts
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.map_join("\n", fn {key, count} ->
      "  #{String.pad_trailing(to_string(key), 15)} #{count}"
    end)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.status

    Show overall portfolio status.

    Options:
      --json       Output as JSON
      --help       Show this help message
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
