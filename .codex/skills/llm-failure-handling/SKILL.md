---
name: llm-failure-handling
description: Implement or review Beacon Support Assistant LLM provider integration, prompt grounding, response parsing, timeout behavior, and chat failure states. Use for LLM clients, prompt builders, chatbot orchestration, persistence of failed attempts, and preventing provider errors from crashing LiveView.
---

# LLM Failure Handling

## Required Outcome

Every user question must produce one of:

```elixir
{:ok, persisted_exchange}
{:error, persisted_failed_exchange}
```

The user must see either a grounded assistant answer or this fallback:

```text
Sorry, I couldn't generate an answer right now. Please try again.
```

Persist both successful answers and failed attempts in PostgreSQL. Never lose the question because the provider failed.

## LLM Client Contract

LLM functions should return:

```elixir
{:ok, answer}
{:error, reason}
```

Do not let provider exceptions, HTTP client errors, malformed responses, or missing config leak into LiveView.

Handle:

- missing or invalid API key;
- HTTP 401, 429, 500, and other non-2xx statuses;
- network failure;
- timeout;
- malformed JSON;
- empty body;
- unexpected response shape;
- empty assistant text;
- unexpected exceptions during HTTP calls.

Normalize internal error reasons for logs or persistence. Do not expose stack traces, API keys, raw request bodies, provider request IDs, or sensitive config in the UI.

## Grounding Rules

Use one LLM call per user question. Prompt must require:

- answer only from Beacon Markdown context;
- no outside knowledge;
- no invented Beacon policies, pricing, billing behavior, security behavior, or support procedures;
- if context is insufficient, say the Beacon help docs do not contain enough information;
- concise, direct answers.

Do not add embeddings, vector search, reranking calls, validation calls, or intent-detection model calls unless explicitly requested.

## Persistence Rules

For success, save:

- question;
- answer;
- status: `completed`;
- sources used if available;
- latency if implemented.

For failure, save:

- question;
- fallback answer;
- status: `failed`;
- normalized error message;
- sources: empty list unless context was still selected;
- latency if implemented.

## Verification

Test or manually verify successful answer, missing API key, timeout/provider error, malformed/empty response, loading state cleanup, and failed-attempt persistence.
