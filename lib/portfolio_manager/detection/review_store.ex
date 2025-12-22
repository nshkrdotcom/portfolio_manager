defmodule PortfolioManager.Detection.ReviewStore do
  @moduledoc """
  Stores pending agentic detection items for human review.

  Review data is centralized under `.portfolio/reviews/pending.yml`
  within the portfolio repository.
  """

  @type item :: map()

  @spec list_pending(GenServer.server() | String.t()) :: {:ok, [item()]} | {:error, term()}
  def list_pending(portfolio_or_path) do
    with {:ok, path} <- resolve_portfolio_path(portfolio_or_path),
         {:ok, data} <- load_file(path) do
      {:ok, Map.get(data, "items", [])}
    end
  end

  @spec save_pending(GenServer.server() | String.t(), [item()]) :: :ok | {:error, term()}
  def save_pending(portfolio_or_path, items) when is_list(items) do
    with {:ok, path} <- resolve_portfolio_path(portfolio_or_path) do
      data = %{
        "schema_version" => 1,
        "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "items" => items
      }

      write_file(path, data)
    end
  end

  @spec append_pending(GenServer.server() | String.t(), [item()]) ::
          :ok | {:error, term()}
  def append_pending(portfolio_or_path, items) when is_list(items) do
    with {:ok, existing} <- list_pending(portfolio_or_path),
         :ok <- save_pending(portfolio_or_path, existing ++ items) do
      :ok
    end
  end

  @spec remove_pending(GenServer.server() | String.t(), [String.t()]) ::
          :ok | {:error, term()}
  def remove_pending(portfolio_or_path, ids) when is_list(ids) do
    with {:ok, existing} <- list_pending(portfolio_or_path) do
      remaining = Enum.reject(existing, fn item -> item["id"] in ids end)
      save_pending(portfolio_or_path, remaining)
    end
  end

  @spec pending_path(GenServer.server() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def pending_path(portfolio_or_path) do
    with {:ok, path} <- resolve_portfolio_path(portfolio_or_path) do
      {:ok, Path.join([path, ".portfolio", "reviews", "pending.yml"])}
    end
  end

  # Private helpers

  defp resolve_portfolio_path(path) when is_binary(path), do: {:ok, Path.expand(path)}

  defp resolve_portfolio_path(portfolio) do
    state = PortfolioManager.Portfolio.get_storage_state(portfolio)
    {:ok, state.path}
  end

  defp load_file(portfolio_path) do
    with {:ok, path} <- pending_path(portfolio_path) do
      case YamlElixir.read_from_file(path) do
        {:ok, data} -> {:ok, data}
        {:error, %YamlElixir.FileNotFoundError{}} -> {:ok, %{"items" => []}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp write_file(portfolio_path, data) do
    with {:ok, path} <- pending_path(portfolio_path),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      content = yaml_encode(data)
      File.write(path, content)
    end
  end

  defp yaml_encode(data) do
    "# AUTO-GENERATED - Do not edit manually\n" <> do_yaml_encode(data, 0)
  end

  defp do_yaml_encode(nil, _indent), do: "null\n"
  defp do_yaml_encode(true, _indent), do: "true\n"
  defp do_yaml_encode(false, _indent), do: "false\n"
  defp do_yaml_encode(v, _indent) when is_number(v), do: "#{v}\n"
  defp do_yaml_encode(v, _indent) when is_atom(v), do: "#{v}\n"

  defp do_yaml_encode(v, _indent) when is_binary(v) do
    if String.contains?(v, "\n") do
      "|\n  " <> String.replace(v, "\n", "\n  ") <> "\n"
    else
      safe_string(v) <> "\n"
    end
  end

  defp do_yaml_encode(list, indent) when is_list(list) do
    if list == [] do
      "[]\n"
    else
      spaces = String.duplicate(" ", indent)

      list
      |> Enum.map(fn item ->
        item_str = do_yaml_encode(item, indent + 2) |> String.trim_trailing("\n")

        if is_map(item) do
          [first | rest] = String.split(item_str, "\n")
          first_line = "#{spaces}- #{first}"

          rest_lines =
            Enum.map(rest, fn line ->
              "#{spaces}  #{line}"
            end)

          Enum.join([first_line | rest_lines], "\n")
        else
          "#{spaces}- #{item_str}"
        end
      end)
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    end
  end

  defp do_yaml_encode(map, indent) when is_map(map) do
    if map == %{} do
      "{}\n"
    else
      spaces = String.duplicate(" ", indent)

      map
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} ->
        key = to_string(k)

        cond do
          is_map(v) and map_size(v) > 0 ->
            "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

          is_list(v) and length(v) > 0 ->
            "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

          true ->
            "#{spaces}#{key}: #{do_yaml_encode(v, indent) |> String.trim_leading()}"
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
end
