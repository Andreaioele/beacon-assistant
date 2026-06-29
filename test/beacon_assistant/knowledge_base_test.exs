defmodule BeaconAssistant.KnowledgeBaseTest do
  use ExUnit.Case, async: true

  alias BeaconAssistant.KnowledgeBase

  test "loads markdown documents with filename title and content" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "billing.md"), "# Billing\n\nBilling works monthly.")
    File.write!(Path.join(dir, "notes.txt"), "ignore me")

    assert {:ok, [document]} = KnowledgeBase.load_documents(dir: dir)
    assert document.filename == "billing.md"
    assert document.title == "Billing"
    assert document.content =~ "Billing works monthly."
  end

  test "builds context with document delimiters and sources" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "plans.md"), "# Plans\n\nFree, Pro, Business.")

    assert {:ok, result} = KnowledgeBase.build_context(dir: dir)
    assert result.context =~ "--- BEGIN DOCUMENT: plans.md ---"
    assert result.context =~ "Free, Pro, Business."
    assert result.context =~ "--- END DOCUMENT: plans.md ---"
    assert result.sources == ["plans.md"]
  end

  test "reads files on every call" do
    dir = tmp_dir()
    path = Path.join(dir, "security.md")
    File.write!(path, "# Security\n\nOld content.")

    assert {:ok, first} = KnowledgeBase.build_context(dir: dir)
    assert first.context =~ "Old content."

    File.write!(path, "# Security\n\nNew content.")

    assert {:ok, second} = KnowledgeBase.build_context(dir: dir)
    assert second.context =~ "New content."
    refute second.context =~ "Old content."
  end

  test "returns an error when no markdown documents exist" do
    assert {:error, :no_knowledge_base_documents} = KnowledgeBase.build_context(dir: tmp_dir())
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "beacon-kb-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
