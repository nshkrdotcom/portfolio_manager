defmodule PortfolioManager.AgentTest do
  use PortfolioManager.SupertesterCase, async: false

  import ExUnit.CaptureLog

  import Mox

  alias PortfolioManager.Agent
  alias PortfolioManager.Agent.Session
  alias PortfolioManager.Router

  setup :verify_on_exit!

  setup do
    # Stop any existing router started by the application
    case Process.whereis(Router) do
      nil -> :ok
      pid -> safe_stop(pid)
    end

    # Start the router with a mock LLM provider
    {:ok, router_pid} =
      Router.start_link(
        strategy: :fallback,
        providers: [
          %{
            name: :test_llm,
            module: PortfolioManager.Mocks.LLM,
            config: %{},
            capabilities: [:generation, :reasoning],
            priority: 1
          }
        ],
        health_check_interval: 0
      )

    on_exit(fn ->
      # Avoid race if the router already stopped.
      _ = Process.exit(router_pid, :normal)
    end)

    :ok
  end

  describe "process/3" do
    test "processes input without tools" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 1
        assert hd(messages).role == :user
        {:ok, %{content: "Here is the explanation."}}
      end)

      session = Session.new()
      assert {:ok, response, updated_session} = Agent.process(session, "Explain this code")

      assert response == "Here is the explanation."
      assert Session.message_count(updated_session) == 2
    end

    test "maintains conversation history" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 1
        {:ok, %{content: "First response"}}
      end)
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 3
        {:ok, %{content: "Second response"}}
      end)

      session = Session.new()
      {:ok, _, session} = Agent.process(session, "First question")
      {:ok, response, session} = Agent.process(session, "Second question")

      assert response == "Second response"
      assert Session.message_count(session) == 4
    end

    test "returns error when LLM fails" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:error, :rate_limited}
      end)

      session = Session.new()
      assert {:error, :rate_limited} = Agent.process(session, "Test")
    end
  end

  describe "process_with_tools/4" do
    test "executes tool calls and returns answer" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"tool": "list_files", "args": {"path": "/tmp"}})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"answer": "Found the files."})}}
      end)

      session = Session.new()

      assert {:ok, answer, updated_session} =
               Agent.process_with_tools(session, "List files", [:list_files])

      assert answer == "Found the files."
      assert [_ | _] = updated_session.tool_results
    end

    test "respects max_iterations" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, 2, fn _messages, _opts ->
        {:ok, %{content: "Still thinking..."}}
      end)

      session = Session.new()

      capture_log(fn ->
        assert {:error, :no_progress} =
                 Agent.process_with_tools(session, "Task", [:search_code], max_iterations: 2)
      end)
    end

    test "includes session context in prompts" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        [msg] = messages
        assert String.contains?(msg.content, "my_repo")
        {:ok, %{content: ~s({"answer": "Done"})}}
      end)

      session = Session.new(context: %{repo: "my_repo"})
      {:ok, _, _} = Agent.process_with_tools(session, "Task", [])
    end
  end

  describe "with_context/3" do
    test "adds context to session" do
      session = Session.new()
      session = Agent.with_context(session, :repo, "my_app")

      assert session.context.repo == "my_app"
    end
  end

  describe "run/2" do
    test "executes task and returns answer" do
      # Mock the LLM to return a final answer
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"answer": "The code is well structured."})}}
      end)

      assert {:ok, answer} = Agent.run("Analyze this codebase")
      assert answer == "The code is well structured."
    end

    test "executes tool calls iteratively" do
      # First call: LLM requests a tool call
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"tool": "list_files", "args": {"path": "/tmp", "pattern": "*"}})}}
      end)

      # Second call: LLM returns final answer based on tool result
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"answer": "Found 3 files in the directory."})}}
      end)

      assert {:ok, answer} = Agent.run("List files in /tmp", tools: [:list_files])
      assert String.contains?(answer, "files")
    end

    test "respects max_iterations limit" do
      # The current regex in parse_response doesn't handle nested JSON,
      # so when max_iterations is reached without a final answer or tool call,
      # it returns :no_progress if no tools were successfully called
      PortfolioManager.Mocks.LLM
      |> expect(:complete, 3, fn _messages, _opts ->
        # Just return plain text with no valid JSON - will hit :continue path
        {:ok, %{content: "I'm thinking about this..."}}
      end)

      capture_log(fn ->
        assert {:error, :no_progress} = Agent.run("Infinite task", max_iterations: 3)
      end)
    end

    test "handles LLM errors gracefully" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:error, :rate_limited}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = Agent.run("Test task")
      end)
    end

    test "supports custom tool selection" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"answer": "Search results found."})}}
      end)

      assert {:ok, _} = Agent.run("Search for code", tools: [:search_code])
    end
  end

  describe "available_tools/0" do
    test "returns list of tool specs" do
      tools = Agent.available_tools()

      assert is_list(tools)
      tool_names = Enum.map(tools, & &1.name)
      assert :search_code in tool_names
      assert :read_file in tool_names
      assert :list_files in tool_names
      assert :get_graph_context in tool_names
    end
  end

  describe "parse_tool_call/1" do
    test "parses simple tool call" do
      content = ~s({"tool": "search_code", "args": {"query": "test"}})
      assert {:tool_call, :search_code, %{"query" => "test"}} = Agent.parse_tool_call(content)
    end

    test "parses alternative format with name/arguments" do
      content = ~s({"name": "read_file", "arguments": {"path": "/tmp/file.txt"}})

      assert {:tool_call, :read_file, %{"path" => "/tmp/file.txt"}} =
               Agent.parse_tool_call(content)
    end

    test "parses nested JSON in args" do
      content =
        ~s({"tool": "search_code", "args": {"filters": {"type": "function"}, "limit": 10}})

      assert {:tool_call, :search_code, args} = Agent.parse_tool_call(content)
      assert args["filters"]["type"] == "function"
      assert args["limit"] == 10
    end

    test "parses final answer" do
      content = ~s({"answer": "This is the final answer."})
      assert {:final_answer, "This is the final answer."} = Agent.parse_tool_call(content)
    end

    test "extracts JSON from surrounding text" do
      content = """
      Let me search for that.

      {"tool": "search_code", "args": {"query": "hello"}}

      Waiting for results...
      """

      assert {:tool_call, :search_code, _args} = Agent.parse_tool_call(content)
    end

    test "returns :continue for invalid JSON" do
      assert :continue = Agent.parse_tool_call("Just some text")
    end

    test "returns :final_answer for long text without JSON" do
      content = String.duplicate("This is a detailed explanation. ", 10)
      assert {:final_answer, ^content} = Agent.parse_tool_call(content)
    end

    test "handles escaped quotes in strings" do
      content = ~s({"tool": "search", "args": {"query": "find \\"quoted\\" text"}})
      assert {:tool_call, :search, args} = Agent.parse_tool_call(content)
      assert args["query"] == ~s(find "quoted" text)
    end
  end

  describe "execute_tool/1" do
    test "executes a known tool" do
      result = Agent.execute_tool(%{tool: :list_files, arguments: %{"path" => System.tmp_dir!()}})

      assert {:ok, %{tool: :list_files, success: true}} = result
    end

    test "returns error for unknown tool" do
      result = Agent.execute_tool(%{tool: :unknown_tool, arguments: %{}})

      assert {:error, {:unknown_tool, :unknown_tool}} = result
    end
  end

  describe "max_iterations/0" do
    test "returns default max iterations" do
      assert Agent.max_iterations() == 10
    end
  end
end
