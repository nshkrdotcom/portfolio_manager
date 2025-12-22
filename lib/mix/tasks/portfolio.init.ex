defmodule Mix.Tasks.Portfolio.Init do
  @moduledoc """
  Initialize a new portfolio repository.

  ## Usage

      mix portfolio.init [path]

  ## Options

    * `--help` - Show this help message

  ## Examples

      # Initialize in default location (~/portfolio)
      mix portfolio.init

      # Initialize in specific path
      mix portfolio.init ~/my-portfolio

  """
  @shortdoc "Initialize a new portfolio repository"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, strict: [help: :boolean])

    if opts[:help] do
      Mix.shell().info("""
      Usage: mix portfolio.init [path]

      Initialize a new portfolio repository.

      Options:
        --help    Show this help message

      Examples:
        mix portfolio.init
        mix portfolio.init ~/my-portfolio
      """)
    else
      path = List.first(args) || default_portfolio_path()
      expanded = Path.expand(path)

      if PortfolioManager.Adapters.YAMLStorage.exists?(expanded) do
        Mix.shell().error("Portfolio already exists at #{expanded}")
        Exit.halt(:config)
      else
        case PortfolioManager.Adapters.YAMLStorage.create(expanded) do
          :ok ->
            Mix.shell().info("""
            #{IO.ANSI.green()}Initialized portfolio at #{expanded}#{IO.ANSI.reset()}

            Structure created:
              #{expanded}/
              ├── config.yml
              ├── registry.yml
              ├── relationships.yml
              └── repos/

            Next steps:
              1. Run `mix portfolio.scan` to discover repositories
              2. Run `mix portfolio.list` to see tracked repos
            """)

          {:error, reason} ->
            Mix.shell().error("Failed to initialize portfolio: #{inspect(reason)}")
            Exit.halt(:error)
        end
      end
    end
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
