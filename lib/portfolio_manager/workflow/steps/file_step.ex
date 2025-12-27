defmodule PortfolioManager.Workflow.Steps.FileStep do
  @moduledoc """
  File operation steps.
  """

  alias PortfolioManager.Adapters.LocalGit
  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    dispatch_action(action, inputs, context)
  end

  defp dispatch_action("read", inputs, context), do: read_files(inputs, context)
  defp dispatch_action("write", inputs, context), do: write_files(inputs, context)
  defp dispatch_action("find_git_repos", inputs, context), do: find_git_repos(inputs, context)
  defp dispatch_action(action, _inputs, _context), do: {:error, "Unknown file action: #{action}"}

  defp read_files(inputs, context) do
    base = get_input(inputs, "path") || ""
    patterns = get_input(inputs, "patterns") || []
    max_size = get_input(inputs, "max_size") || 200_000

    files = resolve_files(base, patterns)

    contents =
      files
      |> Enum.flat_map(&read_file_if_valid(&1, max_size))
      |> Map.new()

    {:ok, context, %{files: contents}}
  end

  defp resolve_files(base, []), do: if(File.regular?(base), do: [base], else: [])

  defp resolve_files(base, patterns),
    do: Enum.flat_map(patterns, &Path.wildcard(Path.join(base, &1)))

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))

  defp read_file_if_valid(path, max_size) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.size <= max_size,
         {:ok, content} <- File.read(path) do
      [{path, content}]
    else
      _ -> []
    end
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
