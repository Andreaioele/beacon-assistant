defmodule BeaconAssistant.ChatbotPersistenceTest do
  use BeaconAssistant.DataCase, async: true

  alias BeaconAssistant.{Chatbot, Conversations}

  @context """
  --- BEGIN DOCUMENT: 03-billing-and-refunds.md ---
  # Billing & refunds
  Paid plans renew automatically monthly or annually.
  --- END DOCUMENT: 03-billing-and-refunds.md ---
  """

  test "persists successful answers with session sources title request id and metrics" do
    session_id = Ecto.UUID.generate()

    build_context = fn ->
      {:ok,
       %{
         context: @context,
         sources: ["03-billing-and-refunds.md", "04-account-and-security.md"]
       }}
    end

    complete = fn _prompt ->
      {:ok,
       %{
         answer:
           Jason.encode!(%{
             answer: "Billing renews monthly or annually.",
             sources: ["03-billing-and-refunds.md"]
           }),
         provider: "openai",
         model_name: "gpt-test",
         input_tokens: 10,
         output_tokens: 7,
         total_tokens: 17,
         response_time_ms: 250,
         prompt_bytes: 900,
         provider_request_id: "req_123",
         fallback_used: false
       }}
    end

    assert {:ok, exchange} =
             Chatbot.ask("How does billing work?",
               chat_session_id: session_id,
               build_context: build_context,
               complete: complete
             )

    assert exchange.status == "completed"
    assert exchange.chat_session_id == session_id
    assert exchange.sources == ["03-billing-and-refunds.md"]
    refute "04-account-and-security.md" in exchange.sources
    assert exchange.model_name == "gpt-test"
    assert exchange.provider_request_id == "req_123"
    assert exchange.total_tokens == 17

    assert {:ok, session} = Conversations.get_or_create_session(session_id)
    assert session.conversation_title == "How does billing work?"
  end

  test "persists LLM failures with fallback answer and error reason" do
    session_id = Ecto.UUID.generate()
    build_context = fn -> {:ok, %{context: @context, sources: ["03-billing-and-refunds.md"]}} end

    complete = fn _prompt ->
      {:error, :timeout,
       %{
         provider: "openai",
         model_name: "gpt-test",
         response_time_ms: 15,
         prompt_bytes: 900
       }}
    end

    assert {:ok, exchange} =
             Chatbot.ask("How does billing work?",
               chat_session_id: session_id,
               build_context: build_context,
               complete: complete
             )

    assert exchange.status == "failed"
    assert exchange.answer == Chatbot.fallback_message(:llm)
    assert exchange.error_reason == ":timeout"
    assert exchange.model_name == "gpt-test"
    assert exchange.response_time_ms == 15
  end

  test "persists missing knowledge base failures" do
    session_id = Ecto.UUID.generate()
    build_context = fn -> {:error, :no_knowledge_base_documents} end

    assert {:ok, exchange} =
             Chatbot.ask("Unknown",
               chat_session_id: session_id,
               build_context: build_context
             )

    assert exchange.status == "failed"
    assert exchange.answer == Chatbot.fallback_message(:knowledge_base)
    assert exchange.error_reason == ":no_knowledge_base_documents"
  end
end
