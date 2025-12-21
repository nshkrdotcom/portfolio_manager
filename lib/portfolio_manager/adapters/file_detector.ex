defmodule PortfolioManager.Adapters.FileDetector do
  @moduledoc """
  File-based detection adapter.

  Detects repository metadata by analyzing files and directory structure.
  """

  @behaviour PortfolioManager.Ports.Detection

  @language_indicators %{
    "mix.exs" => :elixir,
    "rebar.config" => :erlang,
    "Cargo.toml" => :rust,
    "package.json" => :javascript,
    "pyproject.toml" => :python,
    "setup.py" => :python,
    "requirements.txt" => :python,
    "Gemfile" => :ruby,
    "go.mod" => :go,
    "pom.xml" => :java,
    "build.gradle" => :java,
    "CMakeLists.txt" => :cpp,
    "Makefile" => :c,
    "*.csproj" => :csharp,
    "pubspec.yaml" => :dart
  }

  @impl true
  def detect(path) do
    expanded = Path.expand(path)

    with {:ok, language} <- detect_language(expanded),
         {:ok, type} <- detect_type(expanded),
         {:ok, deps} <- detect_dependencies(expanded) do
      {:ok,
       %{
         language: language,
         type: type,
         framework: detect_framework(expanded, language),
         dependencies: deps,
         confidence: calculate_confidence(language, type)
       }}
    end
  end

  @impl true
  def detect_language(path) do
    expanded = Path.expand(path)

    language =
      @language_indicators
      |> Enum.find_value(fn {file_pattern, lang} ->
        if String.contains?(file_pattern, "*") do
          pattern = String.replace(file_pattern, "*", "")

          case File.ls(expanded) do
            {:ok, files} ->
              if Enum.any?(files, &String.ends_with?(&1, pattern)), do: lang

            _ ->
              nil
          end
        else
          if File.exists?(Path.join(expanded, file_pattern)), do: lang
        end
      end)

    {:ok, language || :unknown}
  end

  @impl true
  def detect_type(path) do
    expanded = Path.expand(path)

    # Check for port indicators first
    if is_port?(expanded) do
      {:ok, :port}
    else
      type = detect_type_from_files(expanded)
      {:ok, type || :unknown}
    end
  end

  defp detect_type_from_files(path) do
    # Check Elixir library
    mix_path = Path.join(path, "mix.exs")

    if File.exists?(mix_path) do
      case File.read(mix_path) do
        {:ok, content} ->
          # Check for mix project with app and version
          if Regex.match?(~r/def project/s, content) and
               Regex.match?(~r/app:/, content) do
            return_if_no_app(path, :library)
          else
            nil
          end

        _ ->
          nil
      end
    else
      # Check Python
      setup_path = Path.join(path, "setup.py")

      if File.exists?(setup_path) do
        case File.read(setup_path) do
          {:ok, content} ->
            if Regex.match?(~r/packages=find_packages/, content), do: :library

          _ ->
            nil
        end
      else
        # Check JavaScript
        pkg_path = Path.join(path, "package.json")

        if File.exists?(pkg_path) do
          case File.read(pkg_path) do
            {:ok, content} ->
              cond do
                Regex.match?(~r/"bin":/, content) -> :application
                Regex.match?(~r/"main":/, content) -> :library
                true -> nil
              end

            _ ->
              nil
          end
        else
          # Check Rust
          cargo_path = Path.join(path, "Cargo.toml")

          if File.exists?(cargo_path) do
            case File.read(cargo_path) do
              {:ok, content} ->
                cond do
                  Regex.match?(~r/\[\[bin\]\]/, content) -> :application
                  Regex.match?(~r/\[lib\]/, content) -> :library
                  true -> nil
                end

              _ ->
                nil
            end
          else
            nil
          end
        end
      end
    end
  end

  defp return_if_no_app(path, type) do
    # Check if this is an application (has application.ex)
    lib_path = Path.join(path, "lib")

    if File.dir?(lib_path) do
      case File.ls(lib_path) do
        {:ok, dirs} ->
          has_app =
            Enum.any?(dirs, fn dir ->
              app_path = Path.join([lib_path, dir, "application.ex"])
              File.exists?(app_path)
            end)

          if has_app, do: :application, else: type

        _ ->
          type
      end
    else
      type
    end
  end

  @impl true
  def detect_dependencies(path) do
    expanded = Path.expand(path)
    {:ok, language} = detect_language(expanded)

    deps =
      case language do
        :elixir -> detect_elixir_deps(expanded)
        :python -> detect_python_deps(expanded)
        :javascript -> detect_js_deps(expanded)
        :rust -> detect_rust_deps(expanded)
        _ -> []
      end

    {:ok, deps}
  end

  # Private helpers

  defp is_port?(path) do
    readme_path = Path.join(path, "README.md")

    if File.exists?(readme_path) do
      case File.read(readme_path) do
        {:ok, content} ->
          content_lower = String.downcase(content)

          Regex.match?(~r/port of|ported from|elixir (port|implementation) of/i, content_lower) or
            Regex.match?(~r/based on.*\bgithub\.com\b/i, content_lower)

        _ ->
          false
      end
    else
      false
    end
  end

  defp detect_framework(path, :elixir) do
    mix_path = Path.join(path, "mix.exs")

    if File.exists?(mix_path) do
      case File.read(mix_path) do
        {:ok, content} ->
          cond do
            String.contains?(content, ":phoenix") -> "phoenix"
            String.contains?(content, ":nerves") -> "nerves"
            String.contains?(content, ":absinthe") -> "absinthe"
            true -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp detect_framework(path, :python) do
    files = list_files(path)

    cond do
      "manage.py" in files -> "django"
      "flask" in read_requirements(path) -> "flask"
      "fastapi" in read_requirements(path) -> "fastapi"
      true -> nil
    end
  end

  defp detect_framework(path, :javascript) do
    pkg_path = Path.join(path, "package.json")

    if File.exists?(pkg_path) do
      case File.read(pkg_path) do
        {:ok, content} ->
          cond do
            String.contains?(content, "\"react\"") -> "react"
            String.contains?(content, "\"vue\"") -> "vue"
            String.contains?(content, "\"next\"") -> "next"
            String.contains?(content, "\"express\"") -> "express"
            true -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp detect_framework(_path, _lang), do: nil

  defp detect_elixir_deps(path) do
    mix_path = Path.join(path, "mix.exs")

    if File.exists?(mix_path) do
      case File.read(mix_path) do
        {:ok, content} ->
          ~r/\{:(\w+),/
          |> Regex.scan(content)
          |> Enum.map(fn [_, dep] -> dep end)
          |> Enum.uniq()

        _ ->
          []
      end
    else
      []
    end
  end

  defp detect_python_deps(path) do
    read_requirements(path)
  end

  defp detect_js_deps(path) do
    pkg_path = Path.join(path, "package.json")

    if File.exists?(pkg_path) do
      case File.read(pkg_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, pkg} ->
              deps = Map.get(pkg, "dependencies", %{})
              dev_deps = Map.get(pkg, "devDependencies", %{})
              Map.keys(deps) ++ Map.keys(dev_deps)

            _ ->
              []
          end

        _ ->
          []
      end
    else
      []
    end
  end

  defp detect_rust_deps(path) do
    cargo_path = Path.join(path, "Cargo.toml")

    if File.exists?(cargo_path) do
      case File.read(cargo_path) do
        {:ok, content} ->
          ~r/^(\w[\w-]*)\s*=/m
          |> Regex.scan(content)
          |> Enum.map(fn [_, dep] -> dep end)
          |> Enum.reject(&(&1 in ["name", "version", "edition", "authors"]))

        _ ->
          []
      end
    else
      []
    end
  end

  defp read_requirements(path) do
    req_path = Path.join(path, "requirements.txt")

    if File.exists?(req_path) do
      case File.read(req_path) do
        {:ok, content} ->
          content
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
          |> Enum.map(fn line ->
            line
            |> String.split(~r/[<>=!]/)
            |> List.first()
            |> String.trim()
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  defp list_files(path) do
    case File.ls(path) do
      {:ok, files} -> files
      _ -> []
    end
  end

  defp calculate_confidence(language, type) do
    base =
      case {language, type} do
        {:unknown, :unknown} -> 0.1
        {:unknown, _} -> 0.3
        {_, :unknown} -> 0.5
        {_, _} -> 0.8
      end

    base
  end
end
