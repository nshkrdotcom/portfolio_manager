defmodule Mix.Tasks.Portfolio.Config do
  @moduledoc """
  Manage portfolio configuration.

  ## Usage

      mix portfolio.config <subcommand> [options]

  ## Subcommands

    * `show` - Show current configuration
    * `get <key>` - Get a specific configuration value
    * `set <key> <value>` - Set a configuration value
    * `list-dirs` - List scan directories
    * `add-dir <path>` - Add a scan directory
    * `remove-dir <path>` - Remove a scan directory

  ## Examples

      mix portfolio.config show
      mix portfolio.config get scan.directories
      mix portfolio.config set sync.auto_commit true
      mix portfolio.config add-dir ~/projects
      mix portfolio.config list-dirs

  """
  @shortdoc "Manage portfolio configuration"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      dispatch_command(args, opts)
    end
  end

  defp dispatch_command(["show"], opts), do: show_config(opts)
  defp dispatch_command(["get", key], opts), do: get_config(key, opts)
  defp dispatch_command(["set", key, value], opts), do: set_config(key, value, opts)
  defp dispatch_command(["list-dirs"], opts), do: list_dirs(opts)
  defp dispatch_command(["add-dir", path], opts), do: add_dir(path, opts)
  defp dispatch_command(["remove-dir", path], opts), do: remove_dir(path, opts)
  defp dispatch_command([], opts), do: show_config(opts)

  defp dispatch_command(_, _opts) do
    show_help()
    Exit.halt(:invalid_args)
  end

  defp show_config(opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        if opts[:json] do
          Mix.shell().info(Jason.encode!(config, pretty: true))
        else
          Mix.shell().info("""
          #{IO.ANSI.cyan()}Portfolio Configuration#{IO.ANSI.reset()}
          Path: #{portfolio_path}

          #{format_config(config, 0)}
          """)
        end

      {:error, _} ->
        Mix.shell().error("Configuration file not found at #{config_path}")
        Exit.halt(:config)
    end
  end

  defp get_config(key, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        value = get_nested(config, String.split(key, "."))

        if opts[:json] do
          Mix.shell().info(Jason.encode!(%{key: key, value: value}, pretty: true))
        else
          Mix.shell().info("#{key}: #{inspect(value)}")
        end

      {:error, _} ->
        Mix.shell().error("Configuration file not found")
        Exit.halt(:config)
    end
  end

  defp set_config(key, value, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        parsed_value = parse_value(value)
        keys = String.split(key, ".")
        updated = set_nested(config, keys, parsed_value)

        case write_yaml(config_path, updated) do
          :ok ->
            Mix.shell().info(
              "#{IO.ANSI.green()}Set #{key} = #{inspect(parsed_value)}#{IO.ANSI.reset()}"
            )

          {:error, reason} ->
            Mix.shell().error("Failed to save configuration: #{inspect(reason)}")
        end

      {:error, _} ->
        Mix.shell().error("Configuration file not found")
        Exit.halt(:config)
    end
  end

  defp list_dirs(opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        dirs = get_in(config, ["scan", "directories"]) || []
        output_dirs(dirs, opts)

      {:error, _} ->
        Mix.shell().error("Configuration file not found")
        Exit.halt(:config)
    end
  end

  defp output_dirs(dirs, opts) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(dirs, pretty: true))
    else
      if Enum.empty?(dirs) do
        Mix.shell().info("No scan directories configured.")
      else
        Mix.shell().info("""
        #{IO.ANSI.cyan()}Scan Directories#{IO.ANSI.reset()}

        #{Enum.map_join(dirs, "\n", &("  * " <> &1))}
        """)
      end
    end
  end

  defp add_dir(path, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")
    expanded = Path.expand(path)

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        do_add_dir(config, config_path, expanded)

      {:error, _} ->
        Mix.shell().error("Configuration file not found")
        Exit.halt(:config)
    end
  end

  defp do_add_dir(config, config_path, expanded) do
    dirs = get_in(config, ["scan", "directories"]) || []

    if expanded in dirs do
      Mix.shell().info("Directory already in scan list: #{expanded}")
    else
      updated = put_in(config, ["scan", "directories"], dirs ++ [expanded])
      handle_yaml_write(config_path, updated, "Added #{expanded} to scan directories")
    end
  end

  defp handle_yaml_write(config_path, updated, success_message) do
    case write_yaml(config_path, updated) do
      :ok ->
        Mix.shell().info("#{IO.ANSI.green()}#{success_message}#{IO.ANSI.reset()}")

      {:error, reason} ->
        Mix.shell().error("Failed to save configuration: #{inspect(reason)}")
    end
  end

  defp remove_dir(path, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
    config_path = Path.join(portfolio_path, "config.yml")
    expanded = Path.expand(path)

    case YamlElixir.read_from_file(config_path) do
      {:ok, config} ->
        do_remove_dir(config, config_path, expanded)

      {:error, _} ->
        Mix.shell().error("Configuration file not found")
    end
  end

  defp do_remove_dir(config, config_path, expanded) do
    dirs = get_in(config, ["scan", "directories"]) || []

    if expanded in dirs do
      updated = put_in(config, ["scan", "directories"], Enum.reject(dirs, &(&1 == expanded)))
      handle_yaml_write(config_path, updated, "Removed #{expanded} from scan directories")
    else
      Mix.shell().info("Directory not in scan list: #{expanded}")
    end
  end

  defp get_nested(map, [key]) do
    Map.get(map, key)
  end

  defp get_nested(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> nil
      nested -> get_nested(nested, rest)
    end
  end

  defp get_nested(_, _), do: nil

  defp set_nested(map, [key], value) when is_map(map) do
    Map.put(map, key, value)
  end

  defp set_nested(map, [key | rest], value) when is_map(map) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, set_nested(nested, rest, value))
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp format_config(config, indent) when is_map(config) do
    spaces = String.duplicate("  ", indent)

    config
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} ->
      if is_map(v) or is_list(v) do
        "#{spaces}#{k}:\n#{format_config(v, indent + 1)}"
      else
        "#{spaces}#{k}: #{inspect(v)}"
      end
    end)
  end

  defp format_config(list, indent) when is_list(list) do
    spaces = String.duplicate("  ", indent)
    Enum.map_join(list, "\n", &"#{spaces}- #{&1}")
  end

  defp format_config(value, _indent), do: inspect(value)

  defp write_yaml(path, data) do
    yaml = yaml_encode(data)
    File.write(path, yaml)
  end

  defp yaml_encode(data), do: do_yaml_encode(data, 0)

  defp do_yaml_encode(nil, _indent), do: "null\n"
  defp do_yaml_encode(true, _indent), do: "true\n"
  defp do_yaml_encode(false, _indent), do: "false\n"
  defp do_yaml_encode(v, _indent) when is_number(v), do: "#{v}\n"
  defp do_yaml_encode(v, _indent) when is_binary(v), do: "#{v}\n"

  defp do_yaml_encode(list, indent) when is_list(list) do
    if list == [] do
      "[]\n"
    else
      spaces = String.duplicate("  ", indent)

      list
      |> Enum.map_join("", fn item ->
        "#{spaces}- #{String.trim(do_yaml_encode(item, indent))}\n"
      end)
    end
  end

  defp do_yaml_encode(map, indent) when is_map(map) do
    if map == %{} do
      "{}\n"
    else
      spaces = String.duplicate("  ", indent)

      map
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("", fn {k, v} ->
        encode_map_entry(k, v, spaces, indent)
      end)
    end
  end

  defp encode_map_entry(k, v, spaces, indent) do
    key = to_string(k)

    cond do
      is_map(v) and map_size(v) > 0 ->
        "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 1)}"

      is_list(v) and v != [] ->
        "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 1)}"

      true ->
        "#{spaces}#{key}: #{String.trim(do_yaml_encode(v, indent))}\n"
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.config <subcommand> [options]

    Manage portfolio configuration.

    Subcommands:
      show                  Show current configuration
      get <key>             Get a specific configuration value
      set <key> <value>     Set a configuration value
      list-dirs             List scan directories
      add-dir <path>        Add a scan directory
      remove-dir <path>     Remove a scan directory

    Options:
      --json                Output as JSON
      --help                Show this help message

    Examples:
      mix portfolio.config show
      mix portfolio.config get scan.directories
      mix portfolio.config set sync.auto_commit true
      mix portfolio.config add-dir ~/projects
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
