defmodule PortfolioManager.Detection.FrameworkDetectionTest do
  @moduledoc """
  Tests for framework detection based on dependencies.
  """

  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.FileDetector

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "framework_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "Elixir framework detection" do
    test "detects Phoenix framework", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, deps: deps()]
        end

        defp deps do
          [{:phoenix, "~> 1.7"}, {:phoenix_live_view, "~> 0.19"}]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "phoenix"
    end

    test "detects Nerves framework", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, deps: deps()]
        end

        defp deps do
          [{:nerves, "~> 1.10"}, {:nerves_runtime, "~> 0.13"}]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "nerves"
    end

    test "detects Absinthe framework", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, deps: deps()]
        end

        defp deps do
          [{:absinthe, "~> 1.7"}, {:absinthe_plug, "~> 1.5"}]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "absinthe"
    end

    test "detects Scenic framework", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, deps: deps()]
        end

        defp deps do
          [{:scenic, "~> 0.11"}]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "scenic"
    end

    test "detects Livebook dependency", %{tmp_dir: tmp_dir} do
      mix_content = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, deps: deps()]
        end

        defp deps do
          [{:livebook, "~> 0.12"}]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "livebook"
    end
  end

  describe "Python framework detection" do
    test "detects Django framework", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "manage.py"), "#!/usr/bin/env python")
      File.write!(Path.join(tmp_dir, "requirements.txt"), "django>=4.0\n")

      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "django"
    end

    test "detects FastAPI framework", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "requirements.txt"), "fastapi>=0.100.0\nuvicorn\n")

      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "fastapi"
    end

    test "detects Flask framework", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "requirements.txt"), "flask>=2.0\n")

      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "flask"
    end

    test "detects Streamlit framework", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "requirements.txt"), "streamlit>=1.0\n")

      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "streamlit"
    end
  end

  describe "JavaScript framework detection" do
    test "detects React framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"react": "^18.0.0", "react-dom": "^18.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "react"
    end

    test "detects Vue framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"vue": "^3.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "vue"
    end

    test "detects Next.js framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"next": "^14.0.0", "react": "^18.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      # Next.js should take priority over React
      assert result.framework == "next"
    end

    test "detects Angular framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"@angular/core": "^17.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "angular"
    end

    test "detects Remix framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"@remix-run/node": "^2.0.0", "react": "^18.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "remix"
    end

    test "detects Express framework", %{tmp_dir: tmp_dir} do
      pkg_json = """
      {
        "name": "my-app",
        "dependencies": {"express": "^4.0.0"}
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), pkg_json)
      {:ok, result} = FileDetector.detect(tmp_dir)

      assert result.framework == "express"
    end
  end
end
