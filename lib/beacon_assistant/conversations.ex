defmodule BeaconAssistant.Conversations do
  @moduledoc """
  Boundary for chat session and exchange persistence.
  """

  import Ecto.Query

  alias BeaconAssistant.Conversations.{ChatExchange, ChatSession}
  alias BeaconAssistant.Repo

  def get_or_create_session(session_id) when is_binary(session_id) do
    case Repo.get(ChatSession, session_id) do
      nil -> create_session(session_id)
      session -> touch_session(session)
    end
  end

  def touch_session(%ChatSession{} = session) do
    session
    |> ChatSession.changeset(%{last_seen_at: now()})
    |> Repo.update()
  end

  def maybe_set_conversation_title(%ChatSession{conversation_title: title} = session, _question)
      when is_binary(title) and title != "" do
    {:ok, session}
  end

  def maybe_set_conversation_title(%ChatSession{} = session, question) when is_binary(question) do
    session
    |> ChatSession.title_changeset(%{conversation_title: title_from_question(question)})
    |> Repo.update()
  end

  def create_exchange(attrs) when is_map(attrs) do
    %ChatExchange{}
    |> ChatExchange.changeset(attrs)
    |> Repo.insert()
  end

  def list_exchanges do
    Repo.all(from e in ChatExchange, order_by: [asc: e.inserted_at])
  end

  def list_exchanges_for_session(session_id) when is_binary(session_id) do
    Repo.all(
      from e in ChatExchange,
        where: e.chat_session_id == ^session_id,
        order_by: [asc: e.inserted_at, asc: e.id]
    )
  end

  defp create_session(session_id) do
    timestamp = now()

    %ChatSession{}
    |> ChatSession.changeset(%{
      id: session_id,
      started_at: timestamp,
      last_seen_at: timestamp,
      metadata: %{}
    })
    |> Repo.insert()
  end

  defp title_from_question(question) do
    question
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 80)
  end

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond)
  end
end
