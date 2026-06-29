defmodule BeaconAssistant.ChatbotTest do
  use ExUnit.Case, async: true

  alias BeaconAssistant.Chatbot

  @context """
  --- BEGIN DOCUMENT: 03-billing-and-refunds.md ---
  # Billing & refunds
  Paid plans renew automatically monthly or annually.
  --- END DOCUMENT: 03-billing-and-refunds.md ---

  --- BEGIN DOCUMENT: 04-account-and-security.md ---
  # Account & security
  Beacon supports 2FA on all plans using authenticator apps.
  --- END DOCUMENT: 04-account-and-security.md ---

  --- BEGIN DOCUMENT: 02-plans-and-pricing.md ---
  # Plans & pricing
  Beacon has three plans: Free, Pro, and Business.
  --- END DOCUMENT: 02-plans-and-pricing.md ---
  """

  test "passes billing question and knowledge base context to LLM" do
    assert {:ok, exchange} = ask_with_fake_llm("how billing works")

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == ["03-billing-and-refunds.md"]
  end

  test "passes 2FA reset question and knowledge base context to LLM" do
    assert {:ok, exchange} = ask_with_fake_llm("how to reset two-factor auth")

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
  end

  test "passes plan question and knowledge base context to LLM" do
    assert {:ok, exchange} = ask_with_fake_llm("what's included in each plan")

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
  end

  test "returns knowledge base fallback when no markdown context exists" do
    build_context = fn -> {:error, :no_knowledge_base_documents} end

    assert {:ok, exchange} = Chatbot.ask("unknown", build_context: build_context)
    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:knowledge_base)
    assert exchange.sources == []
  end

  test "returns LLM fallback when Ollama fails" do
    build_context = fn -> {:ok, %{context: @context, sources: ["source.md"]}} end
    complete = fn _prompt -> {:error, :timeout} end

    assert {:ok, exchange} =
             Chatbot.ask("how billing works", build_context: build_context, complete: complete)

    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:llm)
    assert exchange.sources == []
  end

  test "rejects empty questions" do
    assert {:error, :empty_question} = Chatbot.ask("   ")
  end

  defp ask_with_fake_llm(question) do
    parent = self()
    build_context = fn -> {:ok, %{context: @context, sources: ["03-billing-and-refunds.md"]}} end

    complete = fn prompt ->
      send(parent, {:prompt, prompt})
      {:ok, "Grounded answer"}
    end

    result = Chatbot.ask(question, build_context: build_context, complete: complete)

    assert_received {:prompt, prompt}
    assert prompt =~ @context
    assert prompt =~ question
    assert prompt =~ "Answer only from the context above."

    result
  end
end
