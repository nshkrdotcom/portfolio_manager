defmodule Mix.Tasks.Portfolio.Diagnostics do
  @moduledoc """
  Shows diagnostics for the PortfolioIndex system.

  ## Usage

      mix portfolio.diagnostics

  ## Output

  Shows:
  - Collection count and names
  - Document count by status
  - Chunk count and embedding coverage
  - Storage usage estimates
  - Configuration summary

  ## Options

  - `--format` - Output format: table (default) or json
  - `--help` - Show this help message
  - `--dry-run` - Skip database connection (for testing)
  """

  use Mix.Task

  alias PortfolioIndex.Maintenance

  @shortdoc "Show PortfolioIndex system diagnostics"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          help: :boolean,
          dry_run: :boolean
        ]
      )

    if opts[:help] do
      print_help()
    else
      run_diagnostics(opts)
    end
  end

  defp run_diagnostics(opts) do
    format = opts[:format] || "table"
    dry_run = opts[:dry_run] || false

    if dry_run do
      print_dry_run_diagnostics(format)
    else
      Mix.Task.run("app.start")
      repo = get_repo()

      {:ok, diagnostics} = Maintenance.diagnostics(repo)
      print_diagnostics(diagnostics, format)
    end
  end

  defp print_dry_run_diagnostics(format) do
    diagnostics = %{
      collections: 0,
      documents: 0,
      chunks: 0,
      chunks_without_embedding: 0,
      failed_documents: 0,
      storage_bytes: nil
    }

    Mix.shell().info("Diagnostics (dry run - no database connection)")
    print_diagnostics(diagnostics, format)
  end

  defp print_diagnostics(diagnostics, "json") do
    json = Jason.encode!(diagnostics, pretty: true)
    Mix.shell().info(json)
  end

  defp print_diagnostics(diagnostics, _format) do
    Mix.shell().info("""

    PortfolioIndex Diagnostics
    ==========================

    Collections:  #{diagnostics.collections}
    Documents:    #{diagnostics.documents}
      - Failed:   #{diagnostics.failed_documents}
    Chunks:       #{diagnostics.chunks}
      - Missing:  #{diagnostics.chunks_without_embedding}

    """)

    if diagnostics.storage_bytes do
      storage_mb = Float.round(diagnostics.storage_bytes / 1_000_000, 2)
      Mix.shell().info("Storage:      #{storage_mb} MB")
    end

    # Print embedding coverage
    if diagnostics.chunks > 0 do
      coverage =
        ((diagnostics.chunks - diagnostics.chunks_without_embedding) / diagnostics.chunks * 100)
        |> Float.round(1)

      Mix.shell().info("Embedding coverage: #{coverage}%")
    end

    # Print configuration summary
    print_config_summary()
  end

  defp print_config_summary do
    embedder = Application.get_env(:portfolio_index, :embedder)

    default_dims =
      Application.get_env(:portfolio_index, :embedding, [])
      |> Keyword.get(:default_dimensions, 384)

    Mix.shell().info("""

    Configuration
    -------------
    Embedder:     #{inspect(embedder || "Not configured")}
    Dimensions:   #{default_dims}
    """)
  end

  defp print_help do
    Mix.shell().info("""
    Shows diagnostics for the PortfolioIndex system.

    Usage:
      mix portfolio.diagnostics [options]

    Options:
      --format     Output format: table (default) or json
      --help       Show this help message

    Examples:
      mix portfolio.diagnostics
      mix portfolio.diagnostics --format json
    """)
  end

  defp get_repo do
    Application.get_env(:portfolio_manager, :repo, PortfolioManager.Repo)
  end
end
