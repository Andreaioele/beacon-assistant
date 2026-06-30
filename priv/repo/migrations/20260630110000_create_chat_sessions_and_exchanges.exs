defmodule BeaconAssistant.Repo.Migrations.CreateChatSessionsAndExchanges do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :started_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :conversation_title, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:chat_exchanges, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :chat_session_id, references(:chat_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :question, :text, null: false
      add :answer, :text
      add :status, :string, null: false
      add :error_reason, :string
      add :sources, {:array, :string}, null: false, default: []
      add :provider, :string
      add :model_name, :string
      add :input_tokens, :integer
      add :output_tokens, :integer
      add :total_tokens, :integer
      add :response_time_ms, :integer
      add :prompt_bytes, :integer
      add :provider_request_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_exchanges, [:chat_session_id, :inserted_at])
    create index(:chat_exchanges, [:status])
    create index(:chat_exchanges, [:model_name])
    create index(:chat_exchanges, [:provider_request_id])
  end
end
