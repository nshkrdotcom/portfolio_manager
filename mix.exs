defmodule PortfolioManager.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_manager"

  def project do
    [
      app: :portfolio_manager,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :portfolio_core],
        flags: [:error_handling, :unknown, :unmatched_returns]
      ],
      preferred_cli_env: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls],

      # Hex package
      description: description(),
      package: package(),

      # Docs
      name: "PortfolioManager",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
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
      # Core packages (published on Hex).
      # Using local path deps to align with repo changes.
      {:portfolio_core, "~> 0.1.1"},
      {:portfolio_index, "~> 0.1.1"},

      # Web framework (optional, for API)
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 0.20", optional: true},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},

      # CLI utilities
      {:optimus, "~> 0.5"},

      # YAML for manifests
      {:yaml_elixir, "~> 2.9"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Dev/test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/portfolio_manager.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/rag.md",
        "guides/graph.md",
        "guides/configuration.md",
        "guides/cli.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          PortfolioManager,
          PortfolioManager.RAG,
          PortfolioManager.Graph
        ],
        Domain: [
          PortfolioManager.Domain.Registry
        ],
        Infrastructure: [
          PortfolioManager.Application,
          PortfolioManager.Repo
        ]
      ]
    ]
  end

  defp description do
    """
    Application layer for Portfolio ecosystem providing RAG workflows,
    graph analysis, domain registries, and CLI tools built on portfolio_core and portfolio_index.
    """
  end

  defp package do
    [
      name: "portfolio_manager",
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end
end
