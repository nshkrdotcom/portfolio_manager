defmodule PortfolioManager.MixProject do
  use Mix.Project

  @version "0.1.1"
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
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
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

      # RAG (Retrieval-Augmented Generation)
      {:rag, "~> 0.3.4", hex: :rag_ex},

      # Vector store (pgvector)
      {:ecto_sql, "~> 3.0"},
      {:postgrex, "~> 0.17"},
      {:pgvector, "~> 0.3.0"},

      # File watching (optional)
      {:file_system, "~> 1.0", optional: true},

      # SQLite caching (optional)
      {:exqlite, "~> 0.23", optional: true},

      # Testing
      {:supertester, "~> 0.3", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Static analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib assets priv .formatter.exs mix.exs README.md LICENSE guides)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      assets: %{"assets" => "assets"},
      logo: "assets/portfolio_manager.svg",
      extras: [
        "README.md",
        "LICENSE",
        "guides/01_overview.md",
        "guides/02_installation_and_init.md",
        "guides/03_configuration_and_structure.md",
        "guides/04_cli_reference.md",
        "guides/05_detection_and_metadata.md",
        "guides/06_agentic_detection_and_review.md",
        "guides/07_views_and_graph.md",
        "guides/08_workflows.md",
        "guides/09_search_and_cache.md",
        "guides/10_library_api.md",
        "guides/11_operations_and_migration.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/01_overview.md",
          "guides/02_installation_and_init.md",
          "guides/03_configuration_and_structure.md",
          "guides/04_cli_reference.md",
          "guides/05_detection_and_metadata.md",
          "guides/06_agentic_detection_and_review.md",
          "guides/07_views_and_graph.md",
          "guides/08_workflows.md",
          "guides/09_search_and_cache.md",
          "guides/10_library_api.md",
          "guides/11_operations_and_migration.md"
        ]
      ],
      groups_for_modules: [
        Core: [
          PortfolioManager,
          PortfolioManager.Portfolio,
          PortfolioManager.Graph,
          PortfolioManager.Views
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
        ],
        Detection: [
          PortfolioManager.Detection.Agentic
        ],
        Workflow: [
          PortfolioManager.Workflow.Engine,
          PortfolioManager.Workflow.Parser,
          PortfolioManager.Workflow.Context,
          PortfolioManager.Workflow.Step
        ],
        Cache: [
          PortfolioManager.Cache.SQLite
        ],
        RAG: [
          PortfolioManager.Rag,
          PortfolioManager.Rag.Tools.SearchRepos,
          PortfolioManager.Rag.Tools.GetRepoContext,
          PortfolioManager.Rag.Tools.ListRepos,
          PortfolioManager.Rag.Tools.FindRelationships,
          PortfolioManager.Rag.Tools.CompareRepos,
          PortfolioManager.Rag.Tools.GetPortfolioStats
        ]
      ]
    ]
  end
end
