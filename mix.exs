defmodule PortfolioManager.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_manager"

  def project do
    [
      app: :portfolio_manager,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :portfolio_core],
        flags: [:error_handling, :unknown, :unmatched_returns]
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

  def cli do
    [
      preferred_envs: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp deps do
    [
      # Core packages
      {:portfolio_core, path: "../portfolio_core"},
      {:portfolio_index, path: "../portfolio_index"},
      # TODO: nsai_llm doesn't exist yet - commented out temporarily
      # {:nsai_llm, "~> 0.1.0"},
      {:hammer, "~> 6.1"},

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
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:supertester, "~> 0.5.1", only: :test}
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
        # Introduction
        "guides/getting_started.md",
        # Core Guides
        "guides/llm.md",
        "guides/rag.md",
        "guides/router.md",
        "guides/streaming.md",
        # Advanced
        "guides/agent.md",
        "guides/pipeline.md",
        "guides/graph.md",
        "guides/evaluation.md",
        # Reference
        "guides/cli.md",
        "guides/configuration.md",
        # About
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Introduction: ["README.md", "guides/getting_started.md"],
        "Core Guides": [
          "guides/llm.md",
          "guides/rag.md",
          "guides/router.md",
          "guides/streaming.md"
        ],
        Advanced: [
          "guides/agent.md",
          "guides/pipeline.md",
          "guides/graph.md",
          "guides/evaluation.md"
        ],
        Reference: [
          "guides/cli.md",
          "guides/configuration.md"
        ],
        About: ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "LLM & Routing": [
          PortfolioManager.LLM,
          PortfolioManager.Router
        ],
        "RAG & Generation": [
          PortfolioManager.RAG,
          PortfolioManager.Generation,
          PortfolioManager.Evaluation
        ],
        Agent: [
          PortfolioManager.Agent,
          PortfolioManager.Agent.Session,
          PortfolioManager.Agent.Tool
        ],
        Orchestration: [
          PortfolioManager.Pipeline,
          PortfolioManager.Graph
        ],
        Infrastructure: [
          PortfolioManager,
          PortfolioManager.Application,
          PortfolioManager.Repo,
          PortfolioManager.Domain.Registry
        ],
        "Mix Tasks": [
          Mix.Tasks.Portfolio.Ask,
          Mix.Tasks.Portfolio.Search,
          Mix.Tasks.Portfolio.Index,
          Mix.Tasks.Portfolio.Graph,
          Mix.Tasks.Portfolio.Diagnostics,
          Mix.Tasks.Portfolio.Eval.Generate,
          Mix.Tasks.Portfolio.Eval.Run,
          Mix.Tasks.Portfolio.Reembed
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
      files: ~w(lib priv assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md guides),
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
