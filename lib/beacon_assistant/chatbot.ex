defmodule BeaconAssistant.Chatbot do
  @moduledoc """
  Orchestrates grounded support-question handling.
  """

  alias BeaconAssistant.{KnowledgeBase, LLMClient}

  require Logger

  @knowledge_base_fallback "I'm not able to retrieve that information from the available knowledge base."
  @llm_fallback "Sorry, I couldn't generate an answer right now. Please try again."

  def ask(question, opts \\ []) when is_binary(question) do
    question = String.trim(question)

    if question == "" do
      {:error, :empty_question}
    else
      answer_question(question, opts)
    end
  end

  def fallback_message(:knowledge_base), do: @knowledge_base_fallback
  def fallback_message(:llm), do: @llm_fallback

  def build_prompt(question, context) do
    """
    You are Beacon's support assistant.
    Answer customer questions using only the provided Beacon help-center context.
    Do not use outside knowledge.
    If the context does not contain enough information to answer, say exactly:
    "#{@knowledge_base_fallback}"
    Be concise, precise, and helpful.

    Beacon help-center context:

    #{context}

    Customer question:
    #{question}

    Instructions:
    - Answer only from the context above.
    - Do not guess.
    - Do not invent Beacon policies, pricing, billing behavior, security behavior, or support procedures.
    - If the answer is not present, use the exact fallback sentence above.
    - Prefer a direct answer over a long explanation.
    """
    |> String.trim()
  end

  defp answer_question(question, opts) do
    build_context =
      Keyword.get(
        opts,
        :build_context,
        Application.get_env(
          :beacon_assistant,
          :chatbot_build_context,
          &KnowledgeBase.build_context/0
        )
      )

    complete =
      Keyword.get(
        opts,
        :complete,
        Application.get_env(:beacon_assistant, :chatbot_complete, &LLMClient.complete/1)
      )

    Logger.info("chatbot.ask started question=#{inspect(question)}")

    with {:ok, %{context: context, sources: sources}} <- build_context.(),
         prompt <- build_prompt(question, context),
         {:ok, answer} <- complete.(prompt) do
      Logger.info(
        "chatbot.ask completed sources=#{inspect(sources)} answer_bytes=#{byte_size(answer)}"
      )

      {:ok,
       %{
         question: question,
         answer: answer,
         status: :completed,
         sources: sources
       }}
    else
      {:error, :no_knowledge_base_documents} ->
        Logger.warning("chatbot.ask no knowledge base documents")
        {:ok, failed_exchange(question, @knowledge_base_fallback, :no_knowledge_base_documents)}

      {:error, reason} ->
        Logger.error("chatbot.ask LLM failed reason=#{inspect(reason)}")
        {:ok, failed_exchange(question, @llm_fallback, :llm_error)}
    end
  end

  defp failed_exchange(question, answer, reason) do
    %{
      question: question,
      answer: answer,
      status: :failed,
      error: reason,
      sources: []
    }
  end
end
