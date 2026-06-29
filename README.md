# Beacon Support Assistant

Phoenix LiveView scaffold for a Beacon support assistant backed by PostgreSQL.

This initial setup only creates the application shell, domain module boundaries, an empty Markdown knowledge-base folder, and local configuration placeholders. It does not include real LLM integration or chat persistence yet.

## Stack

- Elixir
- Phoenix LiveView
- Ecto
- PostgreSQL

## Local Setup

Install dependencies:

```bash
mix deps.get
```

Create and migrate the local database:

```bash
mix ecto.setup
```

Run the app:

```bash
mix phx.server
```

Open:

```text
http://localhost:4000
```

Run tests:

```bash
mix test
```

## Docker

Build and run the app with PostgreSQL:

```bash
docker compose up --build
```

The app is available at:

```text
http://localhost:4000
```

The database is exposed at:

```text
localhost:5432
```

The local `knowledge-base/` folder is mounted into the app container at `/app/knowledge-base`.
Put Markdown help-center files there for containerized runs.

## Environment

Copy `.env.example` for local shell usage if needed. Do not commit real secrets.

Required later for production:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `LLM_PROVIDER`
- `LLM_API_KEY`
- `LLM_MODEL`
- `LLM_TIMEOUT_MS`
- `KNOWLEDGE_BASE_DIR`

## Project Boundaries

- `BeaconAssistantWeb.ChatLive` owns the LiveView UI shell.
- `BeaconAssistant.Chatbot` will orchestrate question handling.
- `BeaconAssistant.KnowledgeBase` will load Markdown documents.
- `BeaconAssistant.LLMClient` will call the configured LLM provider.
- `BeaconAssistant.Conversations` will own exchange persistence.

Markdown help-center files belong in `priv/knowledge_base/` for local source runs or `knowledge-base/` for Docker runs.
