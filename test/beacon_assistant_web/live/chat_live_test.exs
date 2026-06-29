defmodule BeaconAssistantWeb.ChatLiveTest do
  use BeaconAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    previous = Application.get_env(:beacon_assistant, :chatbot_complete)

    Application.put_env(:beacon_assistant, :chatbot_complete, fn _prompt ->
      {:ok, "Billing is handled from the knowledge base."}
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
