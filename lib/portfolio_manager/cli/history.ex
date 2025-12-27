defmodule PortfolioManager.CLI.History do
  @moduledoc """
  Utilities for REPL history persistence and expansion.
  """

  @default_limit 20

  @spec load(String.t()) :: [String.t()]
  def load(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 == ""))

      {:error, _} ->
        []
    end
  end

  @spec append([String.t()], String.t(), String.t()) :: [String.t()]
  def append(history, path, command) when is_binary(command) do
    trimmed = String.trim(command)

    if trimmed == "" do
      history
    else
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, trimmed <> "\n", [:append]) do
        history ++ [trimmed]
      else
        {:error, _} -> history
      end
    end
  end

  @spec expand([String.t()], String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def expand(history, "!" <> rest) do
    case Integer.parse(rest) do
      {index, ""} when index > 0 ->
        case Enum.at(history, index - 1) do
          nil -> {:error, "No history entry #{index}."}
          command -> {:ok, command}
        end

      _ ->
        {:error, "Invalid history reference."}
    end
  end

  def expand(_history, input), do: {:ok, input}

  @spec recent([String.t()], pos_integer() | nil) :: [{pos_integer(), String.t()}]
  def recent(history, count) do
    limit =
      case count do
        nil -> @default_limit
        _ -> count
      end

    history
    |> Enum.with_index(1)
    |> Enum.drop(max(length(history) - limit, 0))
    |> Enum.map(fn {command, index} -> {index, command} end)
  end

  @spec parse_count(String.t()) :: pos_integer() | nil
  def parse_count(rest) do
    case Integer.parse(String.trim(rest)) do
      {count, ""} when count > 0 -> count
      _ -> nil
    end
  end
end
