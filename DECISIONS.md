# Decisions

This file summarizes the main decisions behind Beacon Support Assistant.

## Scope

I built a small Phoenix LiveView support assistant that answers Beacon customer questions from a Markdown knowledge base.

The focus was a working MVP: chat UI, grounded answers, persisted conversations, safe error handling, and Docker/Railway deployment.

## Phoenix LiveView

I used Phoenix LiveView instead of a separate frontend app.

This keeps the project simpler: UI events, streaming responses, sessions, and persistence stay in one Elixir application. For this challenge, that is easier to run, inspect, and maintain than a separate SPA plus API.

## Markdown Grounding

I used the Markdown files in `priv/knowledge_base/` as direct prompt context.

The knowledge base is small, so embeddings or a vector database would add unnecessary complexity. The tradeoff is that this approach will not scale well to a large document set.

The model is instructed to answer only from the provided context and return:

```json
{"answer":"...","sources":["filename.md"]}
```

The app validates returned source filenames before showing or storing them.

## LLM Provider

The LLM provider is runtime-configurable.

Local Docker uses Ollama by default, so the app can run without an API key. Production can use OpenAI by setting `LLM_PROVIDER=openai` and the required environment variables.

The app does not silently switch providers when config is missing. It fails in a controlled way so configuration problems are visible.

## Persistence

I used PostgreSQL to store anonymous chat sessions and exchanges.

This lets the app keep browser-session history and store useful debugging data: answer status, sources, provider, model, timing, token metrics, and error reason.

## Streaming

Chat answers stream through LiveView.

Users see the answer arrive progressively, but only the final completed or failed exchange is persisted.

## Error Handling

The UI shows safe user-facing messages for offline state, model timeout, missing knowledge base, and unexpected failures.

Technical details are logged and stored when useful, but provider bodies, stack traces, request payloads, and secrets are not shown to users.

## Deployment

Docker Compose runs the app and PostgreSQL locally. Railway uses the same release-style flow with `/app/bin/migrate`, `/app/bin/server`, and `/health`.

`/health` is intentionally lightweight: it only proves the app process is alive and does not call the database, knowledge base, or LLM.

## Deliberately Excluded

I did not add authentication, admin document upload, vector search, analytics dashboards, or a human handoff workflow.

Authentication and user accounts were excluded because the app only needs anonymous browser-session history for the MVP. Adding accounts would require user management, authorization, password/session security, and more testing without improving the core support-answering flow.

Admin document upload was excluded because the knowledge base is small and can be reviewed safely as Markdown files in the repo. This keeps content changes explicit and version-controlled.

Vector search was excluded because direct Markdown grounding is enough for the current document size. A vector database would add ingestion, chunking, embedding, ranking, and operational complexity before it is needed.

Analytics dashboards and human handoff were excluded because they are product extensions. They would be useful in a real support workflow, but the challenge scope is better served by proving the assistant can answer, cite, persist, and handle failures correctly.

## Future Improvements

With more time, I would add scalable retrieval with chunking, embeddings, and metadata-aware ranking. This would make the assistant work better once the knowledge base grows beyond a few Markdown files.

I would also add better answer-quality evaluation: test questions, expected source files, fallback cases, and checks for hallucinated policies or unsupported claims. That would make changes to prompts, models, or documents safer.

For operations, I would add an admin workflow for knowledge-base updates and a small dashboard for failed exchanges, latency, model usage, and source patterns. Those tools would help maintain the system after the MVP without reading logs or querying the database manually.
