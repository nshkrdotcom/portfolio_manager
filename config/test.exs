import Config

config :portfolio_manager,
  env: :test,
  start_repo: false,
  start_router: false,
  manifest: %{}

config :portfolio_core, :manifest, manifest_path: "config/manifests/test.yml"

config :portfolio_index,
  start_repo: false,
  start_boltx: false,
  start_telemetry: false

config :logger, level: :warning
