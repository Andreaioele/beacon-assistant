defmodule BeaconAssistant.Conversations.ChatExchange do
  @moduledoc """
  Persisted question and assistant answer with LLM metrics.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BeaconAssistant.Conversations.ChatSession

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses ~w(completed failed)

  schema "chat_exchanges" do
    field :question, :string
    field :answer, :string
    field :status, :string
    field :error_reason, :string
    field :sources, {:array, :string}, default: []
    field :provider, :string
    field :model_name, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :response_time_ms, :integer
    field :prompt_bytes, :integer
    field :provider_request_id, :string
    field :metadata, :map, default: %{}

    belongs_to :chat_session, ChatSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(exchange, attrs) do
    exchange
    |> cast(attrs, [
      :chat_session_id,
      :question,
      :answer,
      :status,
      :error_reason,
      :sources,
      :provider,
      :model_name,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :response_time_ms,
      :prompt_bytes,
      :provider_request_id,
      :metadata
    ])
    |> validate_required([:chat_session_id, :question, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:chat_session_id)
  end
end
