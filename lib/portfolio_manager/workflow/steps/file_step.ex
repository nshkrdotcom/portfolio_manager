defmodule PortfolioManager.Workflow.Steps.FileStep do
  @moduledoc """
  File operation steps.
  """

  alias PortfolioManager.Workflow.Context
  alias PortfolioManager.Adapters.LocalGit

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}

    case action do
      "read" -> read_files(inputs, context)
      "write" -> write_files(inputs, context)
      "find_git_repos" -> find_git_repos(inputs, context)
      _ -> {:error, "Unknown file action: #{action}"}
    end
  end

  defp read_files(inputs, context) do
    base = Map.get(inputs, "path") || Map.get(inputs, :path) || ""
    patterns = Map.get(inputs, "patterns") || Map.get(inputs, :patterns) || []
    max_size = Map.get(inputs, "max_size") || Map.get(inputs, :max_size) || 200_000

    files =
      case patterns do
        [] -> if File.regular?(base), do: [base], else: []
        _ -> Enum.flat_map(patterns, &Path.wildcard(Path.join(base, &1)))
      end

    contents =
      files
      |> Enum.flat_map(fn path ->
        case File.stat(path) do
          {:ok, stat} when stat.size <= max_size ->
            case File.read(path) do
              {:ok, content} -> [{path, content}]
              _ -> []
            end

          _ ->
            []
        end
      end)
      |> Map.new()

    {:ok, context, %{files: contents}}
  end

  defp write_files(inputs, context) do
    base = Map.get(inputs, "path") || Map.get(inputs, :path) || ""
    files = Map.get(inputs, "files") || Map.get(inputs, :files) || %{}

    results =
      Enum.map(files, fn {path, content} ->
        full_path =
          if base == "" do
            path
          else
            Path.join(base, path)
          end

        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, content)
        full_path
      end)

    {:ok, context, %{paths: results}}
  end

  defp find_git_repos(inputs, context) do
    dirs = Map.get(inputs, "directories") || Map.get(inputs, :directories) || []
    exclude = Map.get(inputs, "exclude") || Map.get(inputs, :exclude) || []

    repos =
      dirs
      |> Enum.flat_map(&LocalGit.discover_repos(&1, exclude: exclude))
      |> Enum.uniq()
      |> Enum.map(&%{path: &1})

    {:ok, context, %{repos: repos}}
  end
end
