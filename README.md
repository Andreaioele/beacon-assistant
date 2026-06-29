# Beacon Support Assistant

Phoenix LiveView scaffold for a Beacon support assistant backed by PostgreSQL.

This app provides a Phoenix LiveView chat UI backed by PostgreSQL and a configurable LLM provider. Local runs default to Ollama, while production can opt into OpenAI with environment variables.

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

By default the app calls a local Ollama server:

```bash
ollama serve
ollama pull qwen3:14b
```

The default Ollama endpoint is:

```text
http://localhost:11434/api/generate
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

Docker runs also default to Ollama. The compose file points the app container at:

```text
http://host.docker.internal:11434
```

Keep Ollama running on the host machine before asking questions through the containerized app.

## Railway

Railway deploy config lives in `railway.toml` and uses the project `Dockerfile`.
Railway health checks use `GET /health`, which returns a lightweight `200 OK`
when the web process is reachable. This endpoint intentionally does not check
PostgreSQL, the knowledge base, or the LLM provider.

Expected Railway services:

- Web service from this repository.
- PostgreSQL service connected to the web service.

Required web service variables:

- `DATABASE_URL` from the Railway PostgreSQL service.
- `SECRET_KEY_BASE` generated with `mix phx.gen.secret`.
- `PHX_SERVER=true`.
- `LLM_PROVIDER=openai`.
- `LLM_API_KEY` with the OpenAI API key.
- `LLM_MODEL` with the OpenAI model name.
- `LLM_TIMEOUT_MS=15000`.
- `KNOWLEDGE_BASE_DIR=/app/knowledge-base`.

Railway should provide `PORT` and `RAILWAY_PUBLIC_DOMAIN`.

Local Railway CLI/MCP auth placeholder:

```bash
export RAILWAY_TOKEN=replace-with-railway-token
```

## Environment

Copy `.env.example` for local shell usage if needed. Do not commit real secrets.

LLM provider behavior:

- Missing `LLM_PROVIDER`, or any value other than `openai`, uses Ollama.
- `LLM_PROVIDER=openai` calls the OpenAI Responses API.
- OpenAI requires both `LLM_API_KEY` and `LLM_MODEL`.
- Ollama can be customized with `OLLAMA_BASE_URL`, `OLLAMA_GENERATE_URL`, `OLLAMA_MODEL`, and `OLLAMA_TIMEOUT_MS`.

Required for production:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `RAILWAY_TOKEN` for local Railway CLI/MCP operations
- `LLM_PROVIDER=openai`
- `LLM_API_KEY`
- `LLM_MODEL`
- `LLM_TIMEOUT_MS`
- `KNOWLEDGE_BASE_DIR`

## Project Boundaries

- `BeaconAssistantWeb.ChatLive` owns the LiveView UI shell.
- `BeaconAssistant.Chatbot` will orchestrate question handling.
- `BeaconAssistant.KnowledgeBase` will load Markdown documents.
- `BeaconAssistant.LLMClient` routes to OpenAI or Ollama based on `LLM_PROVIDER`.
- `BeaconAssistant.Conversations` will own exchange persistence.

Markdown help-center files belong in `priv/knowledge_base/` for local source runs or `knowledge-base/` for Docker runs.

## Decisions

- **Local & Production LLMs**: We used a local model via Ollama for zero-cost local testing and development. In production, we use an API key for a cloud model (GPT-5 Nano) which offers an excellent cost-to-performance ratio. This choice was dictated by the need to balance costs and the required performance.
- **Dynamic Configuration**: The choice of the LLM provider and model is completely dynamic and controlled via environment variables. This ensures that if we ever want to switch models or providers in the future, we only need to update the configuration without modifying the code.
- **Hosting**: We chose Railway as our hosting provider because it allows us to deploy the application and integrate a PostgreSQL database with just a few clicks.
