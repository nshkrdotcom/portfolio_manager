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
        :go -> detect_go_deps(expanded)
        _ -> empty_dep_buckets()
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
            String.contains?(content, ":scenic") -> "scenic"
            String.contains?(content, ":livebook") -> "livebook"
            String.contains?(content, ":ash") -> "ash"
            String.contains?(content, ":commanded") -> "commanded"
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
    deps = detect_python_deps(path) |> flatten_deps()

    cond do
      "manage.py" in files -> "django"
      "django" in deps -> "django"
      "fastapi" in deps -> "fastapi"
      "flask" in deps -> "flask"
      "streamlit" in deps -> "streamlit"
      "gradio" in deps -> "gradio"
      true -> nil
    end
  end

  defp detect_framework(path, :javascript) do
    pkg_path = Path.join(path, "package.json")

    if File.exists?(pkg_path) do
      case File.read(pkg_path) do
        {:ok, content} ->
          # Priority order: meta-frameworks before base frameworks
          cond do
            # Meta-frameworks (take priority)
            String.contains?(content, "\"next\"") -> "next"
            String.contains?(content, "\"@remix-run/") -> "remix"
            String.contains?(content, "\"nuxt\"") -> "nuxt"
            String.contains?(content, "\"@angular/core\"") -> "angular"
            # Base frameworks
            String.contains?(content, "\"react\"") -> "react"
            String.contains?(content, "\"vue\"") -> "vue"
            String.contains?(content, "\"svelte\"") -> "svelte"
            # Backend frameworks
            String.contains?(content, "\"express\"") -> "express"
            String.contains?(content, "\"fastify\"") -> "fastify"
            String.contains?(content, "\"koa\"") -> "koa"
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
          sections = extract_mix_deps_sections(content)

          sections
          |> Enum.reduce(empty_dep_buckets(), fn section, acc ->
            merge_dep_buckets(acc, parse_mix_deps_section(section))
          end)

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
    end
  end

  defp detect_python_deps(path) do
    empty_dep_buckets()
    |> merge_dep_buckets(detect_pyproject_deps(path))
    |> merge_dep_buckets(detect_setup_py_deps(path))
    |> merge_dep_buckets(detect_requirements_deps(path))
  end

  defp detect_pyproject_deps(path) do
    pyproject_path = Path.join(path, "pyproject.toml")

    if File.exists?(pyproject_path) do
      case File.read(pyproject_path) do
        {:ok, content} ->
          runtime =
            content
            |> extract_toml_section("project")
            |> extract_toml_array("dependencies")
            |> Enum.map(&normalize_python_dep/1)

          {dev, optional} = extract_pyproject_optional(content)

          %{
            runtime: runtime,
            dev: dev,
            optional: optional
          }
          |> normalize_dep_buckets()

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
    end
  end

  defp detect_setup_py_deps(path) do
    setup_path = Path.join(path, "setup.py")

    if File.exists?(setup_path) do
      case File.read(setup_path) do
        {:ok, content} ->
          runtime =
            content
            |> extract_python_list("install_requires")
            |> Enum.map(&normalize_python_dep/1)

          dev_from_tests =
            content
            |> extract_python_list("tests_require")
            |> Enum.map(&normalize_python_dep/1)

          {dev, optional} = extract_setup_extras(content)

          %{
            runtime: runtime,
            dev: Enum.uniq(dev ++ dev_from_tests),
            optional: optional
          }
          |> normalize_dep_buckets()

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
    end
  end

  defp detect_requirements_deps(path) do
    runtime = read_requirements(path)

    %{
      runtime: runtime,
      dev: [],
      optional: []
    }
    |> normalize_dep_buckets()
  end

  defp detect_js_deps(path) do
    pkg_path = Path.join(path, "package.json")

    if File.exists?(pkg_path) do
      case File.read(pkg_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, pkg} ->
              runtime = Map.get(pkg, "dependencies", %{}) |> Map.keys()
              dev = Map.get(pkg, "devDependencies", %{}) |> Map.keys()
              peer = Map.get(pkg, "peerDependencies", %{}) |> Map.keys()
              optional = Map.get(pkg, "optionalDependencies", %{}) |> Map.keys()

              %{
                runtime: runtime,
                dev: dev,
                optional: Enum.uniq(peer ++ optional)
              }
              |> normalize_dep_buckets()

            _ ->
              empty_dep_buckets()
          end

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
    end
  end

  defp detect_rust_deps(path) do
    cargo_path = Path.join(path, "Cargo.toml")

    if File.exists?(cargo_path) do
      case File.read(cargo_path) do
        {:ok, content} ->
          {_, deps} =
            content
            |> String.split("\n")
            |> Enum.reduce({nil, empty_dep_buckets()}, fn line, {current, acc} ->
              cond do
                Regex.match?(~r/^\s*\[dependencies\]\s*$/, line) ->
                  {:runtime, acc}

                Regex.match?(~r/^\s*\[dev-dependencies\]\s*$/, line) ->
                  {:dev, acc}

                Regex.match?(~r/^\s*\[build-dependencies\]\s*$/, line) ->
                  {:optional, acc}

                Regex.match?(~r/^\s*\[.+\]\s*$/, line) ->
                  {nil, acc}

                current in [:runtime, :dev, :optional] ->
                  case Regex.run(~r/^\s*([A-Za-z0-9_-]+)\s*=/, line) do
                    [_, dep] ->
                      {current, Map.update(acc, current, [dep], &[dep | &1])}

                    _ ->
                      {current, acc}
                  end

                true ->
                  {current, acc}
              end
            end)

          normalize_dep_buckets(deps)

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
    end
  end

  defp detect_go_deps(path) do
    go_mod_path = Path.join(path, "go.mod")

    if File.exists?(go_mod_path) do
      case File.read(go_mod_path) do
        {:ok, content} ->
          runtime =
            ~r/(?:require\s+|\t)([\w\.\-\/]+)\s+v/
            |> Regex.scan(content)
            |> Enum.map(fn [_, dep] -> dep end)
            |> Enum.reject(&String.contains?(&1, "// indirect"))
            |> Enum.uniq()

          %{
            runtime: runtime,
            dev: [],
            optional: []
          }
          |> normalize_dep_buckets()

        _ ->
          empty_dep_buckets()
      end
    else
      empty_dep_buckets()
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
          |> Enum.map(&normalize_python_dep/1)
          |> Enum.reject(&(&1 == ""))

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

  defp extract_mix_deps_sections(content) do
    deps_blocks =
      Regex.scan(~r/defp\s+deps\s+do\s*(\[.*?\])\s*end/s, content)
      |> Enum.map(fn [_, block] -> block end)

    inline_blocks =
      Regex.scan(~r/deps:\s*(\[[^\]]*\])/s, content)
      |> Enum.map(fn [_, block] -> block end)

    deps_blocks ++ inline_blocks
  end

  defp parse_mix_deps_section(section) do
    Regex.scan(~r/\{:(\w+)\s*,([^}]*)\}/s, section)
    |> Enum.reduce(empty_dep_buckets(), fn [_, dep, opts], acc ->
      category = classify_elixir_dep(opts)
      Map.update(acc, category, [dep], &[dep | &1])
    end)
    |> normalize_dep_buckets()
  end

  defp classify_elixir_dep(opts) when is_binary(opts) do
    cond do
      Regex.match?(~r/optional:\s*true/, opts) ->
        :optional

      Regex.match?(~r/only:\s*\[?[^\]]*:(dev|test)[^\]]*\]?/, opts) ->
        :dev

      Regex.match?(~r/only:\s*:(dev|test)/, opts) ->
        :dev

      true ->
        :runtime
    end
  end

  defp classify_elixir_dep(_), do: :runtime

  defp extract_toml_section(content, section) do
    case Regex.run(~r/^\s*\[#{Regex.escape(section)}\]\s*$(.*?)(?=^\s*\[|\z)/ms, content) do
      [_, body] -> body
      _ -> nil
    end
  end

  defp extract_toml_array(nil, _key), do: []

  defp extract_toml_array(section, key) do
    multiline = ~r/#{key}\s*=\s*\[(.*?)(?:^\s*\])/ms

    case Regex.run(multiline, section) do
      [_, body] ->
        extract_quoted_strings(body)

      _ ->
        case Regex.run(~r/#{key}\s*=\s*\[(.*?)\]/ms, section) do
          [_, body] -> extract_quoted_strings(body)
          _ -> []
        end
    end
  end

  defp extract_pyproject_optional(content) do
    section = extract_toml_section(content, "project.optional-dependencies")

    if is_binary(section) do
      Regex.scan(~r/^\s*([A-Za-z0-9_-]+)\s*=\s*\[(.*?)\]/ms, section)
      |> Enum.reduce({[], []}, fn [_, group, list_body], {dev, optional} ->
        deps = extract_quoted_strings(list_body) |> Enum.map(&normalize_python_dep/1)
        group = String.downcase(group)

        if group in ["dev", "test", "tests", "development"] do
          {dev ++ deps, optional}
        else
          {dev, optional ++ deps}
        end
      end)
      |> then(fn {dev, optional} ->
        {Enum.uniq(dev), Enum.uniq(optional)}
      end)
    else
      {[], []}
    end
  end

  defp extract_python_list(content, key) do
    case Regex.run(~r/#{key}\s*=\s*\[(.*?)\]/ms, content) do
      [_, body] -> extract_quoted_strings(body)
      _ -> []
    end
  end

  defp extract_setup_extras(content) do
    case Regex.run(~r/extras_require\s*=\s*\{(.*?)\}/ms, content) do
      [_, body] ->
        Regex.scan(~r/["']([^"']+)["']\s*:\s*\[(.*?)\]/ms, body)
        |> Enum.reduce({[], []}, fn [_, group, list_body], {dev, optional} ->
          deps = extract_quoted_strings(list_body) |> Enum.map(&normalize_python_dep/1)
          group = String.downcase(group)

          if group in ["dev", "test", "tests", "development"] do
            {dev ++ deps, optional}
          else
            {dev, optional ++ deps}
          end
        end)
        |> then(fn {dev, optional} ->
          {Enum.uniq(dev), Enum.uniq(optional)}
        end)

      _ ->
        {[], []}
    end
  end

  defp extract_quoted_strings(body) when is_binary(body) do
    Regex.scan(~r/["']([^"']+)["']/, body)
    |> Enum.map(fn [_, value] -> String.trim(value) end)
  end

  defp normalize_python_dep(dep) when is_binary(dep) do
    dep
    |> String.trim()
    |> String.split(~r/[\s\[\(<>=!~;]/, parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp empty_dep_buckets do
    %{runtime: [], dev: [], optional: []}
  end

  defp merge_dep_buckets(a, b) do
    %{
      runtime: Enum.uniq(a.runtime ++ b.runtime),
      dev: Enum.uniq(a.dev ++ b.dev),
      optional: Enum.uniq(a.optional ++ b.optional)
    }
    |> normalize_dep_buckets()
  end

  defp normalize_dep_buckets(deps) do
    %{
      runtime: deps.runtime |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.sort(),
      dev: deps.dev |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.sort(),
      optional: deps.optional |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp flatten_deps(%{runtime: runtime, dev: dev, optional: optional}) do
    Enum.uniq(runtime ++ dev ++ optional)
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
