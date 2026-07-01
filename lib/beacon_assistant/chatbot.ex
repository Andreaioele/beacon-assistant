defmodule BeaconAssistant.Chatbot do
  @moduledoc """
  Orchestrates grounded support-question handling.
  """

  alias BeaconAssistant.{Conversations, ErrorHandling, KnowledgeBase, LLMClient}

  require Logger

  @knowledge_base_fallback ErrorHandling.knowledge_base_message()

  def ask(question, opts \\ []) when is_binary(question) do
    question = String.trim(question)

    if question == "" do
      {:error, :empty_question}
    else
      answer_question(question, opts)
    end
  end

  def ask_stream(question, opts \\ []) when is_binary(question) do
    question = String.trim(question)

    if question == "" do
      {:error, :empty_question}
    else
      answer_question_stream(question, opts)
    end
  end

  def fallback_message(:knowledge_base), do: @knowledge_base_fallback
  def fallback_message(:llm), do: ErrorHandling.critical_message()
  def fallback_message(:model_timeout), do: ErrorHandling.model_timeout_message()
  def fallback_message(:critical), do: ErrorHandling.critical_message()

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
    - Return a JSON object only, with this exact shape:
      {"answer":"...","sources":["filename.md"]}
    - Answer only from the context above.
    - Do not guess.
    - Do not invent Beacon policies, pricing, billing behavior, security behavior, or support procedures.
    - If the answer is not present, use the exact fallback sentence above.
    - Include only document filenames actually used to answer in sources.
    - If the answer is the fallback sentence, sources must be an empty array.
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
        Application.get_env(
          :beacon_assistant,
          :chatbot_complete,
          &LLMClient.complete_with_metadata/1
        )
      )

    chat_session_id = Keyword.get(opts, :chat_session_id)

    Logger.info("chatbot.ask started question=#{inspect(question)}")

    with {:ok, %{context: context, sources: available_sources}} <-
           ErrorHandling.safe_call("chatbot.build_context", build_context),
         prompt <- build_prompt(question, context),
         {:ok, raw_answer, metrics} <- call_complete(complete, prompt),
         {:ok, %{answer: answer, sources: sources}} <-
           parse_completion(raw_answer, available_sources) do
      Logger.info(
        "chatbot.ask completed sources=#{inspect(sources)} answer_bytes=#{byte_size(answer)}"
      )

      exchange = %{
        question: question,
        answer: answer,
        status: :completed,
        sources: sources
      }

      maybe_persist_exchange(chat_session_id, exchange, metrics)
    else
      {:error, :no_knowledge_base_documents} ->
        Logger.warning("chatbot.ask no knowledge base documents")

        exchange = failed_exchange(question, :knowledge_base, :no_knowledge_base_documents)

        maybe_persist_exchange(chat_session_id, exchange, %{})

      {:error, reason} ->
        Logger.error("chatbot.ask LLM failed reason=#{inspect(reason)}")

        exchange = failed_exchange(question, ErrorHandling.classify(reason), reason)
        maybe_persist_exchange(chat_session_id, exchange, %{})

      {:error, reason, metrics} ->
        Logger.error("chatbot.ask LLM failed reason=#{inspect(reason)}")

        exchange = failed_exchange(question, ErrorHandling.classify(reason), reason)
        maybe_persist_exchange(chat_session_id, exchange, metrics)
    end
  end

  defp answer_question_stream(question, opts) do
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
        :stream,
        Application.get_env(
          :beacon_assistant,
          :chatbot_stream,
          &LLMClient.stream_with_metadata/2
        )
      )

    on_delta = Keyword.get(opts, :on_delta, fn _delta -> :ok end)
    chat_session_id = Keyword.get(opts, :chat_session_id)

    Logger.info("chatbot.ask_stream started question=#{inspect(question)}")

    with {:ok, %{context: context, sources: available_sources}} <-
           ErrorHandling.safe_call("chatbot.build_context", build_context),
         prompt <- build_prompt(question, context),
         {:ok, raw_answer, metrics} <- call_stream(complete, prompt, on_delta),
         {:ok, %{answer: answer, sources: sources}} <-
           parse_completion(raw_answer, available_sources) do
      Logger.info(
        "chatbot.ask_stream completed sources=#{inspect(sources)} answer_bytes=#{byte_size(answer)}"
      )

      exchange = %{
        question: question,
        answer: answer,
        status: :completed,
        sources: sources
      }

      maybe_persist_exchange(chat_session_id, exchange, metrics)
    else
      {:error, :no_knowledge_base_documents} ->
        Logger.warning("chatbot.ask_stream no knowledge base documents")

        exchange = failed_exchange(question, :knowledge_base, :no_knowledge_base_documents)

        maybe_persist_exchange(chat_session_id, exchange, %{})

      {:error, reason} ->
        Logger.error("chatbot.ask_stream LLM failed reason=#{inspect(reason)}")

        exchange = failed_exchange(question, ErrorHandling.classify(reason), reason)
        maybe_persist_exchange(chat_session_id, exchange, %{})

      {:error, reason, metrics} ->
        Logger.error("chatbot.ask_stream LLM failed reason=#{inspect(reason)}")

        exchange = failed_exchange(question, ErrorHandling.classify(reason), reason)
        maybe_persist_exchange(chat_session_id, exchange, metrics)
    end
  end

  defp call_complete(complete, prompt) do
    case ErrorHandling.safe_call("chatbot.complete", fn -> complete.(prompt) end) do
      {:ok, %{answer: answer} = metadata} when is_binary(answer) ->
        {:ok, answer, Map.delete(metadata, :answer)}

      {:ok, answer} when is_binary(answer) ->
        {:ok, answer, %{}}

      {:error, reason, metadata} ->
        {:error, reason, metadata}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :critical}
    end
  end

  defp call_stream(complete, prompt, on_delta) do
    visible_state = %{raw: "", answer: ""}

    stream_delta = fn raw_delta ->
      visible_state =
        Process.get(:chatbot_visible_stream_state, visible_state)
        |> Map.update!(:raw, &(&1 <> raw_delta))
        |> emit_visible_answer_delta(on_delta)

      Process.put(:chatbot_visible_stream_state, visible_state)
      :ok
    end

    Process.put(:chatbot_visible_stream_state, visible_state)

    result =
      ErrorHandling.safe_call("chatbot.stream", fn ->
        complete.(prompt, on_delta: stream_delta)
      end)

    Process.delete(:chatbot_visible_stream_state)

    case result do
      {:ok, %{answer: answer} = metadata} when is_binary(answer) ->
        {:ok, answer, Map.delete(metadata, :answer)}

      {:ok, answer} when is_binary(answer) ->
        {:ok, answer, %{}}

      {:error, reason, metadata} ->
        {:error, reason, metadata}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :critical}
    end
  end

  defp emit_visible_answer_delta(%{raw: raw, answer: previous_answer} = state, on_delta) do
    answer = answer_prefix(raw)

    if String.starts_with?(answer, previous_answer) do
      delta = String.replace_prefix(answer, previous_answer, "")

      if delta != "" do
        on_delta.(delta)
      end

      %{state | answer: answer}
    else
      state
    end
  end

  defp answer_prefix(raw) do
    case Regex.run(~r/"answer"\s*:\s*"/, raw, return: :index) do
      [{start, length}] ->
        offset = start + length
        json_string = binary_part(raw, offset, byte_size(raw) - offset)
        decode_json_string_prefix(json_string)

      _other ->
        ""
    end
  end

  defp decode_json_string_prefix(json_string) do
    json_string
    |> do_decode_json_string_prefix([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_decode_json_string_prefix("", acc), do: acc
  defp do_decode_json_string_prefix(<<"\"", _rest::binary>>, acc), do: acc
  defp do_decode_json_string_prefix("\\", acc), do: acc

  defp do_decode_json_string_prefix(<<"\\u", hex::binary-size(4), rest::binary>>, acc) do
    case Integer.parse(hex, 16) do
      {codepoint, ""} -> do_decode_json_string_prefix(rest, [<<codepoint::utf8>> | acc])
      _other -> acc
    end
  end

  defp do_decode_json_string_prefix(<<"\\u", _rest::binary>>, acc), do: acc

  defp do_decode_json_string_prefix(<<"\\", escaped, rest::binary>>, acc) do
    decoded =
      case escaped do
        ?" -> "\""
        ?\\ -> "\\"
        ?/ -> "/"
        ?b -> "\b"
        ?f -> "\f"
        ?n -> "\n"
        ?r -> "\r"
        ?t -> "\t"
        _other -> <<escaped>>
      end

    do_decode_json_string_prefix(rest, [decoded | acc])
  end

  defp do_decode_json_string_prefix(<<char::utf8, rest::binary>>, acc) do
    do_decode_json_string_prefix(rest, [<<char::utf8>> | acc])
  end

  defp parse_completion(raw_answer, available_sources) do
    result =
      case Jason.decode(raw_answer) do
        {:ok, %{"answer" => answer} = body} when is_binary(answer) ->
          answer = String.trim(answer)

          %{
            answer: answer,
            sources: validated_sources(answer, Map.get(body, "sources", []), available_sources)
          }

        _other ->
          Logger.warning("chatbot.ask unstructured_answer using_empty_sources")
          %{answer: raw_answer, sources: []}
      end

    {:ok, result}
  rescue
    exception ->
      Logger.error("chatbot.parse_completion failed error=#{Exception.message(exception)}")
      {:error, :critical}
  end

  defp validated_sources(answer, _declared_sources, _available_sources)
       when answer == @knowledge_base_fallback do
    []
  end

  defp validated_sources(_answer, declared_sources, available_sources)
       when is_list(declared_sources) do
    available_sources = MapSet.new(available_sources)

    declared_sources
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&MapSet.member?(available_sources, &1))
    |> Enum.uniq()
  end

  defp validated_sources(_answer, _declared_sources, _available_sources), do: []

  defp maybe_persist_exchange(nil, exchange, _metrics), do: {:ok, exchange}
  defp maybe_persist_exchange("", exchange, _metrics), do: {:ok, exchange}

  defp maybe_persist_exchange(chat_session_id, exchange, metrics) do
    case persist_exchange(chat_session_id, exchange, metrics) do
      {:ok, persisted_exchange} ->
        {:ok, persisted_exchange}

      {:error, reason} ->
        Logger.error("chatbot.persist_exchange failed reason=#{inspect(reason)}")
        {:ok, exchange}
    end
  end

  defp persist_exchange(chat_session_id, exchange, metrics) do
    with {:ok, session} <-
           ErrorHandling.safe_call("chatbot.get_or_create_session", fn ->
             Conversations.get_or_create_session(chat_session_id)
           end),
         {:ok, _session} <-
           ErrorHandling.safe_call("chatbot.maybe_set_conversation_title", fn ->
             Conversations.maybe_set_conversation_title(session, exchange.question)
           end),
         {:ok, persisted_exchange} <-
           ErrorHandling.safe_call("chatbot.create_exchange", fn ->
             Conversations.create_exchange(
               persisted_exchange_attrs(session.id, exchange, metrics)
             )
           end) do
      {:ok, persisted_exchange}
    end
  end

  defp persisted_exchange_attrs(chat_session_id, exchange, metrics) do
    %{
      chat_session_id: chat_session_id,
      question: exchange.question,
      answer: exchange.answer,
      status: exchange.status |> to_string(),
      error_reason: exchange[:error] && inspect(exchange.error),
      sources: exchange.sources,
      provider: metrics[:provider],
      model_name: metrics[:model_name],
      input_tokens: metrics[:input_tokens],
      output_tokens: metrics[:output_tokens],
      total_tokens: metrics[:total_tokens],
      response_time_ms: metrics[:response_time_ms],
      prompt_bytes: metrics[:prompt_bytes],
      provider_request_id: metrics[:provider_request_id],
      metadata: Map.take(metrics, [:fallback_used])
    }
  end

  defp failed_exchange(question, category, reason) do
    %{
      question: question,
      answer: ErrorHandling.user_message(category),
      status: :failed,
      error: reason,
      error_category: category,
      sources: []
    }
  end
end
