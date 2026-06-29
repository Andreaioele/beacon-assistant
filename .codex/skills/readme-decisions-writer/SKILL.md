---
name: readme-decisions-writer
description: Create or update Beacon Support Assistant README.md and DECISIONS.md so documentation matches the current Phoenix LiveView app, grounding strategy, persistence model, deployment state, LLM failure handling, limitations, and AI-agent usage. Use whenever project documentation is added or changed.
---

# README and Decisions Writer

## Rule

Read `AGENTS.md` and inspect actual code before documenting behavior. Do not document features that are not implemented.

## README Requirements

Include:

- project name and short description;
- live application URL or honest placeholder if not deployed;
- stack: Elixir, Phoenix, LiveView, PostgreSQL, chosen LLM provider, Markdown knowledge base;
- local requirements;
- required environment variables such as `DATABASE_URL`, `SECRET_KEY_BASE`, LLM API key, and model name if configurable;
- setup commands:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

- test command:

```bash
mix test
```

- chat flow overview;
- how Markdown knowledge base loading works;
- how prompt grounding works;
- why embeddings/vector database were not used for MVP;
- how LLM failures are handled;
- data model summary;
- known limitations;
- improvements with more time;
- concise note about AI agent usage.

## DECISIONS.md Requirements

Use sections like:

```markdown
# Decisions

## Scope
## Architecture
## Grounding strategy
## Persistence
## LLM provider
## Failure handling
## Deployment
## Deliberately excluded
## Known limitations
## Future improvements
```

Explain direct Markdown prompt grounding with this rationale when accurate:

```text
The provided knowledge base is intentionally small and the project scope allows prompt-based grounding without embeddings or a vector database. I chose direct Markdown prompt grounding to keep the solution inspectable, simple, and aligned with the MVP scope.
```

## Tone

Use clear engineering documentation. Avoid marketing tone, vague claims, and interview/client references unless explicitly requested.

## Consistency Checks

Before finishing, compare docs against code for:

- module names;
- environment variable names;
- migration/table names;
- LLM provider choice;
- deploy URL/status;
- test commands;
- known limitations.
