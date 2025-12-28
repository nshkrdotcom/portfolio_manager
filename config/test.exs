import Config

config :portfolio_manager,
  env: :test,
  start_repo: false

config :portfolio_index,
  start_repo: false,
  start_boltx: false,
  start_telemetry: false

config :logger, level: :warning
