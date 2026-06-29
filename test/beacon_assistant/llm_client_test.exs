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
               timeout_ms: 12_345
             )

    assert_received {:request, "https://api.openai.com/v1/responses", opts}
    assert opts[:headers] == [{"authorization", "Bearer test-key"}]
    assert opts[:json] == %{model: "gpt-test", input: "prompt"}
    assert opts[:receive_timeout] == 12_345
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
end
