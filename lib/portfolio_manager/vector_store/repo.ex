defmodule PortfolioManager.VectorStore.Repo do
  @moduledoc """
  Ecto repo for pgvector-backed document storage.
  """

  use Ecto.Repo,
    otp_app: :portfolio_manager,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    config =
      case socket_config_from_url(env_url()) do
        {:ok, socket_config} ->
          config
          |> Keyword.merge(socket_config)
          |> Keyword.delete(:url)

        :skip ->
          maybe_put_env_url(config)
      end

    config =
      case socket_config_from_env() do
        {:ok, socket_config} ->
          config
          |> Keyword.merge(socket_config)
          |> Keyword.delete(:url)

        :skip ->
          config
      end

    {:ok, config}
  end

  defp env_url do
    System.get_env("PORTFOLIO_DB_URL") || System.get_env("DATABASE_URL")
  end

  defp maybe_put_env_url(config) do
    case env_url() do
      nil -> config
      "" -> config
      url -> Keyword.put(config, :url, url)
    end
  end

  defp socket_config_from_url(nil), do: :skip
  defp socket_config_from_url(""), do: :skip

  defp socket_config_from_url(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    socket = Map.get(query, "host")

    if socket && String.starts_with?(socket, "/") do
      {username, password} = parse_userinfo(uri.userinfo)
      database = uri.path |> to_string() |> String.trim_leading("/")

      {:ok,
       [
         socket_dir: socket,
         database: database,
         username: username,
         password: password
       ]}
    else
      :skip
    end
  end

  defp socket_config_from_env do
    socket_dir = System.get_env("PORTFOLIO_DB_SOCKET") || System.get_env("PGHOST")
    database = System.get_env("PORTFOLIO_DB_NAME") || System.get_env("PGDATABASE")
    username = System.get_env("PORTFOLIO_DB_USER") || System.get_env("PGUSER")
    password = System.get_env("PORTFOLIO_DB_PASSWORD") || System.get_env("PGPASSWORD")

    if socket_dir && database do
      {:ok,
       [
         socket_dir: socket_dir,
         database: database,
         username: username,
         password: password
       ]}
    else
      :skip
    end
  end

  defp parse_userinfo(nil), do: {nil, nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {user, pass}
      [user] -> {user, nil}
      _ -> {nil, nil}
    end
  end
end
