defmodule BeaconAssistant.LLMClient do
  @moduledoc """
  Boundary for future bring-your-own-key LLM provider calls.
  """

  def complete(_prompt) do
    {:error, :not_configured}
  end
end
