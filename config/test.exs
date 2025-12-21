import Config

# Test-specific configuration
config :portfolio_manager,
  portfolio_path: System.tmp_dir!()

config :logger, level: :warning
