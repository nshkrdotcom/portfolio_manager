defmodule PortfolioManager.Adapters.YAMLStorage do
  @moduledoc """
  YAML-based storage adapter for portfolio data.

  Stores data in YAML files within a git repository structure:

      portfolio/
      ├── config.yml
      ├── registry.yml
      ├── relationships.yml
      └── repos/
          └── {repo-id}/
              ├── context.yml
              └── notes.md
  """

  @behaviour PortfolioManager.Ports.Storage

  alias PortfolioManager.Domain.{Context, Registry}

  @type state :: %{path: String.t()}

  @impl true
  def init(path) do
    expanded = Path.expand(path)

    if exists?(expanded) do
      {:ok, %{path: expanded}}
    else
      {:error, :not_initialized}
    end
  end

  @impl true
  def exists?(path) do
    expanded = Path.expand(path)
    File.dir?(expanded) and File.exists?(Path.join(expanded, "registry.yml"))
  end

  @impl true
  def create(path) do
    expanded = Path.expand(path)

    with :ok <- File.mkdir_p(expanded),
         :ok <- File.mkdir_p(Path.join(expanded, "repos")),
         :ok <- write_yaml(Path.join(expanded, "config.yml"), default_config()),
         :ok <- write_yaml(Path.join(expanded, "registry.yml"), %{"repos" => []}),
         :ok <- write_yaml(Path.join(expanded, "relationships.yml"), %{"relationships" => []}) do
      :ok
    end
  end

  @impl true
  def load_registry(%{path: path}) do
    registry_path = Path.join(path, "registry.yml")
    rels_path = Path.join(path, "relationships.yml")

    with {:ok, registry_data} <- read_yaml(registry_path),
         {:ok, rels_data} <- read_yaml(rels_path) do
      repos = Map.get(registry_data, "repos") || []
      rels = Map.get(rels_data, "relationships") || []
      Registry.from_data(repos, rels)
    end
  end

  @impl true
  def save_registry(%{path: path}, %Registry{} = registry) do
    {repos_data, rels_data} = Registry.to_data(registry)

    registry_path = Path.join(path, "registry.yml")
    rels_path = Path.join(path, "relationships.yml")

    with :ok <- write_yaml(registry_path, %{"repos" => repos_data}),
         :ok <- write_yaml(rels_path, %{"relationships" => rels_data}) do
      :ok
    end
  end

  @impl true
  def load_context(%{path: path}, repo_id) do
    repo_path = Path.join([path, "repos", repo_id])
    context_path = Path.join(repo_path, "context.yml")
    notes_path = Path.join(repo_path, "notes.md")

    with {:ok, context_data} <- read_yaml(context_path) do
      notes =
        case File.read(notes_path) do
          {:ok, content} -> content
          {:error, _} -> nil
        end

      context_data
      |> Map.put("notes", notes)
      |> Context.from_map()
    end
  end

  @impl true
  def save_context(%{path: path}, %Context{} = context) do
    repo_id = context.repo.id
    repo_path = Path.join([path, "repos", repo_id])
    context_path = Path.join(repo_path, "context.yml")
    notes_path = Path.join(repo_path, "notes.md")

    with :ok <- File.mkdir_p(repo_path),
         context_data = Context.to_map(context),
         # Remove notes from context.yml (stored separately)
         context_data = Map.delete(context_data, "notes"),
         :ok <- write_yaml(context_path, context_data) do
      # Write notes to separate file
      if context.notes do
        File.write(notes_path, context.notes)
      else
        :ok
      end
    end
  end

  # Private helpers

  defp read_yaml(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, data} -> {:ok, data}
      {:error, %YamlElixir.FileNotFoundError{}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_yaml(path, data) do
    yaml = yaml_encode(data)
    File.write(path, yaml)
  end

  defp yaml_encode(data) do
    # Simple YAML encoding
    encode_value(data, 0)
  end

  defp encode_value(nil, _indent), do: "null\n"
  defp encode_value(true, _indent), do: "true\n"
  defp encode_value(false, _indent), do: "false\n"
  defp encode_value(v, _indent) when is_number(v), do: "#{v}\n"

  defp encode_value(v, _indent) when is_binary(v) do
    if String.contains?(v, "\n") do
      "|\n" <> indent_multiline(v, 2)
    else
      safe_string(v) <> "\n"
    end
  end

  defp encode_value(v, _indent) when is_atom(v), do: "#{v}\n"

  defp encode_value(list, indent) when is_list(list) do
    if list == [] do
      "[]\n"
    else
      list
      |> Enum.map(fn item ->
        item_str = encode_value(item, indent + 2) |> String.trim_trailing("\n")

        if is_map(item) do
          # For maps in lists, put first key on same line as dash
          [first | rest] = String.split(item_str, "\n")
          spaces = String.duplicate(" ", indent)
          first_line = "#{spaces}- #{first}"

          rest_lines =
            Enum.map(rest, fn line ->
              "#{spaces}  #{line}"
            end)

          Enum.join([first_line | rest_lines], "\n")
        else
          "#{String.duplicate(" ", indent)}- #{item_str}"
        end
      end)
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    end
  end

  defp encode_value(map, indent) when is_map(map) do
    if map == %{} do
      "{}\n"
    else
      map
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} ->
        key = to_string(k)
        spaces = String.duplicate(" ", indent)

        cond do
          is_map(v) and map_size(v) > 0 ->
            "#{spaces}#{key}:\n#{encode_value(v, indent + 2)}"

          is_list(v) and length(v) > 0 ->
            "#{spaces}#{key}:\n#{encode_value(v, indent + 2)}"

          true ->
            "#{spaces}#{key}: #{encode_value(v, indent) |> String.trim_leading()}"
        end
      end)
      |> Enum.join("")
    end
  end

  defp safe_string(s) do
    if needs_quoting?(s) do
      "\"#{String.replace(s, "\"", "\\\"")}\""
    else
      s
    end
  end

  defp needs_quoting?(s) do
    String.starts_with?(s, [" ", "-", ":", "#", "!", "?", "@", "&", "*", "`", "'", "\""]) or
      String.contains?(s, [": ", " #"]) or
      s in ["true", "false", "null", "yes", "no", "on", "off"]
  end

  defp indent_multiline(text, spaces) do
    indent = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map(fn line -> "#{indent}#{line}" end)
    |> Enum.join("\n")
  end

  defp default_config do
    %{
      "version" => "1.0",
      "scan" => %{
        "directories" => [],
        "exclude" => ["**/node_modules", "**/.git", "**/vendor"]
      },
      "sync" => %{
        "auto_commit" => false
      }
    }
  end
end
