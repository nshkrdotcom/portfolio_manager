defmodule PortfolioManager.Agent.Session do
  @moduledoc """
  Agent session management.

  Sessions track the state of an agent execution, including
  messages exchanged, tools called, and contextual information.

  ## Message Format

  Messages are normalized to include:

    * `:role` - :user, :assistant, or :tool
    * `:content` - Message content string
    * `:timestamp` - DateTime when message was added
    * `:tool_name` - (optional) Tool name for tool messages
    * `:error` - (optional) Error info for failed tool calls

  ## Usage

      session =
        Session.new(context: %{repo: "my_app"})
        |> Session.add_message(%{role: :user, content: "Hello"})
        |> Session.with_context(:branch, "main")

      # Get messages for LLM
      messages = Session.to_llm_messages(session)

      # Check session size
      tokens = Session.token_estimate(session)
  """

  @type message :: %{
          role: :user | :assistant | :tool,
          content: String.t(),
          timestamp: DateTime.t(),
          tool_name: atom() | nil,
          error: term() | nil
        }

  @type tool_result :: %{
          tool: atom(),
          result: term(),
          timestamp: DateTime.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          messages: [message()],
          tool_results: [tool_result()],
          context: map(),
          metadata: map()
        }

  defstruct [
    :id,
    :created_at,
    :updated_at,
    messages: [],
    tool_results: [],
    context: %{},
    metadata: %{}
  ]

  @doc """
  Create a new session.

  ## Options

    * `:context` - Initial context map (default: %{})
    * `:metadata` - Initial metadata map (default: %{})
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: generate_id(),
      created_at: now,
      updated_at: now,
      context: Keyword.get(opts, :context, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Add a message to the session.

  The message map must include `:role` and `:content`. Optional fields:
  `:tool_name` and `:error`.
  """
  @spec add_message(t(), map()) :: t()
  def add_message(session, message) do
    normalized = normalize_message(message)

    %{
      session
      | messages: session.messages ++ [normalized],
        updated_at: next_timestamp(session.updated_at)
    }
  end

  @doc """
  Add a tool result to the session.
  """
  @spec add_tool_result(t(), atom(), term()) :: t()
  def add_tool_result(session, tool_name, result) do
    tool_result = %{
      tool: tool_name,
      result: result,
      timestamp: DateTime.utc_now()
    }

    %{
      session
      | tool_results: session.tool_results ++ [tool_result],
        updated_at: next_timestamp(session.updated_at)
    }
  end

  @doc """
  Get all messages in the session.
  """
  @spec get_messages(t()) :: [message()]
  def get_messages(session) do
    session.messages
  end

  @doc """
  Convert session messages to LLM-compatible format.

  Returns a list of maps with only `:role` and `:content` keys.
  """
  @spec to_llm_messages(t()) :: [%{role: atom(), content: String.t()}]
  def to_llm_messages(session) do
    Enum.map(session.messages, fn msg ->
      %{role: msg.role, content: msg.content}
    end)
  end

  @doc """
  Estimate token count for the session.

  Uses a simple heuristic of characters / 4.
  """
  @spec token_estimate(t()) :: non_neg_integer()
  def token_estimate(session) do
    session.messages
    |> Enum.map(fn msg -> String.length(msg.content) end)
    |> Enum.sum()
    |> div(4)
  end

  @doc """
  Get the count of messages in the session.
  """
  @spec message_count(t()) :: non_neg_integer()
  def message_count(session) do
    length(session.messages)
  end

  @doc """
  Get the last n messages from the session.
  """
  @spec last_messages(t(), pos_integer()) :: [message()]
  def last_messages(session, n) do
    Enum.take(session.messages, -n)
  end

  @doc """
  Clear all messages from the session.

  Preserves context, metadata, tool_results, and session ID.
  """
  @spec clear_messages(t()) :: t()
  def clear_messages(session) do
    %{session | messages: [], updated_at: next_timestamp(session.updated_at)}
  end

  @doc """
  Set a context value.
  """
  @spec with_context(t(), atom(), term()) :: t()
  def with_context(session, key, value) do
    %{session | context: Map.put(session.context, key, value)}
  end

  @doc """
  Get a context value by key.
  """
  @spec get_context(t(), atom()) :: term() | nil
  def get_context(session, key) do
    Map.get(session.context, key)
  end

  defp normalize_message(message) do
    %{
      role: message[:role] || message["role"],
      content: message[:content] || message["content"] || "",
      timestamp: DateTime.utc_now(),
      tool_name: message[:tool_name] || message["tool_name"],
      error: message[:error] || message["error"]
    }
  end

  defp next_timestamp(previous) do
    now = DateTime.utc_now()

    case DateTime.compare(now, previous) do
      :gt -> now
      _ -> DateTime.add(previous, 1, :microsecond)
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
