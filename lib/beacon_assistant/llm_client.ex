defmodule BeaconAssistant.LLMClient do
  @moduledoc """
  Boundary for LLM completion calls.
  """

  @default_provider "ollama"
  @default_ollama_model "qwen3:14b"
  @default_ollama_base_url "http://localhost:11434"
  @default_openai_endpoint "https://api.openai.com/v1/responses"
  @default_timeout_ms 120_000

  require Logger

  def complete(prompt, opts \\ []) when is_binary(prompt) do
    http_client = Keyword.get(opts, :http_client, &Req.post/2)

    case provider(opts) do
      "openai" -> complete_openai(prompt, http_client, opts)
      _provider -> complete_ollama(prompt, http_client, opts)
    end
  rescue
    exception ->
      Logger.error("llm_client.complete raised error=#{Exception.message(exception)}")
      {:error, :llm_request_failed}
  end

  defp complete_openai(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, openai_endpoint())
    model = Keyword.get(opts, :model, openai_model())
    api_key = Keyword.get(opts, :api_key, openai_api_key())
    timeout_ms = Keyword.get(opts, :timeout_ms, llm_timeout_ms())

    cond do
      blank?(api_key) ->
        Logger.error("llm_client.complete missing OpenAI API key")
        {:error, :missing_api_key}

      blank?(model) ->
        Logger.error("llm_client.complete missing OpenAI model")
        {:error, :missing_model}

      true ->
        request_opts = [
          headers: [{"authorization", "Bearer #{api_key}"}],
          json: %{model: model, input: prompt},
          receive_timeout: timeout_ms
        ]

        Logger.info(
          "llm_client.complete request provider=openai endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
        )

        request_completion(http_client, endpoint, request_opts, &parse_openai_success_body/1)
    end
  end

  defp complete_ollama(prompt, http_client, opts) do
    endpoint = Keyword.get(opts, :endpoint, ollama_endpoint())
    model = Keyword.get(opts, :model, ollama_model())
    timeout_ms = Keyword.get(opts, :timeout_ms, ollama_timeout_ms())

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

    request_completion(http_client, endpoint, request_opts, &parse_ollama_success_body/1)
  end

  defp request_completion(http_client, endpoint, request_opts, parse_success_body) do
    case http_client.(endpoint, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Logger.info("llm_client.complete response status=#{status}")
        parse_success_body.(body)

      {:ok, %Req.Response{status: status}} ->
        Logger.error("llm_client.complete http_error status=#{status}")
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("llm_client.complete transport_error reason=#{inspect(reason)}")
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        Logger.error("llm_client.complete client_error reason=#{inspect(reason)}")
        {:error, reason}

      _other ->
        Logger.error("llm_client.complete unexpected_response")
        {:error, :unexpected_response}
    end
  end

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

  defp provider(opts) do
    opts
    |> Keyword.get(
      :provider,
      System.get_env("LLM_PROVIDER") || llm_config(:provider) || @default_provider
    )
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp openai_endpoint do
    System.get_env("OPENAI_RESPONSES_URL") ||
      llm_config(:openai_responses_url) ||
      @default_openai_endpoint
  end

  defp openai_api_key do
    System.get_env("LLM_API_KEY") || llm_config(:api_key)
  end

  defp openai_model do
    System.get_env("LLM_MODEL") || llm_config(:model)
  end

  defp ollama_endpoint do
    generate_url =
      System.get_env("OLLAMA_GENERATE_URL") ||
        Application.get_env(:beacon_assistant, :ollama_generate_url)

    if generate_url do
      String.trim_trailing(generate_url, "/")
    else
      base_url =
        System.get_env("OLLAMA_BASE_URL") ||
          Application.get_env(:beacon_assistant, :ollama_base_url) ||
          @default_ollama_base_url

      base_url
      |> String.trim_trailing("/")
      |> String.replace_suffix("/v1", "")
      |> Kernel.<>("/api/generate")
    end
  end

  defp ollama_model do
    System.get_env("OLLAMA_MODEL") ||
      Application.get_env(:beacon_assistant, :ollama_model) ||
      @default_ollama_model
  end

  defp ollama_timeout_ms do
    case System.get_env("OLLAMA_TIMEOUT_MS") do
      nil -> Application.get_env(:beacon_assistant, :ollama_timeout_ms, @default_timeout_ms)
      value -> parse_timeout(value)
    end
  end

  defp llm_timeout_ms do
    case System.get_env("LLM_TIMEOUT_MS") || llm_config(:timeout_ms) do
      nil -> @default_timeout_ms
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      value -> parse_timeout(to_string(value))
    end
  end

  defp llm_config(key) do
    :beacon_assistant
    |> Application.get_env(:llm, [])
    |> Keyword.get(key)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(value), do: is_nil(value)

  defp parse_timeout(value) do
    case Integer.parse(value) do
      {timeout, ""} when timeout > 0 -> timeout
      _ -> @default_timeout_ms
    end
  end
end
