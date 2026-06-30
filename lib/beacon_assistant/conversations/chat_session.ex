defmodule BeaconAssistant.Conversations.ChatSession do
  @moduledoc """
  Anonymous browser chat session.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_sessions" do
    field :started_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :conversation_title, :string
    field :metadata, :map, default: %{}

    has_many :exchanges, BeaconAssistant.Conversations.ChatExchange

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:id, :started_at, :last_seen_at, :conversation_title, :metadata])
    |> validate_required([:started_at, :last_seen_at])
  end

  def title_changeset(session, attrs) do
    session
    |> cast(attrs, [:conversation_title])
    |> validate_required([:conversation_title])
  end
end
