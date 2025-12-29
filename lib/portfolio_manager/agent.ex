defmodule PortfolioManager.Agent do
  @moduledoc """
  Tool-using agent for complex code analysis tasks.

  The agent can iteratively use tools to gather information
  and solve problems that require multiple steps.

  ## Session-based API

  The new session-based API maintains conversation history:

      session = Session.new(context: %{repo: "my_app"})

      # Simple LLM call without tools
      {:ok, response, session} = Agent.process(session, "Explain this code")

      # Multi-turn with tools
      {:ok, response, session} = Agent.process_with_tools(
        session,
        "Find and explain the main function",
        [:search_code, :read_file]
      )

  ## Legacy API

  The `run/2` function is still available for simple one-shot tasks:

      {:ok, response} = Agent.run("Analyze this codebase",
        tools: [:search_code, :read_file]
      )
  """

  # Note: Implements the Agent port pattern but uses Session struct instead of plain maps.
  # @behaviour PortfolioCore.Ports.Agent

  require Logger

  alias PortfolioManager.Agent.{Session, Tool}
  alias PortfolioManager.Router

  @max_iterations 10
  @default_tools [:search_code, :read_file, :list_files, :get_graph_context]

  defstruct [:session_id, :tools, :memory, :iteration]

  # Session-based API

  @doc """
  Process input within a session context without tools.

  Maintains conversation history across calls.

  ## Parameters

    * `session` - Current session state
    * `input` - User input to process
    * `opts` - Processing options

  ## Returns

    * `{:ok, response, updated_session}` on success
    * `{:error, reason}` on failure
  """

  @spec process(Session.t(), String.t(), keyword()) ::
          {:ok, String.t(), Session.t()} | {:error, term()}
  def process(session, input, opts \\ []) do
    session = Session.add_message(session, %{role: :user, content: input})
    messages = Session.to_llm_messages(session)

    case Router.complete(messages, opts) do
      {:ok, %{content: response}} ->
        session = Session.add_message(session, %{role: :assistant, content: response})
        {:ok, response, session}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Process input with tool execution within a session.

  Runs the tool execution loop until completion or max iterations.

  ## Parameters

    * `session` - Current session state
    * `input` - User input to process
    * `tools` - List of tool names to make available
    * `opts` - Processing options:
      * `:max_iterations` - Maximum tool execution iterations (default: 10)

  ## Returns

    * `{:ok, response, updated_session}` on success
    * `{:error, reason}` on failure
  """

  @spec process_with_tools(Session.t(), String.t(), [atom()], keyword()) ::
          {:ok, String.t(), Session.t()} | {:error, term()}
  def process_with_tools(session, input, tools, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)
    loaded_tools = load_tools(tools)

    session = Session.add_message(session, %{role: :user, content: input})

    agent = %__MODULE__{
      session_id: session.id,
      tools: loaded_tools,
      memory: [],
      iteration: 0
    }

    execute_session_loop(agent, session, input, max_iter, opts)
  end

  @doc """
  Add context to a session that persists across iterations.
  """
  @spec with_context(Session.t(), atom(), term()) :: Session.t()
  def with_context(session, key, value) do
    Session.with_context(session, key, value)
  end

  # Legacy API

  @doc """
  Run an agent task.

  ## Options

    * `:tools` - List of tool names to make available (default: all)
    * `:max_iterations` - Maximum number of tool call iterations (default: 10)
  """

  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(task, opts \\ []) do
    tools = Keyword.get(opts, :tools, @default_tools)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    session = Session.new()
    loaded_tools = load_tools(tools)

    agent = %__MODULE__{
      session_id: session.id,
      tools: loaded_tools,
      memory: [],
      iteration: 0
    }

    execute_loop(agent, task, max_iter)
  end

  @doc """
  List available tool specifications.
  """

  @spec available_tools() :: [map()]
  def available_tools do
    Tool.list_all()
  end

  @doc """
  Execute a tool call.
  """

  @spec execute_tool(map()) :: {:ok, map()} | {:error, term()}
  def execute_tool(%{tool: tool_name, arguments: args}) do
    tools = load_tools([tool_name])

    case Map.get(tools, tool_name) do
      nil ->
        {:error, {:unknown_tool, tool_name}}

      tool ->
        result = tool.execute.(args)
        success = match?({:ok, _}, result)

        {:ok,
         %{
           id: generate_id(),
           tool: tool_name,
           result: result,
           success: success
         }}
    end
  end

  @doc """
  Return the maximum iterations allowed.
  """

  @spec max_iterations() :: pos_integer()
  def max_iterations, do: @max_iterations

  # Session-based execution loop

  defp execute_session_loop(agent, session, _task, max_iter, _opts)
       when agent.iteration >= max_iter do
    Logger.warning("Agent reached max iterations (#{max_iter})")
    synthesize_session_answer(agent, session)
  end

  defp execute_session_loop(agent, session, task, max_iter, opts) do
    prompt = build_session_prompt(agent, session, task)
    messages = [%{role: :user, content: prompt}]

    case Router.complete(messages, opts) do
      {:ok, %{content: response}} ->
        case parse_tool_call(response) do
          {:tool_call, tool_name, args} ->
            {result, session} = execute_and_record_tool(agent, session, tool_name, args)
            new_agent = update_memory(agent, tool_name, args, result)
            execute_session_loop(new_agent, session, task, max_iter, opts)

          {:final_answer, answer} ->
            session = Session.add_message(session, %{role: :assistant, content: answer})
            {:ok, answer, session}

          :continue ->
            execute_session_loop(
              %{agent | iteration: agent.iteration + 1},
              session,
              task,
              max_iter,
              opts
            )
        end

      {:error, reason} ->
        Logger.error("Agent LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_session_prompt(agent, session, task) do
    tool_descriptions = format_tools(agent.tools)
    memory = format_memory(agent.memory)

    context_info =
      if map_size(session.context) > 0 do
        "Session context: #{inspect(session.context)}\n\n"
      else
        ""
      end

    """
    You are a code analysis agent. Your task is:

    #{task}

    #{context_info}Available tools:
    #{tool_descriptions}

    Conversation history:
    #{memory}

    Instructions:
    - Use tools to gather information needed to complete the task
    - Call one tool at a time using JSON: {"tool": "name", "args": {...}}
    - When ready with final answer: {"answer": "your complete answer"}
    - Be thorough but efficient

    Your response:
    """
  end

  defp execute_and_record_tool(agent, session, tool_name, args) do
    result = execute_tool_internal(agent, tool_name, args)
    session = Session.add_tool_result(session, tool_name, result)
    {result, session}
  end

  defp synthesize_session_answer(agent, session) do
    if Enum.empty?(agent.memory) do
      {:error, :no_progress}
    else
      summary = format_memory(agent.memory)
      answer = "Based on gathered information:\n\n#{summary}"
      session = Session.add_message(session, %{role: :assistant, content: answer})
      {:ok, answer, session}
    end
  end

  # Legacy execution loop

  defp execute_loop(agent, _task, max_iter) when agent.iteration >= max_iter do
    Logger.warning("Agent reached max iterations (#{max_iter})")
    synthesize_answer(agent)
  end

  defp execute_loop(agent, task, max_iter) do
    prompt = build_agent_prompt(agent, task)

    case Router.complete([%{role: :user, content: prompt}]) do
      {:ok, %{content: response}} ->
        case parse_tool_call(response) do
          {:tool_call, tool_name, args} ->
            result = execute_tool_internal(agent, tool_name, args)
            new_agent = update_memory(agent, tool_name, args, result)
            execute_loop(new_agent, task, max_iter)

          {:final_answer, answer} ->
            {:ok, answer}

          :continue ->
            execute_loop(%{agent | iteration: agent.iteration + 1}, task, max_iter)
        end

      {:error, reason} ->
        Logger.error("Agent LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_agent_prompt(agent, task) do
    tool_descriptions = format_tools(agent.tools)
    memory = format_memory(agent.memory)

    """
    You are a code analysis agent. Your task is:

    #{task}

    Available tools:
    #{tool_descriptions}

    Conversation history:
    #{memory}

    Instructions:
    - Use tools to gather information needed to complete the task
    - Call one tool at a time using JSON: {"tool": "name", "args": {...}}
    - When ready with final answer: {"answer": "your complete answer"}
    - Be thorough but efficient

    Your response:
    """
  end

  defp format_tools(tools) do
    Enum.map_join(tools, "\n", fn {name, tool} ->
      params = format_parameters(tool.parameters)
      "- #{name}(#{params}): #{tool.description}"
    end)
  end

  defp format_parameters(parameters) do
    Enum.map_join(parameters, ", ", &format_parameter/1)
  end

  defp format_parameter(p) do
    required_suffix = if p.required, do: " (required)", else: ""
    "#{p.name}: #{p.type}#{required_suffix}"
  end

  defp format_memory([]), do: "No previous actions."

  defp format_memory(memory) do
    Enum.map_join(memory, "\n", fn {tool, args, result} ->
      result_str = inspect(result) |> String.slice(0, 500)
      "Called #{tool}(#{inspect(args)})\nResult: #{result_str}"
    end)
  end

  @doc """
  Parse a response for tool calls or final answers.

  Handles both simple and nested JSON structures.
  Supports both "tool"/"args" and "name"/"arguments" formats.
  """
  @spec parse_tool_call(String.t()) ::
          {:tool_call, atom(), map()} | {:final_answer, String.t()} | :continue
  def parse_tool_call(content) do
    # Try to extract JSON - handle nested objects
    case extract_json_object(content) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, %{"tool" => name, "args" => args}} when is_map(args) ->
            {:tool_call, String.to_atom(name), args}

          {:ok, %{"name" => name, "arguments" => args}} when is_map(args) ->
            {:tool_call, String.to_atom(name), args}

          {:ok, %{"answer" => answer}} ->
            {:final_answer, answer}

          _ ->
            check_plain_text_answer(content)
        end

      :error ->
        check_plain_text_answer(content)
    end
  end

  # Extract JSON object handling nested braces
  defp extract_json_object(content) do
    case find_json_start(content) do
      nil ->
        :error

      start_idx ->
        extract_balanced_braces(content, start_idx)
    end
  end

  defp find_json_start(content) do
    case :binary.match(content, "{") do
      {idx, _} -> idx
      :nomatch -> nil
    end
  end

  defp extract_balanced_braces(content, start_idx) do
    chars = String.slice(content, start_idx, String.length(content))
    extract_balanced(chars, 0, [], false)
  end

  defp extract_balanced("", _depth, _acc, _in_string), do: :error

  defp extract_balanced(<<"\\"::utf8, c::utf8, rest::binary>>, depth, acc, true) do
    extract_balanced(rest, depth, [c, ?\\ | acc], true)
  end

  defp extract_balanced(<<"\"", rest::binary>>, depth, acc, in_string) do
    extract_balanced(rest, depth, [?" | acc], not in_string)
  end

  defp extract_balanced(<<"{", rest::binary>>, depth, acc, false) do
    extract_balanced(rest, depth + 1, [?{ | acc], false)
  end

  defp extract_balanced(<<"}", _rest::binary>>, 1, acc, false) do
    json = [?} | acc] |> Enum.reverse() |> List.to_string()
    {:ok, json}
  end

  defp extract_balanced(<<"}", rest::binary>>, depth, acc, false) when depth > 1 do
    extract_balanced(rest, depth - 1, [?} | acc], false)
  end

  defp extract_balanced(<<c::utf8, rest::binary>>, depth, acc, in_string) do
    extract_balanced(rest, depth, [c | acc], in_string)
  end

  defp check_plain_text_answer(content) do
    if String.length(content) > 100 and not String.contains?(content, "{") do
      {:final_answer, content}
    else
      :continue
    end
  end

  defp execute_tool_internal(agent, tool_name, args) do
    case Map.get(agent.tools, tool_name) do
      nil ->
        "Unknown tool: #{tool_name}"

      tool ->
        case tool.execute.(args) do
          {:ok, result} -> result
          {:error, reason} -> "Error: #{inspect(reason)}"
          result -> result
        end
    end
  end

  defp update_memory(agent, tool_name, args, result) do
    %{
      agent
      | memory: agent.memory ++ [{tool_name, args, result}],
        iteration: agent.iteration + 1
    }
  end

  defp synthesize_answer(agent) do
    if Enum.empty?(agent.memory) do
      {:error, :no_progress}
    else
      summary = format_memory(agent.memory)
      {:ok, "Based on gathered information:\n\n#{summary}"}
    end
  end

  defp load_tools(tool_names) do
    Tool.list_all()
    |> Enum.filter(fn t -> t.name in tool_names end)
    |> Map.new(fn t -> {t.name, t} end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
