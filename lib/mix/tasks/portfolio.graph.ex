defmodule Mix.Tasks.Portfolio.Graph do
  @moduledoc """
  Visualize the relationship graph.

  ## Usage

      mix portfolio.graph [repo-id]

  ## Options

    * `--depth` - How many hops to include (default: 2)
    * `--type` - Filter relationship types (comma-separated)
    * `--output`, `-o` - Output file (dot, svg, png)
    * `--ascii` - ASCII output
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.graph
      mix portfolio.graph flowstone --depth=3
      mix portfolio.graph --type=depends_on -o deps.dot
      mix portfolio.graph flowstone --ascii
  """
  @shortdoc "Show relationship graph"

  use Mix.Task

  alias PortfolioManager.Graph
  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          depth: :integer,
          type: :string,
          output: :string,
          ascii: :boolean,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [o: :output, d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      repo_id = List.first(args)
      show_graph(repo_id, opts)
    end
  end

  defp show_graph(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        graph = Graph.build(portfolio)
        graph = filter_graph(graph, opts[:type])

        cond do
          opts[:json] -> output_json(graph)
          opts[:output] -> output_file(graph, repo_id, opts)
          true -> output_ascii(graph, repo_id, opts)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
        Exit.halt(:config)
    end
  end

  defp output_ascii(graph, repo_id, opts) do
    depth = opts[:depth] || 2
    ascii = Graph.to_ascii(graph, root: repo_id, max_depth: depth)
    Mix.shell().info(ascii)
  end

  defp output_file(graph, repo_id, opts) do
    output = opts[:output]
    depth = opts[:depth] || 2

    case Path.extname(output) do
      ".dot" ->
        File.write!(output, Graph.to_dot(graph))
        Mix.shell().info("Wrote #{output}")

      ".svg" ->
        write_graphviz(graph, output, "svg")

      ".png" ->
        write_graphviz(graph, output, "png")

      _ ->
        ascii = Graph.to_ascii(graph, root: repo_id, max_depth: depth)
        File.write!(output, ascii)
        Mix.shell().info("Wrote #{output}")
    end
  end

  defp write_graphviz(graph, output, format) do
    case System.find_executable("dot") do
      nil ->
        Mix.shell().error("Graphviz 'dot' not found. Install graphviz or output .dot instead.")
        Exit.halt(:error)

      dot ->
        tmp =
          Path.join(
            System.tmp_dir!(),
            "portfolio_graph_#{System.unique_integer([:positive])}.dot"
          )

        File.write!(tmp, Graph.to_dot(graph))

        System.cmd(dot, ["-T#{format}", tmp, "-o", output])
        Mix.shell().info("Wrote #{output}")
    end
  end

  defp output_json(graph) do
    data = %{
      nodes: MapSet.to_list(graph.nodes),
      edges: graph.edges
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp filter_graph(graph, nil), do: graph

  defp filter_graph(graph, type_filter) do
    types =
      type_filter
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    edges = Enum.filter(graph.edges, &(&1.type in types))

    adjacency =
      Enum.reduce(edges, %{}, fn edge, acc ->
        Map.update(acc, edge.from, [edge.to], &[edge.to | &1])
      end)

    %{graph | edges: edges, adjacency: adjacency}
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.graph [repo-id]

    Visualize the relationship graph.

    Options:
      --depth         How many hops to include (default: 2)
      --type          Filter relationship types (comma-separated)
      --output, -o    Output file (dot, svg, png)
      --ascii         ASCII output
      --json          Output as JSON
      --help          Show this help message

    Examples:
      mix portfolio.graph
      mix portfolio.graph flowstone --depth=3
      mix portfolio.graph --type=depends_on -o deps.dot
      mix portfolio.graph flowstone --ascii
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
