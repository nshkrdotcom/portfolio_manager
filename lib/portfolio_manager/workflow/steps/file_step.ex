defmodule PortfolioManager.Workflow.Steps.FileStep do
  @moduledoc """
  File operation step.

  Supports reading, writing, and checking files.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes a file step.

  ## Config Options

    * `action` - File action (read, write, exists, delete, copy)
    * `path` - File path
    * `content` - Content to write (for write action)
    * `dest` - Destination path (for copy action)
    * `capture` - Variable name to capture content into (for read action)

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    config = step.config

    action = Map.get(config, "action", "exists")
    path = Context.interpolate(context, Map.get(config, "path", ""))

    if path == "" do
      {:error, "No path specified"}
    else
      execute_action(action, path, config, context, step.name)
    end
  end

  defp execute_action("read", path, config, context, step_name) do
    capture = Map.get(config, "capture")

    case File.read(path) do
      {:ok, content} ->
        result = %{path: path, content: content, size: byte_size(content)}
        new_ctx = Context.set_result(context, step_name, result)

        new_ctx =
          if capture do
            Context.set_var(new_ctx, capture, content)
          else
            new_ctx
          end

        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, "Failed to read #{path}: #{inspect(reason)}"}
    end
  end

  defp execute_action("write", path, config, context, step_name) do
    content = Context.interpolate(context, Map.get(config, "content", ""))

    # Ensure directory exists
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(path, content) do
          :ok ->
            result = %{path: path, bytes_written: byte_size(content)}
            new_ctx = Context.set_result(context, step_name, result)
            {:ok, new_ctx, result}

          {:error, reason} ->
            {:error, "Failed to write #{path}: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to create directory #{dir}: #{inspect(reason)}"}
    end
  end

  defp execute_action("exists", path, _config, context, step_name) do
    exists = File.exists?(path)
    result = %{path: path, exists: exists}
    new_ctx = Context.set_result(context, step_name, result)
    {:ok, new_ctx, result}
  end

  defp execute_action("delete", path, _config, context, step_name) do
    if File.exists?(path) do
      case File.rm(path) do
        :ok ->
          result = %{path: path, deleted: true}
          new_ctx = Context.set_result(context, step_name, result)
          {:ok, new_ctx, result}

        {:error, reason} ->
          {:error, "Failed to delete #{path}: #{inspect(reason)}"}
      end
    else
      result = %{path: path, deleted: false, reason: "not found"}
      new_ctx = Context.set_result(context, step_name, result)
      {:ok, new_ctx, result}
    end
  end

  defp execute_action("copy", path, config, context, step_name) do
    dest = Context.interpolate(context, Map.get(config, "dest", ""))

    if dest == "" do
      {:error, "No destination path specified for copy"}
    else
      # Ensure destination directory exists
      dir = Path.dirname(dest)

      case File.mkdir_p(dir) do
        :ok ->
          case File.copy(path, dest) do
            {:ok, bytes} ->
              result = %{source: path, dest: dest, bytes_copied: bytes}
              new_ctx = Context.set_result(context, step_name, result)
              {:ok, new_ctx, result}

            {:error, reason} ->
              {:error, "Failed to copy #{path} to #{dest}: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to create directory #{dir}: #{inspect(reason)}"}
      end
    end
  end

  defp execute_action(action, _path, _config, _context, _step_name) do
    {:error, "Unknown file action: #{action}"}
  end
end
