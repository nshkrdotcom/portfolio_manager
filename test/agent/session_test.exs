defmodule PortfolioManager.Agent.SessionTest do
  use PortfolioManager.SupertesterCase, async: true

  alias PortfolioManager.Agent.Session

  describe "new/1" do
    test "creates a new session with defaults" do
      session = Session.new()

      assert is_binary(session.id)
      assert String.length(session.id) == 32
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at
      assert session.messages == []
      assert session.tool_results == []
      assert session.context == %{}
      assert session.metadata == %{}
    end

    test "creates session with context option" do
      session = Session.new(context: %{repo: "my_app", branch: "main"})

      assert session.context == %{repo: "my_app", branch: "main"}
    end

    test "creates session with metadata option" do
      session = Session.new(metadata: %{user_id: "123", request_id: "abc"})

      assert session.metadata == %{user_id: "123", request_id: "abc"}
    end

    test "creates session with both context and metadata" do
      session =
        Session.new(
          context: %{repo: "app"},
          metadata: %{user_id: "123"}
        )

      assert session.context == %{repo: "app"}
      assert session.metadata == %{user_id: "123"}
    end
  end

  describe "add_message/2" do
    test "adds a message with role and content" do
      session = Session.new()

      session = Session.add_message(session, %{role: :user, content: "Hello"})

      assert length(session.messages) == 1
      [msg] = session.messages
      assert msg.role == :user
      assert msg.content == "Hello"
      assert %DateTime{} = msg.timestamp
    end

    test "updates updated_at timestamp" do
      session = Session.new()
      original_updated_at = session.updated_at

      session = Session.add_message(session, %{role: :assistant, content: "Hi"})

      assert DateTime.compare(session.updated_at, original_updated_at) == :gt
    end

    test "preserves message order" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "First"})
        |> Session.add_message(%{role: :assistant, content: "Second"})
        |> Session.add_message(%{role: :user, content: "Third"})

      assert length(session.messages) == 3
      [m1, m2, m3] = session.messages
      assert m1.content == "First"
      assert m2.content == "Second"
      assert m3.content == "Third"
    end

    test "adds message with tool_name field" do
      session = Session.new()

      session =
        Session.add_message(session, %{
          role: :tool,
          content: "result",
          tool_name: :search_code
        })

      [msg] = session.messages
      assert msg.tool_name == :search_code
    end

    test "adds message with error field" do
      session = Session.new()

      session =
        Session.add_message(session, %{
          role: :tool,
          content: "",
          tool_name: :read_file,
          error: :file_not_found
        })

      [msg] = session.messages
      assert msg.error == :file_not_found
    end
  end

  describe "add_tool_result/3" do
    test "adds tool result to session" do
      session = Session.new()

      session = Session.add_tool_result(session, :search_code, {:ok, [%{content: "found"}]})

      assert length(session.tool_results) == 1
      [result] = session.tool_results
      assert result.tool == :search_code
      assert result.result == {:ok, [%{content: "found"}]}
      assert %DateTime{} = result.timestamp
    end

    test "updates updated_at timestamp" do
      session = Session.new()
      original = session.updated_at

      session = Session.add_tool_result(session, :list_files, {:ok, []})

      assert DateTime.compare(session.updated_at, original) == :gt
    end

    test "accumulates multiple tool results" do
      session =
        Session.new()
        |> Session.add_tool_result(:search_code, {:ok, []})
        |> Session.add_tool_result(:read_file, {:error, :not_found})

      assert length(session.tool_results) == 2
    end
  end

  describe "to_llm_messages/1" do
    test "converts session messages to LLM format" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "Hello"})
        |> Session.add_message(%{role: :assistant, content: "Hi there"})

      messages = Session.to_llm_messages(session)

      assert messages == [
               %{role: :user, content: "Hello"},
               %{role: :assistant, content: "Hi there"}
             ]
    end

    test "excludes timestamps and extra fields" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "Test", extra: :ignored})

      [msg] = Session.to_llm_messages(session)

      assert MapSet.new(Map.keys(msg)) == MapSet.new([:content, :role])
    end
  end

  describe "token_estimate/1" do
    test "estimates tokens based on content length" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: String.duplicate("a", 100)})

      # Rough estimate: chars / 4
      estimate = Session.token_estimate(session)

      assert estimate == 25
    end

    test "sums tokens across all messages" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: String.duplicate("a", 100)})
        |> Session.add_message(%{role: :assistant, content: String.duplicate("b", 200)})

      estimate = Session.token_estimate(session)

      # (100 + 200) / 4
      assert estimate == 75
    end

    test "returns 0 for empty session" do
      session = Session.new()

      assert Session.token_estimate(session) == 0
    end
  end

  describe "message_count/1" do
    test "returns count of messages" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "1"})
        |> Session.add_message(%{role: :assistant, content: "2"})
        |> Session.add_message(%{role: :user, content: "3"})

      assert Session.message_count(session) == 3
    end

    test "returns 0 for empty session" do
      assert Session.message_count(Session.new()) == 0
    end
  end

  describe "last_messages/2" do
    test "returns last n messages" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "1"})
        |> Session.add_message(%{role: :assistant, content: "2"})
        |> Session.add_message(%{role: :user, content: "3"})
        |> Session.add_message(%{role: :assistant, content: "4"})

      last_two = Session.last_messages(session, 2)

      assert length(last_two) == 2
      assert Enum.at(last_two, 0).content == "3"
      assert Enum.at(last_two, 1).content == "4"
    end

    test "returns all messages when n exceeds count" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "1"})
        |> Session.add_message(%{role: :assistant, content: "2"})

      result = Session.last_messages(session, 10)

      assert length(result) == 2
    end

    test "returns empty list for empty session" do
      assert Session.last_messages(Session.new(), 5) == []
    end
  end

  describe "clear_messages/1" do
    test "clears messages but keeps context" do
      session =
        Session.new(context: %{repo: "app"})
        |> Session.add_message(%{role: :user, content: "Hello"})
        |> Session.add_message(%{role: :assistant, content: "Hi"})

      cleared = Session.clear_messages(session)

      assert cleared.messages == []
      assert cleared.context == %{repo: "app"}
    end

    test "keeps metadata" do
      session =
        Session.new(metadata: %{user_id: "123"})
        |> Session.add_message(%{role: :user, content: "Test"})

      cleared = Session.clear_messages(session)

      assert cleared.metadata == %{user_id: "123"}
    end

    test "keeps tool_results" do
      session =
        Session.new()
        |> Session.add_tool_result(:search, {:ok, []})
        |> Session.add_message(%{role: :user, content: "Test"})

      cleared = Session.clear_messages(session)

      assert length(cleared.tool_results) == 1
    end

    test "keeps session id" do
      session = Session.new()
      original_id = session.id

      cleared = Session.clear_messages(session)

      assert cleared.id == original_id
    end
  end

  describe "with_context/3" do
    test "sets a context key" do
      session = Session.new()

      session = Session.with_context(session, :repo, "my_app")

      assert session.context.repo == "my_app"
    end

    test "overwrites existing key" do
      session = Session.new(context: %{repo: "old"})

      session = Session.with_context(session, :repo, "new")

      assert session.context.repo == "new"
    end

    test "preserves other context keys" do
      session = Session.new(context: %{repo: "app", branch: "main"})

      session = Session.with_context(session, :repo, "updated")

      assert session.context == %{repo: "updated", branch: "main"}
    end
  end

  describe "get_context/2" do
    test "gets a context value by key" do
      session = Session.new(context: %{repo: "my_app"})

      assert Session.get_context(session, :repo) == "my_app"
    end

    test "returns nil for missing key" do
      session = Session.new()

      assert Session.get_context(session, :unknown) == nil
    end
  end

  describe "get_messages/1" do
    test "returns all messages" do
      session =
        Session.new()
        |> Session.add_message(%{role: :user, content: "Hello"})

      messages = Session.get_messages(session)

      assert length(messages) == 1
    end
  end
end
