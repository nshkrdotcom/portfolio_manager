defmodule PortfolioManager.LLMTest do
  use PortfolioManager.SupertesterCase, async: false

  import Mox

  alias PortfolioManager.LLM
  alias PortfolioManager.Mocks

  setup :verify_on_exit!

  setup do
    PortfolioCore.Registry.clear()
    :ok
  end

  describe "complete/2" do
    test "delegates to the registered :llm adapter" do
      PortfolioCore.Registry.register(:llm, Mocks.LLM, model: "test")

      messages = [%{role: :user, content: "hello"}]

      Mocks.LLM
      |> expect(:complete, fn ^messages, opts ->
        assert opts[:model] == "override"
        {:ok, %{content: "ok", model: "test", usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      assert {:ok, result} = LLM.complete(messages, model: "override")
      assert result.content == "ok"
    end

    test "returns error when no adapter is registered" do
      assert {:error, :no_llm_adapter_configured} = LLM.complete([])
    end
  end

  describe "stream/2" do
    test "maps adapter chunks to strings" do
      PortfolioCore.Registry.register(:llm, Mocks.LLM, [])

      Mocks.LLM
      |> expect(:stream, fn _messages, _opts ->
        {:ok, [%{delta: "A"}, %{delta: "B"}]}
      end)

      assert {:ok, stream} = LLM.stream([%{role: :user, content: "hi"}])
      assert Enum.to_list(stream) == ["A", "B"]
    end

    test "returns error when no adapter is registered" do
      assert {:error, :no_llm_adapter_configured} = LLM.stream([])
    end
  end
end
