defmodule Mix.Tasks.Portfolio.Reembed do
  @moduledoc """
  Re-embeds documents using the current embedding configuration.

  ## Usage

      # Re-embed all chunks
      mix portfolio.reembed

      # Re-embed specific collection
      mix portfolio.reembed --collection my_docs

      # Re-embed with progress output
      mix portfolio.reembed --verbose

  ## Options

  - `--collection` - Only re-embed chunks in this collection
  - `--batch-size` - Chunks per batch (default: 100)
  - `--verbose` - Show progress updates
  - `--dry-run` - Show what would be re-embedded without doing it
  - `--help` - Show this help message
  """

  use Mix.Task

  alias PortfolioIndex.Maintenance
  alias PortfolioIndex.Maintenance.Progress

  @shortdoc "Re-embed documents with current embedding model"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          collection: :string,
          batch_size: :integer,
          verbose: :boolean,
          dry_run: :boolean,
          help: :boolean
        ],
        aliases: [
          c: :collection,
          b: :batch_size,
          v: :verbose
        ]
      )

    cond do
      opts[:help] -> print_help()
      opts[:dry_run] -> print_dry_run(opts)
      true -> execute_reembed(opts)
    end
  end

  defp execute_reembed(opts) do
    Mix.Task.run("app.start")
    repo = get_repo()

    reembed_opts = build_reembed_opts(opts)

    Mix.shell().info("Starting re-embedding...")

    {:ok, result} = Maintenance.reembed(repo, reembed_opts)
    print_result(result)
  end

  defp build_reembed_opts(opts) do
    batch_size = opts[:batch_size] || 100
    verbose = opts[:verbose] || false

    progress_fn =
      if verbose do
        Progress.cli_reporter()
      else
        Progress.silent_reporter()
      end

    base_opts = [
      batch_size: batch_size,
      on_progress: progress_fn
    ]

    if opts[:collection] do
      Keyword.put(base_opts, :collection, opts[:collection])
    else
      base_opts
    end
  end

  defp print_result(result) do
    Mix.shell().info("""

    Re-embedding complete!
    Total chunks: #{result.total}
    Processed: #{result.processed}
    Failed: #{result.failed}
    """)

    print_errors(result.errors)
  end

  defp print_errors([]), do: :ok

  defp print_errors(errors) do
    Mix.shell().info("Errors:")
    Enum.each(errors, &print_error/1)
  end

  defp print_error(error) do
    Mix.shell().info("  - Chunk #{error.chunk_id}: #{inspect(error.error)}")
  end

  defp print_dry_run(opts) do
    collection = opts[:collection]
    batch_size = opts[:batch_size] || 100

    Mix.shell().info("""
    Dry run mode - no changes will be made.

    Configuration:
    - Collection: #{collection || "all"}
    - Batch size: #{batch_size}

    To run for real, remove the --dry-run flag.
    """)
  end

  defp print_help do
    Mix.shell().info("""
    Re-embed documents using the current embedding configuration.

    Usage:
      mix portfolio.reembed [options]

    Options:
      --collection, -c   Only re-embed chunks in this collection
      --batch-size, -b   Chunks per batch (default: 100)
      --verbose, -v      Show progress updates
      --dry-run          Show what would be re-embedded without doing it
      --help             Show this help message

    Examples:
      mix portfolio.reembed
      mix portfolio.reembed --collection docs --verbose
      mix portfolio.reembed --batch-size 50
    """)
  end

  defp get_repo do
    Application.get_env(:portfolio_manager, :repo, PortfolioManager.Repo)
  end
end
