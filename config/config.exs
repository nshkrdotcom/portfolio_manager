import Config

config :portfolio_manager,
  portfolio_path: "../portfolio"

import_config "#{config_env()}.exs"
