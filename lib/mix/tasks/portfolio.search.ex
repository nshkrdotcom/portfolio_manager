defmodule Mix.Tasks.Portfolio.Search do
  @moduledoc """
  Search across all repositories.

  ## Usage

      mix portfolio.search <query>

  ## Options

    * `--field`, `-f` - Search specific fields (repeatable or comma-separated)
    * `--regex`, `-r` - Treat query as regex
    * `--case-sensitive` - Case sensitive search
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.search authentication
      mix portfolio.search "data pipeline"
      mix portfolio.search "TODO" --field=notes
      mix portfolio.search "^auth" --regex
      mix portfolio.search --json "api"

  """
  @shortdoc "Search across repositories"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, query_parts, _} =
      OptionParser.parse(args,
        strict: [
          field: :keep,
          regex: :boolean,
          case_sensitive: :boolean,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir, f: :field, r: :regex]
      )

    if opts[:help] do
      show_help()
    else
      query = Enum.join(query_parts, " ")

      if query == "" do
        Mix.shell().error("Missing search query. Usage: mix portfolio.search <query>")
        Exit.halt(:invalid_args)
      else
        do_search(query, opts)
      end
    end
  end

  defp do_search(query, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        search_opts = build_search_opts(opts)
        results = PortfolioManager.search(portfolio, query, search_opts)
        display_results(results, query, opts)

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
        Exit.halt(:config)
    end
  end

  defp build_search_opts(opts) do
    fields =
      opts[:field]
      |> List.wrap()
      |> Enum.flat_map(&String.split(&1, ",", trim: true))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)

    base_opts =
      if fields == [] do
        []
      else
        [fields: fields]
      end

    base_opts
    |> Keyword.put(:regex, opts[:regex] || false)
    |> Keyword.put(:case_sensitive, opts[:case_sensitive] || false)
  end

  defp display_results(results, query, opts) do
    if opts[:json] do
      output_json(results)
    else
      output_formatted(results, query)
    end
  end

  defp output_json(results) do
    data =
      Enum.map(results, fn repo ->
        %{
          id: repo.id,
          name: repo.name,
          type: repo.type,
          language: repo.language,
          path: repo.path
        }
      end)

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_formatted(results, query) do
    if Enum.empty?(results) do
      Mix.shell().info("No results found for '#{query}'")
    else
      Mix.shell().info("Found #{length(results)} matches for '#{query}':")
      Mix.shell().info("")
      Enum.each(results, &display_repo_result/1)
    end
  end

  defp display_repo_result(repo) do
    Mix.shell().info(
      "  #{IO.ANSI.bright()}#{repo.id}#{IO.ANSI.reset()} (#{repo.type}, #{repo.language})"
    )

    if repo.purpose do
      purpose_preview = String.slice(repo.purpose, 0, 60)
      Mix.shell().info("    #{purpose_preview}...")
    end

    Mix.shell().info("    #{repo.path}")
    Mix.shell().info("")
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.search <query>

    Search across all repositories.

    Options:
      --field, -f        Search specific fields (repeatable)
      --regex, -r        Treat query as regex
      --case-sensitive  Case sensitive search
      --json            Output as JSON
      --help            Show this help message

    Examples:
      mix portfolio.search authentication
      mix portfolio.search "data pipeline"
      mix portfolio.search "TODO" --field=notes
      mix portfolio.search "^auth" --regex
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
