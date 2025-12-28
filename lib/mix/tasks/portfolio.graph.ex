defmodule Mix.Tasks.Portfolio.Graph do
  @moduledoc """
  Graph operations for portfolio analysis.

  ## Usage

      mix portfolio.graph stats --graph default
      mix portfolio.graph build /path/to/repo --graph deps --language elixir

  ## Options

    * `--graph` - Graph ID (default: default)
    * `--language` - Dependency language (default: elixir)
  """

  use Mix.Task

  @shortdoc "Run graph operations"

  @impl true
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          graph: :string,
          language: :string
        ]
      )

    Mix.Task.run("app.start")

    graph_id = opts[:graph] || "default"

    case args do
      ["build", repo_path] ->
        language = parse_language(opts[:language])
        Mix.shell().info("Building dependency graph: #{graph_id}")

        case PortfolioManager.Graph.build_dependency_graph(graph_id, repo_path,
               language: language
             ) do
          {:ok, stats} ->
            print_stats(stats)

          {:error, reason} ->
            Mix.shell().error("Error: #{inspect(reason)}")
            exit({:shutdown, 1})
        end

      ["stats"] ->
        show_stats(graph_id)

      [] ->
        show_stats(graph_id)

      _ ->
        Mix.shell().error("Usage: mix portfolio.graph stats --graph <id>")
        Mix.shell().error("       mix portfolio.graph build <repo_path> --graph <id>")
        exit({:shutdown, 1})
    end
  end

  defp show_stats(graph_id) do
    Mix.shell().info("Graph stats for: #{graph_id}")

    case PortfolioManager.Graph.stats(graph_id) do
      {:ok, stats} ->
        print_stats(stats)

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_stats(stats) do
    node_count = stats[:node_count] || stats["node_count"] || stats[:nodes] || 0
    edge_count = stats[:edge_count] || stats["edge_count"] || stats[:edges] || 0

    Mix.shell().info("\nNodes: #{node_count}")
    Mix.shell().info("Edges: #{edge_count}")
  end

  defp parse_language(nil), do: :elixir
  defp parse_language(lang), do: String.to_atom(lang)
end
