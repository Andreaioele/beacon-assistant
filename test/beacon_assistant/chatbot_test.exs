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

  @sources [
    "03-billing-and-refunds.md",
    "04-account-and-security.md",
    "02-plans-and-pricing.md"
  ]

  test "passes billing question and knowledge base context to LLM" do
    assert {:ok, exchange} =
             ask_with_fake_llm("how billing works", ["03-billing-and-refunds.md"])

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == ["03-billing-and-refunds.md"]
  end

  test "passes 2FA reset question and knowledge base context to LLM" do
    assert {:ok, exchange} =
             ask_with_fake_llm("how to reset two-factor auth", ["04-account-and-security.md"])

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == ["04-account-and-security.md"]
  end

  test "passes plan question and knowledge base context to LLM" do
    assert {:ok, exchange} =
             ask_with_fake_llm("what's included in each plan", ["02-plans-and-pricing.md"])

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == ["02-plans-and-pricing.md"]
  end

  test "does not show candidate sources that the model did not declare as used" do
    assert {:ok, exchange} =
             ask_with_fake_llm("how billing works", ["03-billing-and-refunds.md"])

    assert exchange.sources == ["03-billing-and-refunds.md"]
    refute "04-account-and-security.md" in exchange.sources
    refute "02-plans-and-pricing.md" in exchange.sources
  end

  test "drops unknown sources and deduplicates declared sources" do
    assert {:ok, exchange} =
             ask_with_fake_llm("how billing works", [
               "03-billing-and-refunds.md",
               "unknown.md",
               "03-billing-and-refunds.md"
             ])

    assert exchange.sources == ["03-billing-and-refunds.md"]
  end

  test "uses no sources when the structured answer is the knowledge base fallback" do
    assert {:ok, exchange} =
             ask_with_fake_llm("unsupported question", ["03-billing-and-refunds.md"],
               answer: Chatbot.fallback_message(:knowledge_base)
             )

    assert exchange.status == :completed
    assert exchange.answer == Chatbot.fallback_message(:knowledge_base)
    assert exchange.sources == []
  end

  test "keeps unstructured answers but returns no sources" do
    build_context = fn -> {:ok, %{context: @context, sources: @sources}} end
    complete = fn _prompt -> {:ok, "Grounded answer"} end

    assert {:ok, exchange} =
             Chatbot.ask("how billing works", build_context: build_context, complete: complete)

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == []
  end

  test "streams only visible answer deltas while preserving final source validation" do
    build_context = fn -> {:ok, %{context: @context, sources: @sources}} end
    parent = self()

    stream = fn _prompt, opts ->
      opts[:on_delta].(~s({"answer":"Ground))
      opts[:on_delta].("ed answer")
      opts[:on_delta].(~s(","sources":["03-billing-and-refunds.md","unknown.md"]}))

      {:ok,
       %{
         answer:
           Jason.encode!(%{
             answer: "Grounded answer",
             sources: ["03-billing-and-refunds.md", "unknown.md"]
           }),
         provider: "ollama",
         model_name: "qwen3:14b"
       }}
    end

    assert {:ok, exchange} =
             Chatbot.ask_stream("how billing works",
               build_context: build_context,
               stream: stream,
               on_delta: fn delta -> send(parent, {:delta, delta}) end
             )

    assert exchange.status == :completed
    assert exchange.answer == "Grounded answer"
    assert exchange.sources == ["03-billing-and-refunds.md"]
    assert_received {:delta, "Ground"}
    assert_received {:delta, "ed answer"}
    refute_received {:delta, _delta}
  end

  test "ask_stream rejects empty questions" do
    assert {:error, :empty_question} = Chatbot.ask_stream("   ")
  end

  test "returns knowledge base fallback when no markdown context exists" do
    build_context = fn -> {:error, :no_knowledge_base_documents} end

    assert {:ok, exchange} = Chatbot.ask("unknown", build_context: build_context)
    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:knowledge_base)
    assert exchange.sources == []
  end

  test "returns timeout fallback when model times out" do
    build_context = fn -> {:ok, %{context: @context, sources: ["source.md"]}} end
    complete = fn _prompt -> {:error, :timeout} end

    assert {:ok, exchange} =
             Chatbot.ask("how billing works", build_context: build_context, complete: complete)

    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:model_timeout)
    assert exchange.error_category == :model_timeout
    assert exchange.sources == []
  end

  test "returns critical fallback when LLM returns a critical error" do
    build_context = fn -> {:ok, %{context: @context, sources: ["source.md"]}} end
    complete = fn _prompt -> {:error, :critical} end

    assert {:ok, exchange} =
             Chatbot.ask("how billing works", build_context: build_context, complete: complete)

    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:critical)
    assert exchange.error_category == :critical
    assert exchange.sources == []
  end

  test "returns critical fallback when knowledge base raises" do
    build_context = fn -> raise RuntimeError, "disk unavailable" end

    assert {:ok, exchange} = Chatbot.ask("how billing works", build_context: build_context)

    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:critical)
    assert exchange.error_category == :critical
    assert exchange.sources == []
  end

  test "returns critical fallback when LLM raises" do
    build_context = fn -> {:ok, %{context: @context, sources: ["source.md"]}} end
    complete = fn _prompt -> raise RuntimeError, "provider crashed" end

    assert {:ok, exchange} =
             Chatbot.ask("how billing works", build_context: build_context, complete: complete)

    assert exchange.status == :failed
    assert exchange.answer == Chatbot.fallback_message(:critical)
    assert exchange.error_category == :critical
    assert exchange.sources == []
  end

  test "rejects empty questions" do
    assert {:error, :empty_question} = Chatbot.ask("   ")
  end

  defp ask_with_fake_llm(question, sources, opts \\ []) do
    parent = self()
    answer = Keyword.get(opts, :answer, "Grounded answer")
    build_context = fn -> {:ok, %{context: @context, sources: @sources}} end

    complete = fn prompt ->
      send(parent, {:prompt, prompt})
      {:ok, Jason.encode!(%{answer: answer, sources: sources})}
    end

    result = Chatbot.ask(question, build_context: build_context, complete: complete)

    assert_received {:prompt, prompt}
    assert prompt =~ @context
    assert prompt =~ question
    assert prompt =~ "Answer only from the context above."
    assert prompt =~ "Return a JSON object only"

    result
  end
end
