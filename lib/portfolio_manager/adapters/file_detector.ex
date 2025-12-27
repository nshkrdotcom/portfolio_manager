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

  @elixir_frameworks [
    {":phoenix", "phoenix"},
    {":nerves", "nerves"},
    {":absinthe", "absinthe"},
    {":scenic", "scenic"},
    {":livebook", "livebook"},
    {":ash", "ash"},
    {":commanded", "commanded"}
  ]

  @js_frameworks [
    {"\"next\"", "next"},
    {"\"@remix-run/", "remix"},
    {"\"nuxt\"", "nuxt"},
    {"\"@angular/core\"", "angular"},
    {"\"react\"", "react"},
    {"\"vue\"", "vue"},
    {"\"svelte\"", "svelte"},
    {"\"express\"", "express"},
    {"\"fastify\"", "fastify"},
    {"\"koa\"", "koa"}
  ]

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
    language = find_language_from_indicators(expanded)
    {:ok, language || :unknown}
  end

  defp find_language_from_indicators(expanded) do
    Enum.find_value(@language_indicators, fn {file_pattern, lang} ->
      check_language_indicator(expanded, file_pattern, lang)
    end)
  end

  defp check_language_indicator(expanded, file_pattern, lang) do
    if String.contains?(file_pattern, "*") do
      check_wildcard_pattern(expanded, file_pattern, lang)
    else
      if File.exists?(Path.join(expanded, file_pattern)), do: lang
    end
  end

  defp check_wildcard_pattern(expanded, file_pattern, lang) do
    pattern = String.replace(file_pattern, "*", "")

    case File.ls(expanded) do
      {:ok, files} -> if Enum.any?(files, &String.ends_with?(&1, pattern)), do: lang
      _ -> nil
    end
  end

  @impl true
  def detect_type(path) do
    expanded = Path.expand(path)

    if port?(expanded) do
      {:ok, :port}
    else
      type = detect_type_from_files(expanded)
      {:ok, type || :unknown}
    end
  end

  defp detect_type_from_files(path) do
    detect_elixir_type(path) ||
      detect_python_type(path) ||
      detect_javascript_type(path) ||
      detect_rust_type(path)
  end

  defp detect_elixir_type(path) do
    mix_path = Path.join(path, "mix.exs")

    with true <- File.exists?(mix_path),
         {:ok, content} <- File.read(mix_path),
         true <- mix_project?(content) do
      return_if_no_app(path, :library)
    else
      _ -> nil
    end
  end

  defp mix_project?(content) do
    Regex.match?(~r/def project/s, content) and Regex.match?(~r/app:/, content)
  end

  defp detect_python_type(path) do
    setup_path = Path.join(path, "setup.py")

    with true <- File.exists?(setup_path),
         {:ok, content} <- File.read(setup_path),
         true <- Regex.match?(~r/packages=find_packages/, content) do
      :library
    else
      _ -> nil
    end
  end

  defp detect_javascript_type(path) do
    pkg_path = Path.join(path, "package.json")

    with true <- File.exists?(pkg_path),
         {:ok, content} <- File.read(pkg_path) do
      classify_js_type(content)
    else
      _ -> nil
    end
  end

  defp classify_js_type(content) do
    cond do
      Regex.match?(~r/"bin":/, content) -> :application
      Regex.match?(~r/"main":/, content) -> :library
      true -> nil
    end
  end

  defp detect_rust_type(path) do
    cargo_path = Path.join(path, "Cargo.toml")

    with true <- File.exists?(cargo_path),
         {:ok, content} <- File.read(cargo_path) do
      classify_rust_type(content)
    else
      _ -> nil
    end
  end

  defp classify_rust_type(content) do
    cond do
      Regex.match?(~r/\[\[bin\]\]/, content) -> :application
      Regex.match?(~r/\[lib\]/, content) -> :library
      true -> nil
    end
  end

  defp return_if_no_app(path, type) do
    lib_path = Path.join(path, "lib")

    if File.dir?(lib_path) do
      check_for_application_ex(lib_path, type)
    else
      type
    end
  end

  defp check_for_application_ex(lib_path, type) do
    case File.ls(lib_path) do
      {:ok, dirs} -> if has_application_file?(lib_path, dirs), do: :application, else: type
      _ -> type
    end
  end

  defp has_application_file?(lib_path, dirs) do
    Enum.any?(dirs, fn dir ->
      app_path = Path.join([lib_path, dir, "application.ex"])
      File.exists?(app_path)
    end)
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

  defp port?(path) do
    readme_path = Path.join(path, "README.md")

    with true <- File.exists?(readme_path),
         {:ok, content} <- File.read(readme_path) do
      port_readme?(content)
    else
      _ -> false
    end
  end

  defp port_readme?(content) do
    content_lower = String.downcase(content)

    Regex.match?(~r/port of|ported from|elixir (port|implementation) of/i, content_lower) or
      Regex.match?(~r/based on.*\bgithub\.com\b/i, content_lower)
  end

  defp detect_framework(path, :elixir) do
    mix_path = Path.join(path, "mix.exs")

    with true <- File.exists?(mix_path),
         {:ok, content} <- File.read(mix_path) do
      find_elixir_framework(content)
    else
      _ -> nil
    end
  end

  defp detect_framework(path, :python) do
    files = list_files(path)
    deps = detect_python_deps(path) |> flatten_deps()

    find_python_framework(files, deps)
  end

  defp detect_framework(path, :javascript) do
    pkg_path = Path.join(path, "package.json")

    with true <- File.exists?(pkg_path),
         {:ok, content} <- File.read(pkg_path) do
      find_js_framework(content)
    else
      _ -> nil
    end
  end

  defp detect_framework(_path, _lang), do: nil

  defp find_elixir_framework(content) do
    Enum.find_value(@elixir_frameworks, fn {pattern, framework} ->
      if String.contains?(content, pattern), do: framework
    end)
  end

  defp find_python_framework(files, deps) do
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

  defp find_js_framework(content) do
    Enum.find_value(@js_frameworks, fn {pattern, framework} ->
      if String.contains?(content, pattern), do: framework
    end)
  end

  defp detect_elixir_deps(path) do
    mix_path = Path.join(path, "mix.exs")

    with true <- File.exists?(mix_path),
         {:ok, content} <- File.read(mix_path) do
      content
      |> extract_mix_deps_sections()
      |> Enum.reduce(empty_dep_buckets(), fn section, acc ->
        merge_dep_buckets(acc, parse_mix_deps_section(section))
      end)
    else
      _ -> empty_dep_buckets()
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

    with true <- File.exists?(pyproject_path),
         {:ok, content} <- File.read(pyproject_path) do
      runtime =
        content
        |> extract_toml_section("project")
        |> extract_toml_array("dependencies")
        |> Enum.map(&normalize_python_dep/1)

      {dev, optional} = extract_pyproject_optional(content)

      normalize_dep_buckets(%{runtime: runtime, dev: dev, optional: optional})
    else
      _ -> empty_dep_buckets()
    end
  end

  defp detect_setup_py_deps(path) do
    setup_path = Path.join(path, "setup.py")

    with true <- File.exists?(setup_path),
         {:ok, content} <- File.read(setup_path) do
      runtime =
        content
        |> extract_python_list("install_requires")
        |> Enum.map(&normalize_python_dep/1)

      dev_from_tests =
        content
        |> extract_python_list("tests_require")
        |> Enum.map(&normalize_python_dep/1)

      {dev, optional} = extract_setup_extras(content)

      normalize_dep_buckets(%{
        runtime: runtime,
        dev: Enum.uniq(dev ++ dev_from_tests),
        optional: optional
      })
    else
      _ -> empty_dep_buckets()
    end
  end

  defp detect_requirements_deps(path) do
    runtime = read_requirements(path)
    normalize_dep_buckets(%{runtime: runtime, dev: [], optional: []})
  end

  defp detect_js_deps(path) do
    pkg_path = Path.join(path, "package.json")

    with true <- File.exists?(pkg_path),
         {:ok, content} <- File.read(pkg_path),
         {:ok, pkg} <- Jason.decode(content) do
      parse_package_json_deps(pkg)
    else
      _ -> empty_dep_buckets()
    end
  end

  defp parse_package_json_deps(pkg) do
    runtime = Map.get(pkg, "dependencies", %{}) |> Map.keys()
    dev = Map.get(pkg, "devDependencies", %{}) |> Map.keys()
    peer = Map.get(pkg, "peerDependencies", %{}) |> Map.keys()
    optional = Map.get(pkg, "optionalDependencies", %{}) |> Map.keys()

    normalize_dep_buckets(%{
      runtime: runtime,
      dev: dev,
      optional: Enum.uniq(peer ++ optional)
    })
  end

  defp detect_rust_deps(path) do
    cargo_path = Path.join(path, "Cargo.toml")

    with true <- File.exists?(cargo_path),
         {:ok, content} <- File.read(cargo_path) do
      parse_cargo_deps(content)
    else
      _ -> empty_dep_buckets()
    end
  end

  defp parse_cargo_deps(content) do
    {_, deps} =
      content
      |> String.split("\n")
      |> Enum.reduce({nil, empty_dep_buckets()}, &process_cargo_line/2)

    normalize_dep_buckets(deps)
  end

  defp process_cargo_line(line, {current, acc}) do
    case classify_cargo_line(line) do
      {:section, new_section} -> {new_section, acc}
      :other_section -> {nil, acc}
      :dep when current in [:runtime, :dev, :optional] -> add_cargo_dep(line, current, acc)
      _ -> {current, acc}
    end
  end

  defp classify_cargo_line(line) do
    cond do
      Regex.match?(~r/^\s*\[dependencies\]\s*$/, line) -> {:section, :runtime}
      Regex.match?(~r/^\s*\[dev-dependencies\]\s*$/, line) -> {:section, :dev}
      Regex.match?(~r/^\s*\[build-dependencies\]\s*$/, line) -> {:section, :optional}
      Regex.match?(~r/^\s*\[.+\]\s*$/, line) -> :other_section
      true -> :dep
    end
  end

  defp add_cargo_dep(line, current, acc) do
    case Regex.run(~r/^\s*([A-Za-z0-9_-]+)\s*=/, line) do
      [_, dep] -> {current, Map.update(acc, current, [dep], &[dep | &1])}
      _ -> {current, acc}
    end
  end

  defp detect_go_deps(path) do
    go_mod_path = Path.join(path, "go.mod")

    with true <- File.exists?(go_mod_path),
         {:ok, content} <- File.read(go_mod_path) do
      parse_go_mod_deps(content)
    else
      _ -> empty_dep_buckets()
    end
  end

  defp parse_go_mod_deps(content) do
    runtime =
      ~r/(?:require\s+|\t)([\w\.\-\/]+)\s+v/
      |> Regex.scan(content)
      |> Enum.map(fn [_, dep] -> dep end)
      |> Enum.reject(&String.contains?(&1, "// indirect"))
      |> Enum.uniq()

    normalize_dep_buckets(%{runtime: runtime, dev: [], optional: []})
  end

  defp read_requirements(path) do
    req_path = Path.join(path, "requirements.txt")

    with true <- File.exists?(req_path),
         {:ok, content} <- File.read(req_path) do
      parse_requirements_content(content)
    else
      _ -> []
    end
  end

  defp parse_requirements_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
    |> Enum.map(&normalize_python_dep/1)
    |> Enum.reject(&(&1 == ""))
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
      Regex.match?(~r/optional:\s*true/, opts) -> :optional
      Regex.match?(~r/only:\s*\[?[^\]]*:(dev|test)[^\]]*\]?/, opts) -> :dev
      Regex.match?(~r/only:\s*:(dev|test)/, opts) -> :dev
      true -> :runtime
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
    parse_optional_deps_section(section)
  end

  defp parse_optional_deps_section(nil), do: {[], []}

  defp parse_optional_deps_section(section) do
    Regex.scan(~r/^\s*([A-Za-z0-9_-]+)\s*=\s*\[(.*?)\]/ms, section)
    |> Enum.reduce({[], []}, &classify_optional_group/2)
    |> then(fn {dev, optional} -> {Enum.uniq(dev), Enum.uniq(optional)} end)
  end

  defp classify_optional_group([_, group, list_body], {dev, optional}) do
    deps = list_body |> extract_quoted_strings() |> Enum.map(&normalize_python_dep/1)

    if String.downcase(group) in ["dev", "test", "tests", "development"] do
      {dev ++ deps, optional}
    else
      {dev, optional ++ deps}
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
      [_, body] -> parse_extras_require(body)
      _ -> {[], []}
    end
  end

  defp parse_extras_require(body) do
    Regex.scan(~r/["']([^"']+)["']\s*:\s*\[(.*?)\]/ms, body)
    |> Enum.reduce({[], []}, &classify_extras_group/2)
    |> then(fn {dev, optional} -> {Enum.uniq(dev), Enum.uniq(optional)} end)
  end

  defp classify_extras_group([_, group, list_body], {dev, optional}) do
    deps = list_body |> extract_quoted_strings() |> Enum.map(&normalize_python_dep/1)

    if String.downcase(group) in ["dev", "test", "tests", "development"] do
      {dev ++ deps, optional}
    else
      {dev, optional ++ deps}
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
    case {language, type} do
      {:unknown, :unknown} -> 0.1
      {:unknown, _} -> 0.3
      {_, :unknown} -> 0.5
      {_, _} -> 0.8
    end
  end
end
