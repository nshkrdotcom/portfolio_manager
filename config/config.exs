import Config

config :portfolio_manager,
  portfolio_path: "../portfolio",
  embedding_provider: :gemini,
  embedding_dimensions: 768,
  auto_sync: false

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
