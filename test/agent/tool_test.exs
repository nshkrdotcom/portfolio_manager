defmodule PortfolioManager.Agent.ToolTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Agent.Tool

  describe "list_all/0" do
    test "returns all available tools" do
      tools = Tool.list_all()

      assert is_list(tools)
      assert length(tools) >= 4

      tool_names = Enum.map(tools, & &1.name)
      assert :search_code in tool_names
      assert :read_file in tool_names
      assert :list_files in tool_names
      assert :get_graph_context in tool_names
    end

    test "each tool has required fields" do
      tools = Tool.list_all()

      Enum.each(tools, fn tool ->
        assert is_atom(tool.name)
        assert is_binary(tool.description)
        assert is_list(tool.parameters)
        assert is_function(tool.execute, 1)
      end)
    end

    test "each tool parameter has required fields" do
      tools = Tool.list_all()

      Enum.each(tools, fn tool ->
        Enum.each(tool.parameters, fn param ->
          assert is_atom(param.name)
          assert param.type in [:string, :integer, :boolean]
          assert is_boolean(param.required)
          assert is_binary(param.description)
        end)
      end)
    end
  end

  describe "search_code tool" do
    setup do
      tool =
        Tool.list_all()
        |> Enum.find(&(&1.name == :search_code))

      {:ok, tool: tool}
    end

    test "has correct description", %{tool: tool} do
      assert String.contains?(String.downcase(tool.description), "search")
    end

    test "has query parameter", %{tool: tool} do
      query_param = Enum.find(tool.parameters, &(&1.name == :query))
      assert query_param.required == true
      assert query_param.type == :string
    end
  end

  describe "read_file tool" do
    setup do
      tool =
        Tool.list_all()
        |> Enum.find(&(&1.name == :read_file))

      {:ok, tool: tool}
    end

    test "has correct description", %{tool: tool} do
      assert String.contains?(tool.description, "Read")
    end

    test "has path parameter", %{tool: tool} do
      path_param = Enum.find(tool.parameters, &(&1.name == :path))
      assert path_param.required == true
      assert path_param.type == :string
    end

    test "executes successfully for existing file", %{tool: tool} do
      # Create a temp file
      path = Path.join(System.tmp_dir!(), "test_read_#{:rand.uniform(10000)}.txt")
      File.write!(path, "Hello, World!")

      on_exit(fn -> File.rm(path) end)

      result = tool.execute.(%{"path" => path})
      assert {:ok, "Hello, World!"} = result
    end

    test "executes with line slicing", %{tool: tool} do
      path = Path.join(System.tmp_dir!(), "test_lines_#{:rand.uniform(10000)}.txt")
      File.write!(path, "Line 1\nLine 2\nLine 3\nLine 4\nLine 5")

      on_exit(fn -> File.rm(path) end)

      result = tool.execute.(%{"path" => path, "start_line" => 2, "end_line" => 4})
      assert {:ok, content} = result
      assert content == "Line 2\nLine 3\nLine 4"
    end

    test "returns error for non-existent file", %{tool: tool} do
      result = tool.execute.(%{"path" => "/nonexistent/file.txt"})
      assert {:error, :enoent} = result
    end
  end

  describe "list_files tool" do
    setup do
      tool =
        Tool.list_all()
        |> Enum.find(&(&1.name == :list_files))

      {:ok, tool: tool}
    end

    test "has correct description", %{tool: tool} do
      assert String.contains?(tool.description, "List files")
    end

    test "lists files in directory", %{tool: tool} do
      # Use system tmp directory
      result = tool.execute.(%{"path" => System.tmp_dir!(), "pattern" => "*"})
      assert {:ok, files} = result
      assert is_list(files)
    end

    test "uses default pattern when not specified", %{tool: tool} do
      result = tool.execute.(%{"path" => System.tmp_dir!()})
      assert {:ok, files} = result
      assert is_list(files)
    end
  end

  describe "get_graph_context tool" do
    setup do
      tool =
        Tool.list_all()
        |> Enum.find(&(&1.name == :get_graph_context))

      {:ok, tool: tool}
    end

    test "has correct description", %{tool: tool} do
      assert String.contains?(tool.description, "graph")
    end

    test "has entity parameter", %{tool: tool} do
      entity_param = Enum.find(tool.parameters, &(&1.name == :entity))
      assert entity_param.required == true
      assert entity_param.type == :string
    end

    test "has optional depth parameter", %{tool: tool} do
      depth_param = Enum.find(tool.parameters, &(&1.name == :depth))
      assert depth_param.required == false
      assert depth_param.type == :integer
    end
  end

  describe "validate_args/2" do
    test "returns :ok for valid args" do
      tool = Enum.find(Tool.list_all(), &(&1.name == :read_file))

      assert :ok = Tool.validate_args(tool, %{"path" => "/tmp/test.txt"})
    end

    test "returns :ok for atom keys" do
      tool = Enum.find(Tool.list_all(), &(&1.name == :read_file))

      assert :ok = Tool.validate_args(tool, %{path: "/tmp/test.txt"})
    end

    test "returns error for missing required param" do
      tool = Enum.find(Tool.list_all(), &(&1.name == :read_file))

      assert {:error, errors} = Tool.validate_args(tool, %{})
      assert Enum.any?(errors, &String.contains?(&1, "path"))
    end

    test "returns error for wrong type" do
      tool = Enum.find(Tool.list_all(), &(&1.name == :read_file))

      assert {:error, errors} = Tool.validate_args(tool, %{path: 123})
      assert Enum.any?(errors, &String.contains?(&1, "expected string"))
    end

    test "allows optional params to be missing" do
      tool = Enum.find(Tool.list_all(), &(&1.name == :read_file))

      assert :ok = Tool.validate_args(tool, %{path: "/tmp/file"})
    end
  end

  describe "format_for_llm/1" do
    test "formats tools for LLM prompt" do
      tools = Tool.list_all()
      output = Tool.format_for_llm(tools)

      assert is_binary(output)
      assert String.contains?(output, "search_code")
      assert String.contains?(output, "read_file")
      assert String.contains?(output, "(required)")
      assert String.contains?(output, "(optional)")
    end
  end

  describe "default_context/0" do
    test "returns context with nil values and Router" do
      context = Tool.default_context()

      assert context.session_id == nil
      assert context.user_id == nil
      assert context.repo == nil
      assert context.router == PortfolioManager.Router
    end
  end

  describe "context_from_session/1" do
    test "extracts context from session" do
      alias PortfolioManager.Agent.Session

      session =
        Session.new(
          context: %{repo: "/path/to/repo"},
          metadata: %{user_id: "user123"}
        )

      context = Tool.context_from_session(session)

      assert context.session_id == session.id
      assert context.repo == "/path/to/repo"
      assert context.user_id == "user123"
      assert context.router == PortfolioManager.Router
    end
  end

  describe "to_spec/1" do
    defmodule TestToolModule do
      @behaviour PortfolioManager.Agent.Tool

      @impl true
      def name, do: :test_tool

      @impl true
      def description, do: "A test tool"

      @impl true
      def parameters do
        [%{name: :input, type: :string, required: true, description: "Input value"}]
      end

      @impl true
      def execute(args, _context) do
        {:ok, "Executed with: #{args["input"]}"}
      end
    end

    test "converts module to spec" do
      spec = Tool.to_spec(TestToolModule)

      assert spec.name == :test_tool
      assert spec.description == "A test tool"
      assert length(spec.parameters) == 1
      assert is_function(spec.execute, 1)
    end

    test "spec execute function works" do
      spec = Tool.to_spec(TestToolModule)

      assert {:ok, result} = spec.execute.(%{"input" => "hello"})
      assert result == "Executed with: hello"
    end
  end
end
