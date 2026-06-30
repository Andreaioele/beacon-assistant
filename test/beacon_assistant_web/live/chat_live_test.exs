defmodule BeaconAssistantWeb.ChatLiveTest do
  use BeaconAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BeaconAssistant.Conversations

  setup do
    previous = Application.get_env(:beacon_assistant, :chatbot_complete)

    Application.put_env(:beacon_assistant, :chatbot_complete, fn prompt ->
      assert prompt =~ "Return a JSON object only"

      {:ok,
       Jason.encode!(%{
         answer: "Billing is handled from the knowledge base.",
         sources: ["03-billing-and-refunds.md"]
       })}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:beacon_assistant, :chatbot_complete, previous)
      else
        Application.delete_env(:beacon_assistant, :chatbot_complete)
      end
    end)
  end

  test "renders chat UI", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Beacon Support Assistant"
    assert html =~ "Ask about billing, 2FA, plans..."
  end

  test "submits a question and renders the answer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form", chat: %{question: "how billing works"})
      |> render_submit()

    assert html =~ "how billing works"
    assert html =~ "Billing is handled from the knowledge base."
    assert html =~ "Sources used:"
    assert html =~ "03-billing-and-refunds.md"
    refute html =~ "04-account-and-security.md"
  end

  test "submitting multiple questions in the same browser session persists exchanges", %{
    conn: conn
  } do
    session_id = Ecto.UUID.generate()
    conn = init_test_session(conn, %{chat_session_id: session_id})

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form", chat: %{question: "how billing works"})
    |> render_submit()

    view
    |> form("form", chat: %{question: "how do refunds work"})
    |> render_submit()

    exchanges = Conversations.list_exchanges_for_session(session_id)

    assert Enum.map(exchanges, & &1.question) == [
             "how billing works",
             "how do refunds work"
           ]

    assert Enum.all?(exchanges, &(&1.status == "completed"))
  end

  test "reload with same session renders previous exchanges", %{conn: conn} do
    session_id = Ecto.UUID.generate()

    assert {:ok, _session} = Conversations.get_or_create_session(session_id)

    assert {:ok, _exchange} =
             Conversations.create_exchange(%{
               chat_session_id: session_id,
               question: "previous question",
               answer: "previous answer",
               status: "completed",
               sources: ["source.md"]
             })

    conn = init_test_session(conn, %{chat_session_id: session_id})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "previous question"
    assert html =~ "previous answer"
    assert html =~ "source.md"
  end

  test "empty question is ignored with validation message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form", chat: %{question: "   "})
      |> render_submit()

    assert html =~ "Enter a question before sending."
    refute html =~ "Billing is handled from the knowledge base."
  end
end
