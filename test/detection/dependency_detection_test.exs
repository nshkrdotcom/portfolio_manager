defmodule PortfolioManager.Detection.DependencyDetectionTest do
  @moduledoc """
  Tests for enhanced dependency detection.

  Tests parsing of dependency files for multiple languages:
  - Elixir (mix.exs)
  - Python (pyproject.toml, requirements.txt, setup.py)
  - JavaScript (package.json)
  - Rust (Cargo.toml)
  - Go (go.mod)
  """

  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.FileDetector

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "detection_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "Elixir dependency detection" do
    test "detects dependencies from mix.exs", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            elixir: "~> 1.14",
            deps: deps()
          ]
        end

        defp deps do
          [
            {:phoenix, "~> 1.7"},
            {:ecto, "~> 3.10"},
            {:jason, "~> 1.2"},
            {:plug_cowboy, "~> 2.5"}
          ]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "phoenix" in deps.runtime
      assert "ecto" in deps.runtime
      assert "jason" in deps.runtime
      assert "plug_cowboy" in deps.runtime
    end

    test "handles mix.exs with inline deps", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            deps: [{:oban, "~> 2.0"}, {:telemetry, "~> 1.0"}]
          ]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "oban" in deps.runtime
      assert "telemetry" in deps.runtime
    end
  end

  describe "Python dependency detection" do
    test "detects dependencies from requirements.txt", %{tmp_dir: tmp_dir} do
      requirements = """
      django>=4.0
      requests==2.28.0
      numpy
      pandas>=1.5,<2.0
      # This is a comment
      flask
      """

      File.write!(Path.join(tmp_dir, "requirements.txt"), requirements)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "django" in deps.runtime
      assert "requests" in deps.runtime
      assert "numpy" in deps.runtime
      assert "pandas" in deps.runtime
      assert "flask" in deps.runtime
    end

    test "detects dependencies from pyproject.toml", %{tmp_dir: tmp_dir} do
      pyproject = """
      [project]
      name = "my-package"
      version = "0.1.0"
      dependencies = [
          "fastapi>=0.100.0",
          "uvicorn[standard]",
          "pydantic>=2.0",
      ]

      [project.optional-dependencies]
      dev = ["pytest", "black"]
      """

      File.write!(Path.join(tmp_dir, "pyproject.toml"), pyproject)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "fastapi" in deps.runtime
      assert "uvicorn" in deps.runtime
      assert "pydantic" in deps.runtime
      assert "pytest" in deps.dev
      assert "black" in deps.dev
    end

    test "detects dependencies from setup.py", %{tmp_dir: tmp_dir} do
      setup_py = """
      from setuptools import setup

      setup(
        name="my-package",
        install_requires=[
          "requests>=2.28",
          "numpy",
        ],
        extras_require={
          "dev": ["pytest", "black"],
          "docs": ["sphinx"],
        },
      )
      """

      File.write!(Path.join(tmp_dir, "setup.py"), setup_py)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "requests" in deps.runtime
      assert "numpy" in deps.runtime
      assert "pytest" in deps.dev
      assert "black" in deps.dev
      assert "sphinx" in deps.optional
    end
  end

  describe "JavaScript dependency detection" do
    test "detects dependencies from package.json", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "version": "1.0.0",
        "dependencies": {
          "react": "^18.0.0",
          "axios": "^1.0.0"
        },
        "devDependencies": {
          "jest": "^29.0.0",
          "typescript": "^5.0.0"
        },
        "peerDependencies": {
          "react-dom": "^18.0.0"
        }
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "react" in deps.runtime
      assert "axios" in deps.runtime
      assert "jest" in deps.dev
      assert "typescript" in deps.dev
      assert "react-dom" in deps.optional
    end

    test "handles package.json with no devDependencies", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "simple-app",
        "dependencies": {
          "lodash": "^4.0.0"
        }
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "lodash" in deps.runtime
    end
  end

  describe "Rust dependency detection" do
    test "detects dependencies from Cargo.toml", %{tmp_dir: tmp_dir} do
      cargo_toml = """
      [package]
      name = "my-app"
      version = "0.1.0"
      edition = "2021"

      [dependencies]
      tokio = { version = "1.0", features = ["full"] }
      serde = "1.0"
      reqwest = { version = "0.11", default-features = false }

      [dev-dependencies]
      mockall = "0.11"
      """

      File.write!(Path.join(tmp_dir, "Cargo.toml"), cargo_toml)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "tokio" in deps.runtime
      assert "serde" in deps.runtime
      assert "reqwest" in deps.runtime
      assert "mockall" in deps.dev
    end
  end

  describe "Go dependency detection" do
    test "detects dependencies from go.mod", %{tmp_dir: tmp_dir} do
      go_mod = """
      module github.com/user/myapp

      go 1.21

      require (
      \tgithub.com/gin-gonic/gin v1.9.1
      \tgithub.com/spf13/cobra v1.7.0
      \tgorm.io/gorm v1.25.0
      )

      require (
      \tgolang.org/x/net v0.12.0 // indirect
      )
      """

      File.write!(Path.join(tmp_dir, "go.mod"), go_mod)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "github.com/gin-gonic/gin" in deps.runtime or "gin" in deps.runtime
      assert "github.com/spf13/cobra" in deps.runtime or "cobra" in deps.runtime
    end
  end
end
