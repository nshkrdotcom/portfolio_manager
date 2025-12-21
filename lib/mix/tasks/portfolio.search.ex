defmodule Mix.Tasks.Portfolio.Search do
  @moduledoc """
  Search across all repositories.

  ## Usage

      mix portfolio.search <query>

  ## Options

    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.search authentication
      mix portfolio.search "data pipeline"
      mix portfolio.search --json "api"

  """
  @shortdoc "Search across repositories"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, query_parts, _} =
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
      query = Enum.join(query_parts, " ")

      if query == "" do
        Mix.shell().error("Missing search query. Usage: mix portfolio.search <query>")
      else
        do_search(query, opts)
      end
    end
  end

  defp do_search(query, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        results = PortfolioManager.search(portfolio, query)

        if opts[:json] do
          output_json(results)
        else
          output_formatted(results, query)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
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

      Enum.each(results, fn repo ->
        Mix.shell().info(
          "  #{IO.ANSI.bright()}#{repo.id}#{IO.ANSI.reset()} (#{repo.type}, #{repo.language})"
        )

        if repo.purpose do
          purpose_preview = String.slice(repo.purpose, 0, 60)
          Mix.shell().info("    #{purpose_preview}...")
        end

        Mix.shell().info("    #{repo.path}")
        Mix.shell().info("")
      end)
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.search <query>

    Search across all repositories.

    Options:
      --json       Output as JSON
      --help       Show this help message

    Examples:
      mix portfolio.search authentication
      mix portfolio.search "data pipeline"
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
