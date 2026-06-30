defmodule BeaconAssistant.LLMClientTest do
  use ExUnit.Case, async: true

  alias BeaconAssistant.LLMClient

  test "returns answer from Ollama response body" do
    parent = self()

    http_client = fn url, opts ->
      send(parent, {:request, url, opts})
      {:ok, %Req.Response{status: 200, body: %{"response" => " Answer. "}}}
    end

    assert {:ok, "Answer."} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "ollama",
               model: "qwen3:14b"
             )

    assert_received {:request, "http://localhost:11434/api/generate", opts}
    assert opts[:json].model == "qwen3:14b"
    assert opts[:json].stream == false
    assert opts[:json].prompt == "prompt"
  end

  test "falls back to Ollama when provider is unset or not openai" do
    parent = self()

    http_client = fn url, _opts ->
      send(parent, {:url, url})
      {:ok, %Req.Response{status: 200, body: %{"response" => "local answer"}}}
    end

    assert {:ok, "local answer"} =
             LLMClient.complete("prompt", http_client: http_client, provider: nil)

    assert_received {:url, "http://localhost:11434/api/generate"}

    assert {:ok, "local answer"} =
             LLMClient.complete("prompt", http_client: http_client, provider: "anything-else")

    assert_received {:url, "http://localhost:11434/api/generate"}
  end

  test "sends OpenAI Responses API request when provider is openai" do
    parent = self()

    http_client = fn url, opts ->
      send(parent, {:request, url, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "output" => [
             %{"content" => [%{"type" => "output_text", "text" => " OpenAI answer. "}]}
           ]
         }
       }}
    end

    assert {:ok, "OpenAI answer."} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "gpt-test",
               fallback_model: "fallback-test",
               timeout_ms: 12_345
             )

    assert_received {:request, "https://api.openai.com/v1/responses", opts}
    assert opts[:headers] == [{"authorization", "Bearer test-key"}]
    assert opts[:json] == %{model: "gpt-test", input: "prompt"}
    assert opts[:receive_timeout] == 12_345
    refute_received {:request, _url, _opts}
  end

  test "retries OpenAI request with fallback model when primary model is unavailable" do
    parent = self()

    http_client = fn url, opts ->
      send(parent, {:request, url, opts})

      case opts[:json].model do
        "primary-test" ->
          {:ok,
           %Req.Response{
             status: 404,
             body: %{"error" => %{"code" => "model_not_found"}}
           }}

        "fallback-test" ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "output" => [
                 %{"content" => [%{"type" => "output_text", "text" => " Fallback answer. "}]}
               ]
             }
           }}
      end
    end

    assert {:ok, "Fallback answer."} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "primary-test",
               fallback_model: "fallback-test"
             )

    assert_received {:request, "https://api.openai.com/v1/responses", primary_opts}
    assert primary_opts[:json] == %{model: "primary-test", input: "prompt"}

    assert_received {:request, "https://api.openai.com/v1/responses", fallback_opts}
    assert fallback_opts[:json] == %{model: "fallback-test", input: "prompt"}
  end

  test "does not retry OpenAI model unavailable response when fallback model is blank" do
    parent = self()

    http_client = fn _url, opts ->
      send(parent, {:model, opts[:json].model})
      {:ok, %Req.Response{status: 404, body: %{"error" => %{"code" => "model_not_found"}}}}
    end

    assert {:error, {:model_unavailable, 404}} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "primary-test",
               fallback_model: " "
             )

    assert_received {:model, "primary-test"}
    refute_received {:model, _fallback_model}
  end

  test "returns fallback error when OpenAI fallback model also fails" do
    parent = self()

    http_client = fn _url, opts ->
      send(parent, {:model, opts[:json].model})

      case opts[:json].model do
        "primary-test" ->
          {:ok, %Req.Response{status: 404, body: %{"error" => %{"code" => "model_not_found"}}}}

        "fallback-test" ->
          {:ok, %Req.Response{status: 500, body: %{"error" => "down"}}}
      end
    end

    assert {:error, {:http_error, 500}} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "primary-test",
               fallback_model: "fallback-test"
             )

    assert_received {:model, "primary-test"}
    assert_received {:model, "fallback-test"}
  end

  test "requires OpenAI API key and model" do
    http_client = fn _url, _opts -> flunk("OpenAI request should not be sent") end

    assert {:error, :missing_api_key} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               model: "gpt-test"
             )

    assert {:error, :missing_model} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key"
             )
  end

  test "handles non success status" do
    http_client = fn _url, _opts ->
      {:ok, %Req.Response{status: 500, body: %{"error" => "down"}}}
    end

    assert {:error, {:http_error, 500}} =
             LLMClient.complete("prompt", http_client: http_client, provider: "ollama")

    assert {:error, {:http_error, 500}} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "gpt-test"
             )
  end

  test "does not retry OpenAI errors unrelated to model availability" do
    assert_openai_no_fallback(
      {:ok, %Req.Response{status: 401, body: %{"error" => "unauthorized"}}},
      {:error, {:http_error, 401}}
    )

    assert_openai_no_fallback(
      {:ok, %Req.Response{status: 429, body: %{"error" => "rate limited"}}},
      {:error, {:http_error, 429}}
    )

    assert_openai_no_fallback(
      {:ok, %Req.Response{status: 500, body: %{"error" => "down"}}},
      {:error, {:http_error, 500}}
    )

    assert_openai_no_fallback(
      {:ok, %Req.Response{status: 200, body: %{"id" => "resp_123"}}},
      {:error, :malformed_response}
    )

    assert_openai_no_fallback(
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"output" => [%{"content" => [%{"type" => "output_text", "text" => " "}]}]}
       }},
      {:error, :empty_response}
    )

    assert_openai_no_fallback({:error, :timeout}, {:error, :timeout})
  end

  test "handles client errors" do
    http_client = fn _url, _opts -> {:error, :timeout} end

    assert {:error, :timeout} =
             LLMClient.complete("prompt", http_client: http_client, provider: "ollama")

    assert {:error, :timeout} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "gpt-test"
             )
  end

  test "handles malformed and empty Ollama responses" do
    malformed = fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{"done" => true}}} end
    empty = fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{"response" => " "}}} end

    assert {:error, :malformed_response} =
             LLMClient.complete("prompt", http_client: malformed, provider: "ollama")

    assert {:error, :empty_response} =
             LLMClient.complete("prompt", http_client: empty, provider: "ollama")
  end

  test "handles malformed and empty OpenAI responses" do
    malformed = fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: %{"id" => "resp_123"}}}
    end

    empty = fn _url, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"output" => [%{"content" => [%{"type" => "output_text", "text" => " "}]}]}
       }}
    end

    openai_opts = [provider: "openai", api_key: "test-key", model: "gpt-test"]

    assert {:error, :malformed_response} =
             LLMClient.complete("prompt", Keyword.merge(openai_opts, http_client: malformed))

    assert {:error, :empty_response} =
             LLMClient.complete("prompt", Keyword.merge(openai_opts, http_client: empty))
  end

  test "does not use fallback model for Ollama provider" do
    parent = self()

    http_client = fn _url, opts ->
      send(parent, {:request, opts})
      {:ok, %Req.Response{status: 200, body: %{"response" => "local answer"}}}
    end

    assert {:ok, "local answer"} =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "ollama",
               model: "qwen3:14b",
               fallback_model: "fallback-test"
             )

    assert_received {:request, opts}
    assert opts[:json].model == "qwen3:14b"
    refute opts[:json].model == "fallback-test"
  end

  defp assert_openai_no_fallback(http_response, expected_result) do
    parent = self()

    http_client = fn _url, opts ->
      send(parent, {:model, opts[:json].model})
      http_response
    end

    assert ^expected_result =
             LLMClient.complete("prompt",
               http_client: http_client,
               provider: "openai",
               api_key: "test-key",
               model: "primary-test",
               fallback_model: "fallback-test"
             )

    assert_received {:model, "primary-test"}
    refute_received {:model, "fallback-test"}
  end
end
