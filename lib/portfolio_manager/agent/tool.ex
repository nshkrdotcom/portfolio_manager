defmodule PortfolioManager.Agent.Tool do
  @moduledoc """
  Tool definitions for the agent framework.

  Tools are functions that agents can call to gather information
  or perform actions. Each tool has:

  - A name (atom)
  - A description (for the LLM)
  - Parameters with types and requirements
  - An execute function

  ## Behaviour

  Tools can be implemented as modules using the Tool behaviour:

      defmodule MyTool do
        @behaviour PortfolioManager.Agent.Tool

        @impl true
        def name, do: :my_tool

        @impl true
        def description, do: "Does something useful"

        @impl true
        def parameters do
          [
            %{name: :query, type: :string, required: true, description: "The query"}
          ]
        end

        @impl true
        def execute(args, context) do
          # context includes: session_id, user_id, repo, router
          {:ok, "result"}
        end
      end

  ## Context

  When executing a tool, the context map contains:

    * `:session_id` - The current session ID
    * `:user_id` - The user ID (if available)
    * `:repo` - The repository path (if available)
    * `:router` - The Router module for LLM calls

  ## Helper Functions

      # Convert tool module to specification
      spec = Tool.to_spec(MyTool)

      # Validate arguments
      :ok = Tool.validate_args(MyTool, %{"query" => "test"})

      # Format tools for LLM prompt
      prompt = Tool.format_for_llm([MyTool])
  """

  @type parameter :: %{
          name: atom(),
          type: :string | :integer | :boolean | :list | :map,
          required: boolean(),
          description: String.t()
        }

  @type t :: %{
          name: atom(),
          description: String.t(),
          parameters: [parameter()],
          execute: (map() -> term()) | (map(), map() -> term())
        }

  @type context :: %{
          session_id: String.t() | nil,
          user_id: String.t() | nil,
          repo: String.t() | nil,
          router: module()
        }

  @doc "Returns the tool name as an atom."
  @callback name() :: atom()

  @doc "Returns a description of what the tool does."
  @callback description() :: String.t()

  @doc "Returns the list of parameters the tool accepts."
  @callback parameters() :: [parameter()]

  @doc "Executes the tool with the given arguments and context."
  @callback execute(args :: map(), context :: context()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  List all available tools (built-in map-based tools).
  """
  @spec list_all() :: [t()]
  def list_all do
    [
      search_code_tool(),
      read_file_tool(),
      list_files_tool(),
      get_graph_context_tool()
    ]
  end

  @doc """
  Convert a tool behaviour module to a specification map.
  """
  @spec to_spec(module()) :: t()
  def to_spec(module) do
    %{
      name: module.name(),
      description: module.description(),
      parameters: module.parameters(),
      execute: fn args -> module.execute(args, default_context()) end
    }
  end

  @doc """
  Convert a tool behaviour module to a specification map with context.
  """
  @spec to_spec(module(), context()) :: t()
  def to_spec(module, context) do
    %{
      name: module.name(),
      description: module.description(),
      parameters: module.parameters(),
      execute: fn args -> module.execute(args, context) end
    }
  end

  @doc """
  Validate arguments against a tool's parameter definitions.

  Returns `:ok` if all required parameters are present and types match,
  or `{:error, reasons}` with a list of validation errors.
  """
  @spec validate_args(module() | t(), map()) :: :ok | {:error, [String.t()]}
  def validate_args(module, args) when is_atom(module) do
    validate_args_against_params(module.parameters(), args)
  end

  def validate_args(%{parameters: params}, args) do
    validate_args_against_params(params, args)
  end

  defp validate_args_against_params(params, args) do
    errors =
      params
      |> Enum.flat_map(fn param ->
        validate_param(param, args)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_param(param, args) do
    name = param.name
    name_str = Atom.to_string(name)
    value = Map.get(args, name) || Map.get(args, name_str)

    cond do
      param.required and is_nil(value) ->
        ["Missing required parameter: #{name}"]

      is_nil(value) ->
        []

      not type_matches?(param.type, value) ->
        ["Parameter #{name} expected #{param.type}, got #{inspect(value)}"]

      true ->
        []
    end
  end

  defp type_matches?(:string, value), do: is_binary(value)
  defp type_matches?(:integer, value), do: is_integer(value)
  defp type_matches?(:boolean, value), do: is_boolean(value)
  defp type_matches?(:list, value), do: is_list(value)
  defp type_matches?(:map, value), do: is_map(value)
  defp type_matches?(_, _), do: true

  @doc """
  Format tools for inclusion in LLM prompts (OpenAI function format).
  """
  @spec format_for_llm([module() | t()]) :: String.t()
  def format_for_llm(tools) do
    Enum.map_join(tools, "\n\n", &format_tool_for_llm/1)
  end

  defp format_tool_for_llm(module) when is_atom(module) do
    format_tool_for_llm(to_spec(module))
  end

  defp format_tool_for_llm(%{name: name, description: description, parameters: params}) do
    param_str = format_parameters_for_llm(params)

    """
    Function: #{name}
    Description: #{description}
    Parameters:
    #{param_str}
    """
  end

  defp format_parameters_for_llm(params) do
    Enum.map_join(params, "\n", fn p ->
      required = if p.required, do: "(required)", else: "(optional)"
      "  - #{p.name}: #{p.type} #{required} - #{p.description}"
    end)
  end

  @doc """
  Create a default context for tool execution.
  """
  @spec default_context() :: context()
  def default_context do
    %{
      session_id: nil,
      user_id: nil,
      repo: nil,
      router: PortfolioManager.Router
    }
  end

  @doc """
  Create a context from a session.
  """
  @spec context_from_session(PortfolioManager.Agent.Session.t()) :: context()
  def context_from_session(session) do
    %{
      session_id: session.id,
      user_id: Map.get(session.context, :user_id) || Map.get(session.metadata, :user_id),
      repo: Map.get(session.context, :repo),
      router: PortfolioManager.Router
    }
  end

  # Built-in tools

  defp search_code_tool do
    %{
      name: :search_code,
      description: "Search the codebase for relevant code using semantic similarity",
      parameters: [
        %{
          name: :query,
          type: :string,
          required: true,
          description: "Search query"
        },
        %{
          name: :limit,
          type: :integer,
          required: false,
          description: "Maximum results (default 5)"
        }
      ],
      execute: fn args ->
        query = args["query"] || args[:query]
        limit = args["limit"] || args[:limit] || 5
        PortfolioManager.RAG.search(query, limit: limit)
      end
    }
  end

  defp read_file_tool do
    %{
      name: :read_file,
      description: "Read contents of a file from the repository",
      parameters: [
        %{
          name: :path,
          type: :string,
          required: true,
          description: "File path to read"
        },
        %{
          name: :start_line,
          type: :integer,
          required: false,
          description: "Starting line number"
        },
        %{
          name: :end_line,
          type: :integer,
          required: false,
          description: "Ending line number"
        }
      ],
      execute: fn args ->
        path = args["path"] || args[:path]
        start_line = args["start_line"] || args[:start_line]
        end_line = args["end_line"] || args[:end_line]

        case File.read(path) do
          {:ok, content} ->
            content = maybe_slice_lines(content, start_line, end_line)
            {:ok, content}

          error ->
            error
        end
      end
    }
  end

  defp list_files_tool do
    %{
      name: :list_files,
      description: "List files in a directory matching a pattern",
      parameters: [
        %{
          name: :path,
          type: :string,
          required: true,
          description: "Directory path"
        },
        %{
          name: :pattern,
          type: :string,
          required: false,
          description: "Glob pattern (default: *)"
        }
      ],
      execute: fn args ->
        path = args["path"] || args[:path]
        pattern = args["pattern"] || args[:pattern] || "*"

        full_pattern = Path.join(path, pattern)
        files = Path.wildcard(full_pattern)
        {:ok, files}
      end
    }
  end

  defp get_graph_context_tool do
    %{
      name: :get_graph_context,
      description: "Get related entities from the knowledge graph",
      parameters: [
        %{
          name: :entity,
          type: :string,
          required: true,
          description: "Entity name to find context for"
        },
        %{
          name: :depth,
          type: :integer,
          required: false,
          description: "Traversal depth (default 2)"
        }
      ],
      execute: fn args ->
        entity = args["entity"] || args[:entity]
        depth = args["depth"] || args[:depth] || 2

        # Use default graph
        PortfolioManager.Graph.neighbors("default", entity, depth: depth)
      end
    }
  end

  defp maybe_slice_lines(content, nil, nil), do: content

  defp maybe_slice_lines(content, start_line, end_line) do
    lines = String.split(content, "\n")

    start_idx = (start_line || 1) - 1
    end_idx = (end_line || length(lines)) - 1

    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.join("\n")
  end
end
