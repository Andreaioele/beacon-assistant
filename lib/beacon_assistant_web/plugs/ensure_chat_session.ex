defmodule BeaconAssistantWeb.Plugs.EnsureChatSession do
  @moduledoc """
  Ensures each browser session has an anonymous chat session id.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :chat_session_id) do
      session_id when is_binary(session_id) and session_id != "" ->
        conn

      _missing ->
        put_session(conn, :chat_session_id, Ecto.UUID.generate())
    end
  end
end
