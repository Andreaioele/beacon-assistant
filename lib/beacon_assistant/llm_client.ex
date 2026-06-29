defmodule BeaconAssistant.LLMClient do
  @moduledoc """
  Boundary for Ollama completion calls.
  """

  @default_model "qwen3:14b"
  @default_base_url "http://localhost:11434"
  @default_timeout_ms 120_000

  require Logger

  def complete(prompt, opts \\ []) when is_binary(prompt) do
    http_client = Keyword.get(opts, :http_client, &Req.post/2)
    endpoint = Keyword.get(opts, :endpoint, endpoint())
    model = Keyword.get(opts, :model, model())
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_ms())

    request_opts = [
      json: %{
        model: model,
        prompt: prompt,
        stream: false
      },
      receive_timeout: timeout_ms
    ]

    Logger.info(
      "llm_client.complete request endpoint=#{endpoint} model=#{model} prompt_bytes=#{byte_size(prompt)} timeout_ms=#{timeout_ms}"
    )

    case http_client.(endpoint, request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Logger.info("llm_client.complete response status=#{status}")
        parse_success_body(body)

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
  rescue
    exception ->
      Logger.error("llm_client.complete raised error=#{Exception.message(exception)}")
      {:error, :llm_request_failed}
  end

  defp parse_success_body(%{"response" => response}) when is_binary(response) do
    answer = String.trim(response)

    if answer == "" do
      Logger.error("llm_client.complete empty_response")
      {:error, :empty_response}
    else
      {:ok, answer}
    end
  end

  defp parse_success_body(body) do
    Logger.error("llm_client.complete malformed_response body=#{inspect(body)}")
    {:error, :malformed_response}
  end

  defp endpoint do
    generate_url =
      System.get_env("OLLAMA_GENERATE_URL") ||
        Application.get_env(:beacon_assistant, :ollama_generate_url)

    if generate_url do
      String.trim_trailing(generate_url, "/")
    else
      base_url =
        System.get_env("OLLAMA_BASE_URL") ||
          Application.get_env(:beacon_assistant, :ollama_base_url) ||
          @default_base_url

      base_url
      |> String.trim_trailing("/")
      |> String.replace_suffix("/v1", "")
      |> Kernel.<>("/api/generate")
    end
  end

  defp model do
    System.get_env("OLLAMA_MODEL") ||
      Application.get_env(:beacon_assistant, :ollama_model) ||
      @default_model
  end

  defp timeout_ms do
    case System.get_env("OLLAMA_TIMEOUT_MS") do
      nil -> Application.get_env(:beacon_assistant, :ollama_timeout_ms, @default_timeout_ms)
      value -> parse_timeout(value)
    end
  end

  defp parse_timeout(value) do
    case Integer.parse(value) do
      {timeout, ""} when timeout > 0 -> timeout
      _ -> @default_timeout_ms
    end
  end
end
