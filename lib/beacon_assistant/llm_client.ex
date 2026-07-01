defmodule BeaconAssistant.LLMClient do
  @moduledoc """
  Boundary for LLM completion calls.
  """

  require Logger
  alias BeaconAssistant.ErrorHandling

  def complete(prompt, opts \\ []) when is_binary(prompt) do
    case complete_with_metadata(prompt, opts) do
      {:ok, %{answer: answer}} -> {:ok, answer}
      {:error, reason, _metadata} -> {:error, reason}
    end
  end

  def complete_with_metadata(prompt, opts \\ []) when is_binary(prompt) do
    http_client = Keyword.get(opts, :http_client, &Req.post/2)

    case provider(opts) do
      "" ->
        {:error, :critical, %{prompt_bytes: byte_size(prompt), error_reason: ":missing_provider"}}

      "openai" ->
        complete_openai(prompt, http_client, opts)

      "ollama" ->
        complete_ollama(prompt, http_client, opts)

      provider ->
        {:error, :critical,
         %{
           prompt_bytes: byte_size(prompt),
           error_reason: inspect({:unsupported_provider, provider})
         }}
    end
  rescue
    exception ->
      Logger.error("llm_client.complete raised error=#{Exception.message(exception)}")

      {:error, :critical,
       %{
         prompt_bytes: byte_size(prompt),
         error_reason: inspect({:exception, exception.__struct__})
       }}
  end

  def stream_with_metadata(prompt, opts \\ []) when is_binary(prompt) do
    http_client = Keyword.get(opts, :http_client, &Req.post/2)

    case provider(opts) do
      "" ->
        {:error, :critical, %{prompt_bytes: byte_size(prompt), error_reason: ":missing_provider"}}

      "openai" ->
        stream_openai(prompt, http_client, opts)

      "ollama" ->
        stream_ollama(prompt, http_client, opts)

      provider ->
        {:error, :critical,
         %{
           prompt_bytes: byte_size(prompt),
           error_reason: inspect({:unsupported_provider, provider})
         }}
    end
  rescue
    exception ->
      Logger.error("llm_client.stream raised error=#{Exception.message(exception)}")

      {:error, :critical,
       %{
         prompt_bytes: byte_size(prompt),
         error_reason: inspect({:exception, exception.__struct__})
       }}
  end

  defp complete_openai(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, openai_endpoint())
    model = Keyword.get(opts, :model, openai_model())
    fallback_model = Keyword.get(opts, :fallback_model, openai_fallback_model())
    api_key = Keyword.get(opts, :api_key, openai_api_key())
    timeout_ms = Keyword.get(opts, :timeout_ms, llm_timeout_ms())

    cond do
      blank?(endpoint) ->
        Logger.error("llm_client.complete missing OpenAI endpoint")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_endpoint)}

      blank?(api_key) ->
        Logger.error("llm_client.complete missing OpenAI API key")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_api_key)}

      blank?(model) ->
        Logger.error("llm_client.complete missing OpenAI model")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_model)}

      invalid_timeout?(timeout_ms) ->
        Logger.error("llm_client.complete missing OpenAI timeout")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_timeout)}

      true ->
        case request_openai_completion(
               http_client,
               endpoint,
               prompt,
               api_key,
               model,
               timeout_ms,
               :primary
             ) do
          {:error, reason, _metadata} = error ->
            if model_unavailable_error?(reason) and not blank?(fallback_model) do
              Logger.warning(
                "llm_client.complete primary_model_unavailable model=#{model} fallback_model=#{fallback_model}"
              )

              request_openai_completion(
                http_client,
                endpoint,
                prompt,
                api_key,
                fallback_model,
                timeout_ms,
                :fallback,
                true
              )
              |> ErrorHandling.normalize_llm_result()
            else
              if model_unavailable_error?(reason) do
                Logger.warning(
                  "llm_client.complete primary_model_unavailable_without_fallback model=#{model}"
                )
              end

              ErrorHandling.normalize_llm_result(error)
            end

          result ->
            ErrorHandling.normalize_llm_result(result)
        end
    end
  end

  defp stream_openai(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, openai_endpoint())
    model = Keyword.get(opts, :model, openai_model())
    fallback_model = Keyword.get(opts, :fallback_model, openai_fallback_model())
    api_key = Keyword.get(opts, :api_key, openai_api_key())
    timeout_ms = Keyword.get(opts, :timeout_ms, llm_timeout_ms())

    cond do
      blank?(endpoint) ->
        Logger.error("llm_client.stream missing OpenAI endpoint")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_endpoint)}

      blank?(api_key) ->
        Logger.error("llm_client.stream missing OpenAI API key")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_api_key)}

      blank?(model) ->
        Logger.error("llm_client.stream missing OpenAI model")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_model)}

      invalid_timeout?(timeout_ms) ->
        Logger.error("llm_client.stream missing OpenAI timeout")
        {:error, :critical, error_metadata(:openai, model, prompt, nil, :missing_timeout)}

      true ->
        case request_openai_stream(
               http_client,
               endpoint,
               prompt,
               api_key,
               model,
               timeout_ms,
               opts,
               :primary
             ) do
          {:error, reason, _metadata} = error ->
            if model_unavailable_error?(reason) and not blank?(fallback_model) do
              Logger.warning(
                "llm_client.stream primary_model_unavailable model=#{model} fallback_model=#{fallback_model}"
              )

              request_openai_stream(
                http_client,
                endpoint,
                prompt,
                api_key,
                fallback_model,
                timeout_ms,
                opts,
                :fallback,
                true
              )
              |> ErrorHandling.normalize_llm_result()
            else
              ErrorHandling.normalize_llm_result(error)
            end

          result ->
            ErrorHandling.normalize_llm_result(result)
        end
    end
  end

  defp request_openai_stream(
         http_client,
         endpoint,
         prompt,
         api_key,
         model,
         timeout_ms,
         opts,
         attempt,
         fallback_used \\ false
       ) do
    on_delta = Keyword.get(opts, :on_delta, fn _delta -> :ok end)
    {:ok, state} = start_stream_state()

    request_opts = [
      headers: [{"authorization", "Bearer #{api_key}"}],
      json: %{model: model, input: prompt, stream: true},
      receive_timeout: timeout_ms,
      decode_body: false,
      into: stream_into(state, &consume_openai_stream_chunk/3, on_delta)
    ]

    Logger.info(
      "llm_client.stream request provider=openai attempt=#{attempt} endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
    )

    started_at = System.monotonic_time(:millisecond)

    try do
      case http_client.(endpoint, request_opts) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          Logger.info(
            "llm_client.stream response provider=openai attempt=#{attempt} status=#{status}"
          )

          final_stream_result(
            state,
            :openai,
            model,
            prompt,
            elapsed_ms(started_at),
            fallback_used,
            provider_request_id(response)
          )

        {:ok, %Req.Response{status: status, body: body}} ->
          reason = openai_http_error_reason(status, maybe_decode_json_body(body))

          Logger.error(
            "llm_client.stream http_error provider=openai attempt=#{attempt} status=#{status}"
          )

          metadata =
            base_metadata(:openai, model, prompt, elapsed_ms(started_at))
            |> Map.put(:fallback_used, fallback_used)

          {:error, reason, metadata}

        {:error, %Req.TransportError{reason: reason}} ->
          Logger.error(
            "llm_client.stream transport_error provider=openai attempt=#{attempt} reason=#{inspect(reason)}"
          )

          {:error, {:transport_error, reason},
           base_metadata(:openai, model, prompt, elapsed_ms(started_at))}

        {:error, reason} ->
          Logger.error(
            "llm_client.stream client_error provider=openai attempt=#{attempt} reason=#{inspect(reason)}"
          )

          {:error, reason, base_metadata(:openai, model, prompt, elapsed_ms(started_at))}

        _other ->
          Logger.error("llm_client.stream unexpected_response provider=openai attempt=#{attempt}")

          {:error, :unexpected_response,
           base_metadata(:openai, model, prompt, elapsed_ms(started_at))}
      end
    after
      Agent.stop(state)
    end
  end

  defp request_openai_completion(
         http_client,
         endpoint,
         prompt,
         api_key,
         model,
         timeout_ms,
         attempt,
         fallback_used \\ false
       ) do
    request_opts = [
      headers: [{"authorization", "Bearer #{api_key}"}],
      json: %{model: model, input: prompt},
      receive_timeout: timeout_ms
    ]

    Logger.info(
      "llm_client.complete request provider=openai attempt=#{attempt} endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
    )

    started_at = System.monotonic_time(:millisecond)

    case http_client.(endpoint, request_opts) do
      {:ok, %Req.Response{status: status, body: body} = response} when status in 200..299 ->
        Logger.info(
          "llm_client.complete response provider=openai attempt=#{attempt} status=#{status}"
        )

        metadata =
          base_metadata(:openai, model, prompt, elapsed_ms(started_at))
          |> Map.put(:fallback_used, fallback_used)
          |> Map.merge(openai_usage_metadata(body))
          |> Map.put(:provider_request_id, provider_request_id(response))

        case parse_openai_success_body(body) do
          {:ok, answer} -> {:ok, Map.put(metadata, :answer, answer)}
          {:error, reason} -> {:error, reason, metadata}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        reason = openai_http_error_reason(status, body)

        Logger.error(
          "llm_client.complete http_error provider=openai attempt=#{attempt} status=#{status}"
        )

        metadata =
          base_metadata(:openai, model, prompt, elapsed_ms(started_at))
          |> Map.put(:fallback_used, fallback_used)

        {:error, reason, metadata}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error(
          "llm_client.complete transport_error provider=openai attempt=#{attempt} reason=#{inspect(reason)}"
        )

        {:error, {:transport_error, reason},
         base_metadata(:openai, model, prompt, elapsed_ms(started_at))}

      {:error, reason} ->
        Logger.error(
          "llm_client.complete client_error provider=openai attempt=#{attempt} reason=#{inspect(reason)}"
        )

        {:error, reason, base_metadata(:openai, model, prompt, elapsed_ms(started_at))}

      _other ->
        Logger.error("llm_client.complete unexpected_response provider=openai attempt=#{attempt}")

        {:error, :unexpected_response,
         base_metadata(:openai, model, prompt, elapsed_ms(started_at))}
    end
  end

  defp complete_ollama(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, ollama_endpoint())
    model = Keyword.get(opts, :model, ollama_model())
    timeout_ms = Keyword.get(opts, :timeout_ms, ollama_timeout_ms())

    cond do
      blank?(endpoint) ->
        Logger.error("llm_client.complete missing Ollama endpoint")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_endpoint)}

      blank?(model) ->
        Logger.error("llm_client.complete missing Ollama model")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_model)}

      invalid_timeout?(timeout_ms) ->
        Logger.error("llm_client.complete missing Ollama timeout")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_timeout)}

      true ->
        request_opts = [
          json: %{
            model: model,
            prompt: prompt,
            stream: false
          },
          receive_timeout: timeout_ms
        ]

        Logger.info(
          "llm_client.complete request provider=ollama endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
        )

        request_ollama_completion(http_client, endpoint, request_opts, prompt, model)
    end
  end

  defp stream_ollama(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, ollama_endpoint())
    model = Keyword.get(opts, :model, ollama_model())
    timeout_ms = Keyword.get(opts, :timeout_ms, ollama_timeout_ms())

    cond do
      blank?(endpoint) ->
        Logger.error("llm_client.stream missing Ollama endpoint")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_endpoint)}

      blank?(model) ->
        Logger.error("llm_client.stream missing Ollama model")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_model)}

      invalid_timeout?(timeout_ms) ->
        Logger.error("llm_client.stream missing Ollama timeout")
        {:error, :critical, error_metadata(:ollama, model, prompt, nil, :missing_timeout)}

      true ->
        request_opts = [
          json: %{
            model: model,
            prompt: prompt,
            stream: true
          },
          receive_timeout: timeout_ms,
          decode_body: false
        ]

        Logger.info(
          "llm_client.stream request provider=ollama endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
        )

        request_ollama_stream(http_client, endpoint, request_opts, prompt, model, opts)
    end
  end

  defp request_ollama_stream(http_client, endpoint, request_opts, prompt, model, opts) do
    on_delta = Keyword.get(opts, :on_delta, fn _delta -> :ok end)
    {:ok, state} = start_stream_state()

    request_opts =
      Keyword.put(
        request_opts,
        :into,
        stream_into(state, &consume_ollama_stream_chunk/3, on_delta)
      )

    started_at = System.monotonic_time(:millisecond)

    result =
      try do
        case http_client.(endpoint, request_opts) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            Logger.info("llm_client.stream response provider=ollama status=#{status}")

            final_stream_result(
              state,
              :ollama,
              model,
              prompt,
              elapsed_ms(started_at),
              false,
              nil
            )

          {:ok, %Req.Response{status: status}} ->
            Logger.error("llm_client.stream http_error provider=ollama status=#{status}")

            {:error, {:http_error, status},
             base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

          {:error, %Req.TransportError{reason: reason}} ->
            Logger.error(
              "llm_client.stream transport_error provider=ollama reason=#{inspect(reason)}"
            )

            {:error, {:transport_error, reason},
             base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

          {:error, reason} ->
            Logger.error(
              "llm_client.stream client_error provider=ollama reason=#{inspect(reason)}"
            )

            {:error, reason, base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

          _other ->
            Logger.error("llm_client.stream unexpected_response provider=ollama")

            {:error, :unexpected_response,
             base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}
        end
      after
        Agent.stop(state)
      end

    ErrorHandling.normalize_llm_result(result)
  end

  defp request_ollama_completion(http_client, endpoint, request_opts, prompt, model) do
    started_at = System.monotonic_time(:millisecond)

    case http_client.(endpoint, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Logger.info("llm_client.complete response status=#{status}")

        metadata =
          base_metadata(:ollama, model, prompt, elapsed_ms(started_at))
          |> Map.merge(ollama_usage_metadata(body))

        case parse_ollama_success_body(body) do
          {:ok, answer} -> {:ok, Map.put(metadata, :answer, answer)}
          {:error, reason} -> {:error, reason, metadata}
        end

      {:ok, %Req.Response{status: status}} ->
        Logger.error("llm_client.complete http_error status=#{status}")

        {:error, {:http_error, status},
         base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("llm_client.complete transport_error reason=#{inspect(reason)}")

        {:error, {:transport_error, reason},
         base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

      {:error, reason} ->
        Logger.error("llm_client.complete client_error reason=#{inspect(reason)}")
        {:error, reason, base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}

      _other ->
        Logger.error("llm_client.complete unexpected_response")

        {:error, :unexpected_response,
         base_metadata(:ollama, model, prompt, elapsed_ms(started_at))}
    end
    |> ErrorHandling.normalize_llm_result()
  end

  defp start_stream_state do
    Agent.start_link(fn ->
      %{
        answer: "",
        buffer: "",
        completed?: false,
        error: nil,
        metadata: %{}
      }
    end)
  end

  defp stream_into(state, consume_chunk, on_delta) do
    fn {:data, data}, {request, response} ->
      consume_chunk.(state, data, on_delta)
      {:cont, {request, response}}
    end
  end

  defp consume_ollama_stream_chunk(state, data, on_delta) when is_binary(data) do
    Agent.update(state, fn stream ->
      {lines, buffer} = complete_lines(stream.buffer <> data)

      Enum.reduce(lines, %{stream | buffer: buffer}, fn line, acc ->
        line = String.trim(line)

        if line == "" do
          acc
        else
          case Jason.decode(line) do
            {:ok, body} when is_map(body) ->
              delta = Map.get(body, "response", "")

              if is_binary(delta) and delta != "" do
                on_delta.(delta)
              end

              metadata =
                if Map.get(body, "done") == true do
                  Map.merge(acc.metadata, ollama_usage_metadata(body))
                else
                  acc.metadata
                end

              %{
                acc
                | answer: acc.answer <> if(is_binary(delta), do: delta, else: ""),
                  completed?: acc.completed? or Map.get(body, "done") == true,
                  metadata: metadata
              }

            _other ->
              %{acc | error: :malformed_stream_response}
          end
        end
      end)
    end)
  end

  defp consume_openai_stream_chunk(state, data, on_delta) when is_binary(data) do
    Agent.update(state, fn stream ->
      {events, buffer} = complete_sse_events(stream.buffer <> data)

      Enum.reduce(events, %{stream | buffer: buffer}, fn event, acc ->
        consume_openai_stream_event(acc, event, on_delta)
      end)
    end)
  end

  defp consume_openai_stream_event(stream, event, on_delta) do
    data =
      event
      |> String.split(~r/\r?\n/)
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.trim_leading(String.replace_prefix(&1, "data:", "")))
      |> Enum.join("\n")
      |> String.trim()

    cond do
      data == "" or data == "[DONE]" ->
        stream

      true ->
        case Jason.decode(data) do
          {:ok, %{"type" => "response.output_text.delta", "delta" => delta}}
          when is_binary(delta) ->
            if delta != "" do
              on_delta.(delta)
            end

            %{stream | answer: stream.answer <> delta}

          {:ok, %{"type" => "response.completed", "response" => response}}
          when is_map(response) ->
            metadata =
              stream.metadata
              |> Map.merge(openai_usage_metadata(response))
              |> Map.put(:provider_request_id, body_value(response, "id"))

            %{stream | completed?: true, metadata: metadata}

          {:ok, %{"type" => "response.failed", "response" => response}}
          when is_map(response) ->
            %{stream | error: {:openai_stream_failed, response}}

          {:ok, %{"type" => "error"} = body} ->
            %{stream | error: {:openai_stream_error, body}}

          {:ok, _body} ->
            stream

          {:error, _reason} ->
            %{stream | error: :malformed_stream_response}
        end
    end
  end

  defp final_stream_result(
         state,
         provider,
         model,
         prompt,
         response_time_ms,
         fallback_used,
         request_id
       ) do
    stream = Agent.get(state, & &1)

    cond do
      stream.error ->
        {:error, stream.error,
         base_metadata(provider, model, prompt, response_time_ms)
         |> Map.put(:fallback_used, fallback_used)}

      String.trim(stream.answer) == "" ->
        Logger.error("llm_client.stream empty_response provider=#{provider}")

        {:error, :empty_response,
         base_metadata(provider, model, prompt, response_time_ms)
         |> Map.put(:fallback_used, fallback_used)}

      true ->
        metadata =
          provider
          |> base_metadata(model, prompt, response_time_ms)
          |> Map.put(:fallback_used, fallback_used)
          |> Map.merge(stream.metadata)

        metadata =
          if request_id && is_nil(metadata.provider_request_id) do
            Map.put(metadata, :provider_request_id, request_id)
          else
            metadata
          end

        {:ok, Map.put(metadata, :answer, String.trim(stream.answer))}
    end
  end

  defp complete_lines(buffer) do
    lines = String.split(buffer, "\n")

    if String.ends_with?(buffer, "\n") do
      {lines, ""}
    else
      {Enum.drop(lines, -1), List.last(lines) || ""}
    end
  end

  defp complete_sse_events(buffer) do
    normalized = String.replace(buffer, "\r\n", "\n")
    events = String.split(normalized, "\n\n")

    if String.ends_with?(normalized, "\n\n") do
      {events, ""}
    else
      {Enum.drop(events, -1), List.last(events) || ""}
    end
  end

  defp maybe_decode_json_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp maybe_decode_json_body(body), do: body

  defp parse_ollama_success_body(%{"response" => response}) when is_binary(response) do
    answer = String.trim(response)

    if answer == "" do
      Logger.error("llm_client.complete empty_response")
      {:error, :empty_response}
    else
      {:ok, answer}
    end
  end

  defp parse_ollama_success_body(body) do
    Logger.error("llm_client.complete malformed_response body=#{inspect(body)}")
    {:error, :malformed_response}
  end

  defp parse_openai_success_body(%{"output" => output}) when is_list(output) do
    answer =
      output
      |> Enum.flat_map(fn
        %{"content" => content} when is_list(content) -> content
        _other -> []
      end)
      |> Enum.flat_map(fn
        %{"text" => text} when is_binary(text) -> [text]
        _other -> []
      end)
      |> Enum.join("\n")
      |> String.trim()

    if answer == "" do
      Logger.error("llm_client.complete empty_response")
      {:error, :empty_response}
    else
      {:ok, answer}
    end
  end

  defp parse_openai_success_body(body) do
    Logger.error("llm_client.complete malformed_response body=#{inspect(body)}")
    {:error, :malformed_response}
  end

  defp base_metadata(provider, model, prompt, response_time_ms) do
    %{
      provider: to_string(provider),
      model_name: model,
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      response_time_ms: response_time_ms,
      prompt_bytes: byte_size(prompt),
      provider_request_id: nil,
      fallback_used: false
    }
  end

  defp error_metadata(provider, model, prompt, response_time_ms, reason) do
    provider
    |> base_metadata(model, prompt, response_time_ms)
    |> Map.put(:error_reason, inspect(reason))
  end

  defp openai_usage_metadata(%{"usage" => usage}) when is_map(usage) do
    input_tokens = token_value(usage, ["input_tokens", "prompt_tokens"])
    output_tokens = token_value(usage, ["output_tokens", "completion_tokens"])

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: token_value(usage, ["total_tokens"]) || token_sum(input_tokens, output_tokens)
    }
  end

  defp openai_usage_metadata(_body), do: %{}

  defp ollama_usage_metadata(body) when is_map(body) do
    input_tokens = token_value(body, ["prompt_eval_count"])
    output_tokens = token_value(body, ["eval_count"])

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: token_sum(input_tokens, output_tokens)
    }
  end

  defp ollama_usage_metadata(_body), do: %{}

  defp provider_request_id(%Req.Response{headers: headers, body: body}) do
    header_value(headers, "x-request-id") ||
      header_value(headers, "openai-request-id") ||
      body_value(body, "request_id") ||
      body_value(body, "id")
  end

  defp header_value(headers, key) when is_map(headers) do
    case Map.get(headers, key) || Map.get(headers, String.downcase(key)) do
      [value | _rest] when is_binary(value) -> value
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp header_value(headers, key) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {header_key, value} when is_binary(header_key) ->
        if String.downcase(header_key) == key, do: header_list_value(value)

      _other ->
        nil
    end)
  end

  defp header_value(_headers, _key), do: nil

  defp header_list_value([value | _rest]) when is_binary(value), do: value
  defp header_list_value(value) when is_binary(value), do: value
  defp header_list_value(_value), do: nil

  defp body_value(body, key) when is_map(body) do
    case Map.get(body, key) do
      value when is_binary(value) -> value
      _other -> nil
    end
  end

  defp body_value(_body, _key), do: nil

  defp token_value(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_integer(value) and value >= 0 -> value
        _other -> nil
      end
    end)
  end

  defp token_sum(input_tokens, output_tokens)
       when is_integer(input_tokens) and is_integer(output_tokens) do
    input_tokens + output_tokens
  end

  defp token_sum(_input_tokens, _output_tokens), do: nil

  defp elapsed_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp provider(opts) do
    opts
    |> Keyword.get(
      :provider,
      llm_config(:provider)
    )
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp openai_endpoint do
    llm_config(:openai_responses_url)
  end

  defp openai_api_key do
    llm_config(:api_key)
  end

  defp openai_model do
    llm_config(:model)
  end

  defp openai_fallback_model do
    llm_config(:fallback_model)
  end

  defp openai_http_error_reason(status, body) do
    if openai_model_unavailable?(status, body) do
      {:model_unavailable, status}
    else
      {:http_error, status}
    end
  end

  defp openai_model_unavailable?(404, _body), do: true

  defp openai_model_unavailable?(_status, body) do
    body
    |> inspect()
    |> String.downcase()
    |> then(fn body_text ->
      String.contains?(body_text, "model_not_found") or
        String.contains?(body_text, "model_not_available") or
        String.contains?(body_text, "model unavailable")
    end)
  end

  defp model_unavailable_error?({:model_unavailable, _status}), do: true
  defp model_unavailable_error?(_reason), do: false

  defp ollama_endpoint do
    llm_config(:ollama_generate_url)
  end

  defp ollama_model do
    llm_config(:ollama_model)
  end

  defp ollama_timeout_ms do
    llm_config(:ollama_timeout_ms)
  end

  defp llm_timeout_ms do
    llm_config(:timeout_ms)
  end

  defp llm_config(key) do
    :beacon_assistant
    |> Application.get_env(:llm, [])
    |> Keyword.get(key)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value), do: is_nil(value)

  defp invalid_timeout?(timeout), do: not (is_integer(timeout) and timeout > 0)
end
