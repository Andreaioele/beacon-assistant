---
name: elixir-architecture-review
description: Review Beacon Support Assistant Elixir/Phoenix code for architecture boundaries, MVP scope, failure handling, and idiomatic maintainability. Use before finalizing implementation tasks, when reviewing diffs, or when checking whether LiveView, chatbot, knowledge base, LLM client, and persistence responsibilities stayed separate.
---

# Elixir Architecture Review

## Review Order

1. Confirm the feature works end-to-end.
2. Check boundaries from `AGENTS.md`.
3. Confirm LLM and grounding logic are not mixed into LiveView.
4. Confirm user-facing flows do not raise unhandled exceptions.
5. Check that code stays small, readable, and MVP-scoped.
6. Check tests and documentation for the touched behavior.

## Boundaries

```text
lib/beacon_assistant_web/
  LiveView, components, routing, rendering, browser events

lib/beacon_assistant/
  chatbot orchestration, knowledge base, prompt building, LLM client, persistence contexts
```

LiveView should call application-level functions. It should not implement full chat orchestration, direct HTTP provider calls, Markdown loading, prompt construction, or direct database writes.

## Elixir Checks

Verify:

- function names are clear;
- pattern matching is readable;
- `case` handles success and error paths;
- fallible functions return `{:ok, value}` or `{:error, reason}` where useful;
- user-facing flows avoid unsafe `!` calls unless intentionally safe;
- long functions are split into private helpers;
- modules have narrow responsibilities;
- no unused aliases/imports or dead code remain;
- `mix format` passes;
- `mix test` passes if tests exist.

## Beacon MVP Checks

Reject scope creep unless explicitly requested:

- no pgvector, embeddings, LangChain, or vector database for MVP;
- no separate frontend app;
- no authentication, user accounts, multi-tenancy, or admin upload panel;
- no streaming or multi-turn memory before the core deployed flow works.

Prefer a small complete implementation over a larger incomplete one.

## Review Output

When reporting a review, lead with blocking issues by severity and include file/line references. Then list open questions, test gaps, and a short summary. If no issues are found, say that clearly and mention remaining risk.
