defmodule Mix.Tasks.Portfolio.Docs do
  @moduledoc """
  Manage documentation ingestion.

  ## Usage

      mix portfolio.docs <subcommand> [options]

  ## Subcommands

    * `ingest` - Ingest documentation from tracked repos
    * `search` - Search indexed documentation chunks

  ## Options

    * `--repo` - Ingest docs for a specific repo ID
    * `--dry-run` - Show what would be ingested without writing
    * `--embed` - Generate embeddings and store chunks
    * `--chunk-max-chars` - Max characters per chunk
    * `--chunk-overlap` - Overlap characters per chunk
    * `--embed-batch-size` - Embedding batch size
    * `--delete-existing` - Delete existing chunks for the repo
    * `--limit` - Limit search results
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.docs ingest
      mix portfolio.docs ingest --repo my-app
      mix portfolio.docs ingest --dry-run
      mix portfolio.docs ingest --embed
      mix portfolio.docs search "http client"

  """
  @shortdoc "Manage documentation ingestion"

  use Mix.Task

  alias PortfolioManager.CLI.Exit
  alias PortfolioManager.Docs.Ingest

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          dry_run: :boolean,
          embed: :boolean,
          chunk_max_chars: :integer,
          chunk_overlap: :integer,
          embed_batch_size: :integer,
          delete_existing: :boolean,
          limit: :integer,
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
        ["ingest" | _] ->
          run_ingest(opts)

        ["search", query | _] ->
          run_search(query, opts)

        [] ->
          show_help()
          Exit.halt(:invalid_args)

        _ ->
          show_help()
          Exit.halt(:invalid_args)
      end
    end
  end

  defp run_ingest(opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config = load_config(portfolio_path)

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        ingest_opts = [
          config: config,
          repo_id: opts[:repo],
          dry_run: opts[:dry_run],
          embed: opts[:embed],
          chunk_max_chars: opts[:chunk_max_chars],
          chunk_overlap: opts[:chunk_overlap],
          embed_batch_size: opts[:embed_batch_size],
          delete_existing: opts[:delete_existing]
        ]

        {:ok, result} = Ingest.run(portfolio, ingest_opts)
        output_result(result, opts)

      {:error, :not_initialized} ->
        Mix.shell().error(
          "Portfolio not found at #{portfolio_path}. Run `mix portfolio.init` first."
        )

        Exit.halt(:config)
    end
  end

  defp run_search(query, opts) do
    repo_id = opts[:repo]
    limit = opts[:limit] || 5

    case PortfolioManager.VectorStore.search(query, repo_id: repo_id, limit: limit) do
      {:ok, results} ->
        display_search_results(query, results, opts)

      {:error, :missing_database_url} ->
        Mix.shell().error("Missing database URL. Set PORTFOLIO_DB_URL or DATABASE_URL.")
        Exit.halt(:config)

      {:error, reason} ->
        Mix.shell().error("Doc search failed: #{inspect(reason)}")
        Exit.halt(:error)
    end
  end

  defp output_result(%{results: results, totals: totals} = result, opts) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(result, pretty: true))
    else
      Mix.shell().info("Ingested docs for #{totals.repos} repos.")
      Mix.shell().info("Total docs indexed: #{totals.docs} (skipped: #{totals.skipped})")

      Enum.each(results, fn repo_result ->
        status = repo_result.status
        repo_id = repo_result.repo_id
        indexed = Map.get(repo_result, :docs_indexed, 0)
        skipped = Map.get(repo_result, :docs_skipped, 0)
        Mix.shell().info("  #{repo_id}: #{status} (indexed: #{indexed}, skipped: #{skipped})")
      end)
    end
  end

  defp display_search_results(query, results, opts) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(%{query: query, results: results}, pretty: true))
    else
      Mix.shell().info("Found #{length(results)} results:")

      Enum.each(results, fn result ->
        source = result.source || "unknown"
        score = Float.round(result.score || 0.0, 4)
        Mix.shell().info("  #{score} #{source}")
      end)
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.docs <subcommand> [options]

    Subcommands:
      ingest        Ingest documentation from tracked repos
      search <query> Search indexed doc chunks via pgvector

    Options:
      --repo        Ingest docs for a specific repo ID
      --dry-run     Show what would be ingested without writing
      --embed       Generate embeddings and store chunks
      --chunk-max-chars  Max characters per chunk
      --chunk-overlap    Overlap characters per chunk
      --embed-batch-size Embedding batch size
      --delete-existing  Delete existing chunks for the repo
      --limit       Limit search results
      --json        Output as JSON
      --help        Show this help message

    Examples:
      mix portfolio.docs ingest
      mix portfolio.docs ingest --repo my-app
      mix portfolio.docs ingest --dry-run
      mix portfolio.docs ingest --embed
      mix portfolio.docs search "http client"
    """)
  end

  defp load_config(portfolio_path) do
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} -> config
      {:error, _} -> %{}
    end
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
