---
name: phoenix-liveview-feature
description: Build or modify Phoenix LiveView features for the Beacon Support Assistant. Use for chat UI, forms, loading/error states, source display, and integration between LiveView and Beacon application modules while keeping LLM, Markdown, prompt, and persistence logic out of the web layer.
---

# Phoenix LiveView Feature

## Workflow

1. Read `AGENTS.md` before changing code.
2. Locate the Phoenix app structure before editing.
3. Keep LiveView modules focused on UI state, events, rendering, and user feedback.
4. Delegate business behavior to application modules under `lib/beacon_assistant/`.
5. Run `mix format` after Elixir changes and `mix test` when practical.

## Architecture Rules

Expected web layer:

```text
lib/beacon_assistant_web/
  live/
    chat_live.ex
  components/
```

Expected application layer:

```text
lib/beacon_assistant/
  chatbot.ex
  knowledge_base.ex
  llm_client.ex
  conversations.ex
```

`BeaconAssistantWeb.ChatLive` may call high-level functions such as:

```elixir
BeaconAssistant.Chatbot.ask(question)
BeaconAssistant.Conversations.list_exchanges()
```

Do not call LLM providers, read Markdown files, build long prompts, or run Repo operations directly in LiveView event handlers.

## UI State Rules

Use clear assigns such as:

```elixir
assign(socket,
  exchanges: [],
  loading: false,
  error: nil,
  sources: []
)
```

On submit:

1. Ignore or validate empty questions.
2. Set loading state.
3. Call the application-level chatbot/context function.
4. Append or reload the persisted exchange.
5. Clear the input.
6. Clear loading state on success and failure.

Every user question must produce either a grounded answer or a graceful fallback message. Never leave the UI stuck in loading.

## Scope Rules

Keep UI simple and functional. Do not add authentication, accounts, admin panels, streaming, embeddings, vector search, multi-turn memory, or major visual polish unless explicitly requested and the core app is already complete.

## Verification

Before finishing, verify:

- form submits correctly;
- empty questions are handled;
- user question appears in chat;
- assistant answer or fallback appears in chat;
- loading state clears on success and failure;
- LLM failures do not crash LiveView;
- source filenames render if implemented;
- `mix format` ran after Elixir edits;
- tests were added or updated when reasonable.
