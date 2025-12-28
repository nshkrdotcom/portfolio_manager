# RAG Query Example
# Run: mix run examples/rag_query.exs

Mix.Task.run("app.start")

alias PortfolioManager.RAG

# Tip: run examples/index_repo.exs first to populate the index.
index_id = System.get_env("PORTFOLIO_INDEX_ID") || "default"

# Simple question
question = "How does the workflow engine process steps?"

IO.puts("Question: #{question}")
IO.puts("Strategy: hybrid\n")

case RAG.ask(question, strategy: :hybrid, k: 5, index_id: index_id) do
  {:ok, answer} ->
    IO.puts("Answer:")
    IO.puts(answer)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
