defmodule PortfolioManager.VectorStore.Repo.Migrations.CreateRagChunks do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    execute("""
    CREATE TABLE IF NOT EXISTS rag_chunks (
      id bigserial PRIMARY KEY,
      content text NOT NULL,
      source text,
      embedding vector(3072),
      metadata jsonb DEFAULT '{}'::jsonb,
      inserted_at timestamp without time zone,
      updated_at timestamp without time zone
    )
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS rag_chunks_content_search_idx
    ON rag_chunks
    USING gin (to_tsvector('english', content))
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS rag_chunks")
  end
end
