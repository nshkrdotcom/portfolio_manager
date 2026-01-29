import Config

neo4j_uri = System.get_env("NEO4J_URI") || "bolt://localhost:7687"
neo4j_user = System.get_env("NEO4J_USER") || "neo4j"
neo4j_password = System.get_env("NEO4J_PASSWORD") || "password"
neo4j_pool_size = String.to_integer(System.get_env("NEO4J_POOL_SIZE") || "10")

config :portfolio_manager,
  env: :development,
  start_repo: true

# Configure portfolio_core's Manifest.Engine (started by portfolio_core's supervision tree)
config :portfolio_core, :manifest, manifest_path: "config/manifests/development.yml"

config :portfolio_manager, :ecto_repos, [PortfolioManager.Repo]

config :portfolio_manager, PortfolioManager.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  database: System.get_env("PGDATABASE") || "portfolio_manager_dev",
  pool_size: 10

config :portfolio_index,
  start_repo: true,
  start_boltx: true,
  start_telemetry: true,
  ecto_repos: [PortfolioIndex.Repo]

config :portfolio_index, PortfolioIndex.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  database: System.get_env("PGDATABASE") || "portfolio_manager_dev",
  pool_size: 10,
  types: PortfolioIndex.PostgrexTypes

config :boltx, Boltx,
  name: Boltx,
  uri: neo4j_uri,
  auth: [username: neo4j_user, password: neo4j_password],
  pool_size: neo4j_pool_size

# Hammer rate limiter config (required by portfolio_index hex package 0.3.1)
# Note: This is a workaround - hammer is not actually used by the code anymore,
# but it's still a dependency in the published Hex package.
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       # 2 hours
       expiry_ms: 60_000 * 60 * 2,
       # 10 minutes
       cleanup_interval_ms: 60_000 * 10
     ]}

import_config "#{config_env()}.exs"
