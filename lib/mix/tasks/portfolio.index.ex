defmodule Mix.Tasks.Portfolio.Index do
  @moduledoc """
  Index a repository for RAG queries.

  ## Usage

      mix portfolio.index /path/to/repo
      mix portfolio.index . --index my_project

  ## Options

    * `--index` - Index name (default: default)
    * `--extensions` - File extensions to include (default: .ex,.exs,.md)
  """

  use Mix.Task

  @shortdoc "Index a repository for RAG"

  @impl true
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          index: :string,
          extensions: :string
        ]
      )

    Mix.Task.run("app.start")

    repo_path =
      case args do
        [path | _] -> Path.expand(path)
        [] -> File.cwd!()
      end

    extensions =
      case opts[:extensions] do
        nil -> [".ex", ".exs", ".md"]
        ext -> String.split(ext, ",") |> Enum.map(&String.trim/1)
      end

    index_opts = [
      index_id: opts[:index] || "default",
      extensions: extensions
    ]

    Mix.shell().info("Indexing: #{repo_path}")
    Mix.shell().info("Index: #{index_opts[:index_id]}")
    Mix.shell().info("Extensions: #{Enum.join(extensions, ", ")}")

    case PortfolioManager.RAG.index_repo(repo_path, index_opts) do
      {:ok, result} ->
        Mix.shell().info("\nQueued #{result.files_queued} files for indexing")
        Mix.shell().info("Index ID: #{result.index_id}")

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
