defmodule BeaconAssistant.Chatbot do
  @moduledoc """
  Orchestrates support-question handling.

  Real grounding, LLM calls, and persistence are intentionally not implemented in the
  initial scaffold.
  """

  def ask(_question) do
    {:error, :not_implemented}
  end
end
