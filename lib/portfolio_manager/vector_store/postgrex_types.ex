Postgrex.Types.define(
  PortfolioManager.VectorStore.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
