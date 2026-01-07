# Streaming Query Example
#
# This example demonstrates streaming RAG queries.
#
# Run with: mix run examples/streaming_query.exs

Mix.Task.run("app.start")

IO.puts("=== Streaming Query Example ===\n")

question = "What are the main features of this application?"

IO.puts("Question: #{question}")
IO.puts("\nStreaming response:\n")
IO.puts("---")

# Track timing
start_time = System.monotonic_time(:millisecond)
Process.put(:first_chunk_time, nil)

case PortfolioManager.RAG.stream_query(question, fn chunk ->
       # Record time to first chunk
       if Process.get(:first_chunk_time) == nil do
         Process.put(:first_chunk_time, System.monotonic_time(:millisecond))
       end

       IO.write(chunk)
     end) do
  :ok ->
    end_time = System.monotonic_time(:millisecond)
    total_time = end_time - start_time
    first_chunk_time = Process.get(:first_chunk_time)

    IO.puts("\n---")

    if first_chunk_time do
      IO.puts("Time to first chunk: #{first_chunk_time - start_time}ms")
    end

    IO.puts("\nTotal time: #{total_time}ms")

  {:error, reason} ->
    IO.puts("\nError: #{inspect(reason)}")
end

IO.puts("")

# Also demonstrate stream_search
IO.puts("=== Streaming Search Results ===\n")

query = "authentication"
IO.puts("Searching for: #{query}\n")

result_count = Agent.start_link(fn -> 0 end) |> elem(1)

case PortfolioManager.RAG.stream_search(
       query,
       fn result ->
         count = Agent.get_and_update(result_count, fn n -> {n + 1, n + 1} end)
         IO.puts("Result #{count}:")
         IO.puts("  Source: #{result[:source] || "unknown"}")
         IO.puts("  Score: #{result[:score] || "n/a"}")
         snippet = (result[:content] || "") |> String.slice(0, 100) |> String.replace("\n", " ")
         IO.puts("  Content: #{snippet}...")
         IO.puts("")
       end,
       limit: 5
     ) do
  :ok ->
    total = Agent.get(result_count, & &1)
    IO.puts("Found #{total} results")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("\n=== Example Complete ===")
