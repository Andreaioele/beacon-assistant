defmodule BeaconAssistantWeb.ChatLiveTest do
  use BeaconAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BeaconAssistant.{Conversations, ErrorHandling}

  setup do
    previous_complete = Application.get_env(:beacon_assistant, :chatbot_complete)
    previous_stream = Application.get_env(:beacon_assistant, :chatbot_stream)

    Application.put_env(:beacon_assistant, :chatbot_stream, fn prompt, opts ->
      assert prompt =~ "Return a JSON object only"

      answer =
        Jason.encode!(%{
          answer: "Billing is handled from the knowledge base.",
          sources: ["03-billing-and-refunds.md"]
        })

      opts[:on_delta].(answer)
      {:ok, %{answer: answer}}
    end)

    on_exit(fn ->
      if previous_complete do
        Application.put_env(:beacon_assistant, :chatbot_complete, previous_complete)
      else
        Application.delete_env(:beacon_assistant, :chatbot_complete)
      end

      if previous_stream do
        Application.put_env(:beacon_assistant, :chatbot_stream, previous_stream)
      else
        Application.delete_env(:beacon_assistant, :chatbot_stream)
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

    pending_html =
      view
      |> form("form", chat: %{question: "how billing works"})
      |> render_submit()

    assert pending_html =~ "how billing works"
    assert pending_html =~ "Generating..."

    html = render_until(view, "Sources used:")

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

    render_until(view, "Billing is handled from the knowledge base.")

    view
    |> form("form", chat: %{question: "how do refunds work"})
    |> render_submit()

    wait_for_exchange_count(session_id, 2)

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

  test "offline browser status shows warning", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_hook(view, "network_status_changed", %{online: false})

    assert html =~ ErrorHandling.offline_message()
  end

  test "offline submit does not call chatbot", %{conn: conn} do
    parent = self()

    Application.put_env(:beacon_assistant, :chatbot_stream, fn _prompt, _opts ->
      send(parent, :chatbot_called)
      {:ok, "should not run"}
    end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "network_status_changed", %{online: false})

    html = render_hook(view, "send", %{"chat" => %{"question" => "how billing works"}})

    assert html =~ ErrorHandling.offline_message()
    refute_received :chatbot_called
  end

  test "returning online clears offline warning and allows submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render_hook(view, "network_status_changed", %{online: false}) =~
             ErrorHandling.offline_message()

    refute render_hook(view, "network_status_changed", %{online: true}) =~
             ErrorHandling.offline_message()

    view
    |> form("form", chat: %{question: "how billing works"})
    |> render_submit()

    html = render_until(view, "Sources used:")

    assert html =~ "Billing is handled from the knowledge base."
  end

  test "renders timeout failure without crashing", %{conn: conn} do
    Application.put_env(:beacon_assistant, :chatbot_stream, fn _prompt, _opts ->
      {:error, :timeout}
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form", chat: %{question: "how billing works"})
    |> render_submit()

    html = render_until(view, ErrorHandling.model_timeout_message())

    assert html =~ ErrorHandling.model_timeout_message()
  end

  test "renders critical failure without crashing", %{conn: conn} do
    Application.put_env(:beacon_assistant, :chatbot_stream, fn _prompt, _opts ->
      {:error, :critical}
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("form", chat: %{question: "how billing works"})
    |> render_submit()

    html = render_until(view, ErrorHandling.critical_message())

    assert html =~ ErrorHandling.critical_message()
  end

  defp render_until(view, expected, attempts \\ 25)

  defp render_until(view, expected, attempts) when attempts > 0 do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(20)
      render_until(view, expected, attempts - 1)
    end
  end

  defp render_until(view, _expected, 0), do: render(view)

  defp wait_for_exchange_count(session_id, expected_count, attempts \\ 25)

  defp wait_for_exchange_count(session_id, expected_count, attempts) when attempts > 0 do
    if length(Conversations.list_exchanges_for_session(session_id)) == expected_count do
      :ok
    else
      Process.sleep(20)
      wait_for_exchange_count(session_id, expected_count, attempts - 1)
    end
  end

  defp wait_for_exchange_count(_session_id, _expected_count, 0), do: :ok
end
