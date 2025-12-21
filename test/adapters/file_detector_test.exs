defmodule PortfolioManager.Adapters.FileDetectorTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.FileDetector

  describe "detect_language/1" do
    test "detects Elixir from mix.exs" do
      path = Path.join(System.tmp_dir!(), "elixir_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "mix.exs"), "defmodule Test.MixProject do end")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :elixir} = FileDetector.detect_language(path)
    end

    test "detects Python from requirements.txt" do
      path = Path.join(System.tmp_dir!(), "python_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "requirements.txt"), "flask==2.0.0")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :python} = FileDetector.detect_language(path)
    end

    test "detects JavaScript from package.json" do
      path = Path.join(System.tmp_dir!(), "js_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "package.json"), "{}")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :javascript} = FileDetector.detect_language(path)
    end

    test "detects Rust from Cargo.toml" do
      path = Path.join(System.tmp_dir!(), "rust_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "Cargo.toml"), "[package]")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :rust} = FileDetector.detect_language(path)
    end

    test "returns :unknown for unrecognized repo" do
      path = Path.join(System.tmp_dir!(), "unknown_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      File.write!(Path.join(path, "README.md"), "# Hello")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :unknown} = FileDetector.detect_language(path)
    end
  end

  describe "detect_type/1" do
    test "detects Elixir library" do
      path = Path.join(System.tmp_dir!(), "elixir_lib_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "mix.exs"), """
      defmodule MyLib.MixProject do
        use Mix.Project

        def project do
          [app: :my_lib, version: "0.1.0"]
        end
      end
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :library} = FileDetector.detect_type(path)
    end

    test "detects port from README" do
      path = Path.join(System.tmp_dir!(), "port_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "README.md"), """
      # MyPort

      This is an Elixir port of the Python library instructor.
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, :port} = FileDetector.detect_type(path)
    end
  end

  describe "detect_dependencies/1" do
    test "detects Elixir dependencies" do
      path = Path.join(System.tmp_dir!(), "elixir_deps_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          [
            {:phoenix, "~> 1.7"},
            {:ecto, "~> 3.10"},
            {:jason, "~> 1.4"}
          ]
        end
      end
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, deps} = FileDetector.detect_dependencies(path)
      assert "phoenix" in deps
      assert "ecto" in deps
      assert "jason" in deps
    end

    test "detects Python dependencies" do
      path = Path.join(System.tmp_dir!(), "python_deps_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "requirements.txt"), """
      flask==2.0.0
      requests>=2.28
      numpy
      # comment
      pandas==1.5.0
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, deps} = FileDetector.detect_dependencies(path)
      assert "flask" in deps
      assert "requests" in deps
      assert "numpy" in deps
      assert "pandas" in deps
    end

    test "detects JavaScript dependencies" do
      path = Path.join(System.tmp_dir!(), "js_deps_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "package.json"), """
      {
        "dependencies": {
          "react": "^18.0.0",
          "axios": "^1.0.0"
        },
        "devDependencies": {
          "jest": "^29.0.0"
        }
      }
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, deps} = FileDetector.detect_dependencies(path)
      assert "react" in deps
      assert "axios" in deps
      assert "jest" in deps
    end
  end

  describe "detect/1" do
    test "returns full detection result" do
      path = Path.join(System.tmp_dir!(), "full_detect_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)

      File.write!(Path.join(path, "mix.exs"), """
      defmodule MyLib.MixProject do
        use Mix.Project

        def project do
          [app: :my_lib, version: "0.1.0"]
        end

        defp deps do
          [{:jason, "~> 1.4"}]
        end
      end
      """)

      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, result} = FileDetector.detect(path)
      assert result.language == :elixir
      assert result.type == :library
      assert "jason" in result.dependencies
      assert result.confidence > 0
    end
  end
end
