defmodule Mix.Tasks.Portfolio.Ask do
  @moduledoc """
  Ask a question using RAG.

  ## Usage

      mix portfolio.ask "What does the User module do?"
      mix portfolio.ask "How is authentication handled?" --strategy self_rag
      mix portfolio.ask "Explain this code" --stream

  ## Options

    * `--strategy` - RAG strategy to use (hybrid, self_rag, graph_rag)
    * `--index` - Vector index to query (default: default)
    * `--k` - Number of results to retrieve (default: 10)
    * `--stream` - Stream the response as it's generated
  """

  use Mix.Task

  @shortdoc "Ask a question using RAG"

  @impl true
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        switches: [
          strategy: :string,
          index: :string,
          k: :integer,
          stream: :boolean
        ],
        aliases: [s: :strategy, i: :index]
      )

    Mix.Task.run("app.start")

    question = Enum.join(args, " ")

    if String.trim(question) == "" do
      Mix.shell().error("Usage: mix portfolio.ask \"your question\"")
      exit({:shutdown, 1})
    end

    query_opts = [
      strategy: String.to_atom(opts[:strategy] || "hybrid"),
      index_id: opts[:index] || "default",
      k: opts[:k] || 10,
      top_k: opts[:k] || 5
    ]

    Mix.shell().info("Querying: #{question}")
    Mix.shell().info("Strategy: #{query_opts[:strategy]}")

    if opts[:stream] do
      run_streaming_query(question, query_opts)
    else
      run_sync_query(question, query_opts)
    end
  end

  defp run_sync_query(question, query_opts) do
    case PortfolioManager.RAG.ask(question, query_opts) do
      {:ok, answer} ->
        Mix.shell().info("\n#{answer}")

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp run_streaming_query(question, query_opts) do
    IO.write("\n")

    case PortfolioManager.RAG.stream_query(question, &IO.write/1, query_opts) do
      :ok ->
        IO.write("\n\n")

      {:error, reason} ->
        Mix.shell().error("\nError: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
