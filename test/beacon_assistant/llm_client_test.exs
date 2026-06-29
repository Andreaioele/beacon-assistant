defmodule BeaconAssistant.LLMClientTest do
  use ExUnit.Case, async: true

  alias BeaconAssistant.LLMClient

  test "returns answer from Ollama response body" do
    parent = self()

    http_client = fn _url, opts ->
      send(parent, {:request_opts, opts})
      {:ok, %Req.Response{status: 200, body: %{"response" => " Answer. "}}}
    end

    assert {:ok, "Answer."} =
             LLMClient.complete("prompt", http_client: http_client, model: "qwen3:14b")

    assert_received {:request_opts, opts}
    assert opts[:json].model == "qwen3:14b"
    assert opts[:json].stream == false
    assert opts[:json].prompt == "prompt"
  end

  test "handles non success status" do
    http_client = fn _url, _opts ->
      {:ok, %Req.Response{status: 500, body: %{"error" => "down"}}}
    end

    assert {:error, {:http_error, 500}} = LLMClient.complete("prompt", http_client: http_client)
  end

  test "handles client errors" do
    http_client = fn _url, _opts -> {:error, :timeout} end

    assert {:error, :timeout} = LLMClient.complete("prompt", http_client: http_client)
  end

  test "handles malformed and empty responses" do
    malformed = fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{"done" => true}}} end
    empty = fn _url, _opts -> {:ok, %Req.Response{status: 200, body: %{"response" => " "}}} end

    assert {:error, :malformed_response} = LLMClient.complete("prompt", http_client: malformed)
    assert {:error, :empty_response} = LLMClient.complete("prompt", http_client: empty)
  end
end
