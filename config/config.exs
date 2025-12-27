import Config

config :portfolio_manager,
  portfolio_path: "../portfolio",
  embedding_provider: :gemini,
  embedding_dimensions: 3072,
  vector_index_lists: 100,
  auto_sync: false

config :portfolio_manager, :ecto_repos, [PortfolioManager.VectorStore.Repo]

config :portfolio_manager, PortfolioManager.VectorStore.Repo,
  pool_size: 5,
  types: PortfolioManager.VectorStore.PostgrexTypes,
  show_sensitive_data_on_connection_error: true

# RAG provider configuration
config :rag,
  providers: %{
    gemini: %{
      module: Rag.Ai.Gemini,
      model: "gemini-2.0-flash",
      embedding_model: "text-embedding-004"
    },
    claude: %{
      module: Rag.Ai.Claude,
      model: "claude-sonnet-4-20250514"
    },
    codex: %{
      module: Rag.Ai.Codex,
      model: "gpt-4o"
    }
  },
  default_strategy: :specialist,
  agent: %{
    max_iterations: 10,
    default_provider: :gemini
  }

import_config "#{config_env()}.exs"
