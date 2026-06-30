defmodule BeaconAssistant.ConversationsTest do
  use BeaconAssistant.DataCase, async: true

  alias BeaconAssistant.Conversations
  alias BeaconAssistant.Conversations.{ChatExchange, ChatSession}
  alias BeaconAssistant.Repo

  test "get_or_create_session creates a session with defaults" do
    session_id = Ecto.UUID.generate()

    assert {:ok, %ChatSession{} = session} = Conversations.get_or_create_session(session_id)
    assert session.id == session_id
    assert session.started_at
    assert session.last_seen_at
    assert session.metadata == %{}
  end

  test "get_or_create_session returns an existing session and touches last_seen_at" do
    session_id = Ecto.UUID.generate()

    assert {:ok, first_session} = Conversations.get_or_create_session(session_id)
    assert {:ok, second_session} = Conversations.get_or_create_session(session_id)

    assert first_session.id == second_session.id
    assert DateTime.compare(second_session.last_seen_at, first_session.last_seen_at) in [:eq, :gt]
  end

  test "maybe_set_conversation_title sets a title only when missing" do
    assert {:ok, session} = Conversations.get_or_create_session(Ecto.UUID.generate())

    assert {:ok, titled_session} =
             Conversations.maybe_set_conversation_title(
               session,
               "  How do I reset two factor authentication?  "
             )

    assert titled_session.conversation_title == "How do I reset two factor authentication?"

    assert {:ok, unchanged_session} =
             Conversations.maybe_set_conversation_title(titled_session, "Another question")

    assert unchanged_session.conversation_title == "How do I reset two factor authentication?"
  end

  test "create_exchange persists completed exchanges with metrics" do
    assert {:ok, session} = Conversations.get_or_create_session(Ecto.UUID.generate())

    assert {:ok, %ChatExchange{} = exchange} =
             Conversations.create_exchange(%{
               chat_session_id: session.id,
               question: "How does billing work?",
               answer: "Billing renews monthly or annually.",
               status: "completed",
               sources: ["03-billing-and-refunds.md"],
               provider: "openai",
               model_name: "gpt-test",
               input_tokens: 12,
               output_tokens: 8,
               total_tokens: 20,
               response_time_ms: 345,
               prompt_bytes: 1234,
               provider_request_id: "req_123",
               metadata: %{fallback_used: false}
             })

    assert exchange.chat_session_id == session.id
    assert exchange.status == "completed"
    assert exchange.provider_request_id == "req_123"
    assert exchange.total_tokens == 20
  end

  test "create_exchange persists failed exchanges with error reason" do
    assert {:ok, session} = Conversations.get_or_create_session(Ecto.UUID.generate())

    assert {:ok, exchange} =
             Conversations.create_exchange(%{
               chat_session_id: session.id,
               question: "Can you answer?",
               answer: "Sorry, I couldn't generate an answer right now. Please try again.",
               status: "failed",
               error_reason: ":timeout"
             })

    assert exchange.status == "failed"
    assert exchange.error_reason == ":timeout"
  end

  test "exchange changeset requires session question and status" do
    changeset = ChatExchange.changeset(%ChatExchange{}, %{})

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).chat_session_id
    assert "can't be blank" in errors_on(changeset).question
    assert "can't be blank" in errors_on(changeset).status
  end

  test "list_exchanges_for_session returns chronological exchanges for one session" do
    assert {:ok, session} = Conversations.get_or_create_session(Ecto.UUID.generate())
    assert {:ok, other_session} = Conversations.get_or_create_session(Ecto.UUID.generate())

    assert {:ok, first} =
             Conversations.create_exchange(%{
               chat_session_id: session.id,
               question: "First",
               answer: "One",
               status: "completed"
             })

    assert {:ok, second} =
             Conversations.create_exchange(%{
               chat_session_id: session.id,
               question: "Second",
               answer: "Two",
               status: "completed"
             })

    assert {:ok, _other} =
             Conversations.create_exchange(%{
               chat_session_id: other_session.id,
               question: "Other",
               answer: "Other",
               status: "completed"
             })

    assert Enum.map(Conversations.list_exchanges_for_session(session.id), & &1.id) == [
             first.id,
             second.id
           ]
  end

  test "chat sessions can be queried with conversation titles" do
    assert {:ok, session} = Conversations.get_or_create_session(Ecto.UUID.generate())
    assert {:ok, session} = Conversations.maybe_set_conversation_title(session, "Pricing details")

    assert Repo.get!(ChatSession, session.id).conversation_title == "Pricing details"
  end
end
