defmodule BeaconAssistant.KnowledgeBase do
  @moduledoc """
  Loads Beacon Markdown help-center documents from the configured knowledge-base folder.

  The loader intentionally reads from disk on every call so edits to Markdown files
  are reflected immediately during local iteration.
  """

  defmodule Document do
    @moduledoc false

    defstruct [:filename, :title, :content]
  end

  require Logger

  def list_documents do
    knowledge_base_dir()
    |> markdown_paths()
    |> Enum.map(&Path.basename/1)
  end

  def load_documents(opts \\ []) do
    dir = Keyword.get(opts, :dir, knowledge_base_dir())

    documents =
      dir
      |> markdown_paths()
      |> Enum.map(&read_document/1)

    Logger.info(
      "knowledge_base.load_documents dir=#{dir} count=#{length(documents)} files=#{inspect(Enum.map(documents, & &1.filename))}"
    )

    {:ok, documents}
  rescue
    exception ->
      Logger.error("knowledge_base.load_documents failed error=#{Exception.message(exception)}")
      {:error, :knowledge_base_unavailable}
  end

  def build_context(opts \\ []) do
    with {:ok, documents} <- load_documents(opts),
         false <- documents == [] do
      context =
        documents
        |> Enum.map_join("\n\n", &format_document/1)

      {:ok,
       %{
         context: context,
         documents: documents,
         sources: Enum.map(documents, & &1.filename)
       }}
    else
      true -> {:error, :no_knowledge_base_documents}
      {:error, reason} -> {:error, reason}
    end
  end

  def knowledge_base_dir do
    System.get_env("KNOWLEDGE_BASE_DIR") ||
      Application.get_env(:beacon_assistant, :knowledge_base_dir) ||
      Application.app_dir(:beacon_assistant, "priv/knowledge_base")
  end

  defp markdown_paths(dir) do
    if File.dir?(dir) do
      dir
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.sort()
    else
      []
    end
  end

  defp read_document(path) do
    content = File.read!(path)

    %Document{
      filename: Path.basename(path),
      title: extract_title(content, Path.basename(path)),
      content: content
    }
  end

  defp extract_title(content, fallback) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, title] -> String.trim(title)
      _ -> Path.rootname(fallback)
    end
  end

  defp format_document(%Document{} = document) do
    """
    --- BEGIN DOCUMENT: #{document.filename} ---
    #{String.trim(document.content)}
    --- END DOCUMENT: #{document.filename} ---
    """
    |> String.trim()
  end
end
