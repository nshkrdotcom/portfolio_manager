defmodule PortfolioManager.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_manager"

  def project do
    [
      app: :portfolio_manager,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "AI-native personal project intelligence system",
      package: package(),

      # Docs
      name: "Portfolio Manager",
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioManager.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # YAML parsing
      {:yaml_elixir, "~> 2.9"},

      # JSON
      {:jason, "~> 1.4"},

      # File watching (optional)
      {:file_system, "~> 1.0", optional: true},

      # Testing
      {:supertester, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Core: [
          PortfolioManager,
          PortfolioManager.Portfolio
        ],
        Domain: [
          PortfolioManager.Domain.Repo,
          PortfolioManager.Domain.Context,
          PortfolioManager.Domain.Relationship,
          PortfolioManager.Domain.Registry
        ],
        Ports: [
          PortfolioManager.Ports.Storage,
          PortfolioManager.Ports.Git,
          PortfolioManager.Ports.Detection
        ],
        Adapters: [
          PortfolioManager.Adapters.YAMLStorage,
          PortfolioManager.Adapters.LocalGit,
          PortfolioManager.Adapters.FileDetector
        ]
      ]
    ]
  end
end
