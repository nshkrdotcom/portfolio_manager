# Index Repository Example
# Run: mix run examples/index_repo.exs

Mix.Task.run("app.start")

alias PortfolioManager.RAG

repo_path = File.cwd!()
index_id = System.get_env("PORTFOLIO_INDEX_ID") || "default"

IO.puts("Indexing: #{repo_path}")
IO.puts("Index ID: #{index_id}")

case RAG.index_repo(repo_path, index_id: index_id, extensions: [".ex", ".exs", ".md"]) do
  {:ok, result} ->
    IO.puts("\nSuccess!")
    IO.puts("Files queued: #{result.files_queued}")
    IO.puts("Index ID: #{result.index_id}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
