---
name: deployment-checklist
description: Check Beacon Support Assistant deployment readiness or debug production deployment issues. Use before deploy, after deploy, or when public Phoenix LiveView app, PostgreSQL, migrations, environment variables, knowledge-base files, or LLM provider configuration may be broken.
---

# Deployment Checklist

## Pre-Deploy

Verify:

- app runs locally with `mix phx.server`;
- `mix format` has run;
- `mix test` passes or failures are documented;
- PostgreSQL migrations exist;
- Markdown knowledge-base files are included in the repo/release;
- runtime config reads environment variables;
- no API keys or secrets are committed;
- README includes local setup and production notes.

## Required Production Config

Check deployment platform has:

- `DATABASE_URL` or platform equivalent;
- `SECRET_KEY_BASE`;
- LLM provider API key;
- LLM model name if configurable;
- Phoenix host/port configuration if needed.

## Database

Verify:

- database exists;
- migrations have run;
- exchange table exists;
- successful user questions persist;
- failed LLM attempts persist.

Expected table shape from `AGENTS.md`:

```text
chat_exchanges
- question: text
- answer: text
- status: completed | failed
- error_message: text
- sources: jsonb or array
- latency_ms: integer
```

## Runtime Smoke Test

On public URL:

1. Open app.
2. Ask a question answerable from Markdown docs.
3. Confirm grounded answer.
4. Ask a question not covered by docs.
5. Confirm assistant says docs lack enough information.
6. Confirm no invented Beacon policies.
7. Confirm loading state clears.
8. Confirm persistence if DB access is available.

## Common Production Failures

Check for:

- missing `SECRET_KEY_BASE`;
- missing or invalid LLM API key;
- database connection error;
- migrations not run;
- knowledge-base files missing from release;
- wrong Phoenix host or port;
- timeout too short or too long.

## Output

Return pass/fail checklist, blockers, non-blocking improvements, and exact commands when useful. Do not add features while doing deploy readiness review.
