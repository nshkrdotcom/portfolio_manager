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

      assert "phoenix" in deps
      assert "ecto" in deps
      assert "jason" in deps
      assert "plug_cowboy" in deps
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

      assert "oban" in deps
      assert "telemetry" in deps
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

      assert "django" in deps
      assert "requests" in deps
      assert "numpy" in deps
      assert "pandas" in deps
      assert "flask" in deps
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

      assert "fastapi" in deps
      assert "uvicorn" in deps
      assert "pydantic" in deps
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
        }
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, deps} = FileDetector.detect_dependencies(tmp_dir)

      assert "react" in deps
      assert "axios" in deps
      assert "jest" in deps
      assert "typescript" in deps
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

      assert "lodash" in deps
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

      assert "tokio" in deps
      assert "serde" in deps
      assert "reqwest" in deps
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

      assert "github.com/gin-gonic/gin" in deps or "gin" in deps
      assert "github.com/spf13/cobra" in deps or "cobra" in deps
    end
  end
end
