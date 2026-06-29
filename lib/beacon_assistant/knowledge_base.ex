defmodule BeaconAssistant.KnowledgeBase do
  @moduledoc """
  Loads Beacon Markdown help-center documents from the configured knowledge-base folder.
  """

  def list_documents do
    knowledge_base_dir()
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
  end

  def knowledge_base_dir do
    System.get_env("KNOWLEDGE_BASE_DIR") ||
      Application.app_dir(:beacon_assistant, "priv/knowledge_base")
  end
end
