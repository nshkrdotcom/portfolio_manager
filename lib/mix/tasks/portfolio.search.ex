defmodule Mix.Tasks.Portfolio.Search do
  @moduledoc """
  Search portfolio content using RAG retrieval.

  ## Usage

      mix portfolio.search "authentication flow"
      mix portfolio.search "GenServer" --index code --k 5

  ## Options

    * `--index` - Vector index to query (default: default)
    * `--k` - Number of results to retrieve (default: 10)
  """

  use Mix.Task

  @shortdoc "Search portfolio content using RAG"

  @impl true
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          index: :string,
          k: :integer
        ]
      )

    Mix.Task.run("app.start")

    query = Enum.join(args, " ")

    if String.trim(query) == "" do
      Mix.shell().error("Usage: mix portfolio.search \"your query\"")
      exit({:shutdown, 1})
    end

    search_opts = [
      index_id: opts[:index] || "default",
      k: opts[:k] || 10
    ]

    Mix.shell().info("Searching: #{query}")

    case PortfolioManager.RAG.search(query, search_opts) do
      {:ok, items} ->
        Mix.shell().info("\nResults: #{length(items)}")

        Enum.with_index(items, 1)
        |> Enum.each(fn {item, idx} ->
          Mix.shell().info("#{idx}. score=#{format_score(item.score)} source=#{item.source}")
          Mix.shell().info("   #{snippet(item.content)}")
        end)

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp format_score(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 3)
  defp format_score(_score), do: "n/a"

  defp snippet(content) when is_binary(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 160)
  end

  defp snippet(_), do: ""
end
