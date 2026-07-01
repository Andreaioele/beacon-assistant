# Beacon Support Assistant

Beacon Support Assistant is a Phoenix LiveView web app that answers support questions using a local Markdown knowledge base, a configurable LLM provider, and PostgreSQL for storing sessions, messages, and metrics.

The project is designed for two modes:

- local development with Docker, PostgreSQL, and Ollama on the developer machine;
- production on Railway, with a Docker image, Railway PostgreSQL, and an opt-in OpenAI provider.

## Stack

- Elixir and Phoenix 1.8
- Phoenix LiveView
- Ecto and PostgreSQL
- Req for HTTP calls to LLM providers
- Docker and Docker Compose for the local environment
- Railway for deployment and managed database hosting

## Local Setup In A Few Steps

Prerequisites:

- Docker Desktop running
- Ollama installed and running only if you want to test real answers from the local model

Start Ollama and pull the model used by Docker Compose:

```bash
ollama serve
ollama pull qwen3-coder:30b
```

From a new shell, enter the project and Start the app and database:

```bash
docker compose up --build -d
```

This command builds the Phoenix release, starts PostgreSQL, waits for the database to become healthy, runs migrations with `/app/bin/migrate`, and then starts the web server with `/app/bin/server`.

Verify that everything is running:

```bash
docker compose ps
docker compose exec -T db pg_isready -U postgres -d beacon_assistant_dev
curl -i http://localhost:4000/health
curl -i http://localhost:4000/
```

Open the app:

```text
http://localhost:4000
```

To read logs:

```bash
docker compose logs -f app
```

To stop the environment:

```bash
docker compose down
```

## Project Settings

### 1. Local Docker Configuration

The `docker-compose.yml` file contains all values required to run locally:

- `PHX_SERVER=true` enables the server in the Phoenix release.
- `PHX_HOST=localhost` sets the local host.
- `PORT=4000` exposes the app at `http://localhost:4000`.
- `DATABASE_URL=ecto://postgres:postgres@db:5432/beacon_assistant_dev` connects the app to the Docker `db` service.
- `SECRET_KEY_BASE` is a local value that is not used in production.
- `LLM_PROVIDER=ollama` uses Ollama as the local provider.
- `OLLAMA_GENERATE_URL=http://host.docker.internal:11434/api/generate` lets the container reach Ollama on the host machine.
- `OLLAMA_MODEL=qwen3-coder:30b` must match a model pulled with `ollama pull`.

You do not need to copy `.env.example` for the standard Docker flow.

### 2. Local Shell Configuration Without Docker

Docker is the recommended flow. If you want to use Phoenix commands directly on your machine, copy `.env.example` and load the variables:

```bash
cp .env.example .env
set -a
source .env
set +a
```

Then install dependencies, prepare the database, and start the server:

```bash
mix setup
mix phx.server
```

This mode requires Elixir, Erlang, local PostgreSQL, and the asset toolchain to be available on your machine.

### 3. LLM Configuration

The LLM provider is selected through `LLM_PROVIDER`:

- `ollama`: uses `OLLAMA_GENERATE_URL`, `OLLAMA_MODEL`, and `OLLAMA_TIMEOUT_MS`.
- `openai`: uses `OPENAI_RESPONSES_URL`, `LLM_API_KEY`, `LLM_MODEL`, `LLM_FALLBACK_MODEL`, and `LLM_TIMEOUT_MS`.

The code does not silently fall back between providers. If a required variable is missing, the request fails in a controlled way and an exchange with status `failed` is stored when a chat session exists.

### 4. Railway Configuration

Railway uses `railway.toml`:

- builder: `DOCKERFILE`
- pre-deploy: `/app/bin/migrate`
- start: `/app/bin/server`
- healthcheck: `GET /health`

Required variables for the web service:

```text
DATABASE_URL=${{Postgres.DATABASE_URL}}
SECRET_KEY_BASE=<generated-with-mix-phx.gen.secret>
PHX_SERVER=true
LLM_PROVIDER=openai
LLM_API_KEY=<openai-api-key>
LLM_MODEL=<primary-openai-model>
LLM_FALLBACK_MODEL=<fallback-openai-model>
OPENAI_RESPONSES_URL=https://api.openai.com/v1/responses
LLM_TIMEOUT_MS=15000
```

Railway provides `PORT` and `RAILWAY_PUBLIC_DOMAIN`. `config/runtime.exs` uses `PHX_HOST`, then `RAILWAY_PUBLIC_DOMAIN`, then `example.com` as a fallback.

## Useful Commands

```bash
docker compose up --build -d
docker compose ps
docker compose logs -f app
docker compose exec -T db psql -U postgres -d beacon_assistant_dev -c "\\dt"
docker compose down
```

Phoenix commands without Docker:

```bash
mix deps.get
mix ecto.setup
mix test
mix format
mix precommit
```

## Application Flow

The main flow is:

1. The browser opens `/`.
2. `BeaconAssistantWeb.Plugs.EnsureChatSession` ensures the HTTP session has an anonymous `chat_session_id`.
3. `BeaconAssistantWeb.ChatLive` loads previous exchanges for that session.
4. The user sends a question.
5. `BeaconAssistantWeb.ChatLive` immediately appends the user's question and an empty assistant bubble.
6. A supervised task calls `BeaconAssistant.Chatbot.ask_stream/2`, which normalizes the question, builds the context from the knowledge base, prepares the grounded prompt, and calls `BeaconAssistant.LLMClient`.
7. The LLM client streams chunks from Ollama or OpenAI based on configuration.
8. The chatbot extracts only the JSON `answer` text while chunks arrive and sends visible answer deltas back to LiveView.
9. When generation finishes, the chatbot validates the final JSON response and filters the sources declared by the model against the documents that were actually loaded.
10. `BeaconAssistant.Conversations` stores the final question, answer, sources, status, provider, model, and metrics.
11. LiveView replaces the temporary assistant bubble with the persisted final exchange and shows sources.

### Streaming Responses

Chat responses are streamed through the existing LiveView connection. The UI shows the user message and an assistant `Generating...` placeholder immediately, then updates the assistant text as provider chunks arrive. The model still returns the same internal JSON shape, `{"answer":"...","sources":["filename.md"]}`, but the UI streams only the decoded `answer` field so users never see raw JSON. Sources are hidden during generation and shown only after the final response is parsed and validated.

The synchronous `Chatbot.ask/2` and `LLMClient.complete_with_metadata/2` paths remain available for compatibility and tests. The interactive chat uses `Chatbot.ask_stream/2` and `LLMClient.stream_with_metadata/2`.

`GET /health` is outside the browser pipeline. It returns `200 OK` without touching the database, session, knowledge base, or LLM, so Railway can use it as a lightweight liveness check.

## Error Handling

The chat flow handles expected and unexpected failures without crashing the LiveView process.

- Browser offline: the client checks `navigator.onLine` and sends network status updates to LiveView. When the browser is offline, the form is disabled and the app shows: `You appear to be offline. Connect to the internet before sending a request.` No chatbot or LLM request is started while the client is offline.
- Model timeout: LLM timeout reasons are normalized as `:model_timeout`. The failed exchange is shown with: `The model is taking too long to respond. Please try again.`
- Knowledge base unavailable or empty: the chatbot does not call the LLM and returns the knowledge-base fallback answer.
- Critical errors: malformed provider responses, provider HTTP errors, missing provider configuration, unexpected module exceptions, and persistence failures are caught and normalized. The user sees: `Something went wrong. Please try again later.`

Technical error reasons are logged and stored on failed exchanges when available. The UI never exposes provider response bodies, stack traces, request payloads, API keys, or raw runtime errors.

## Technical And Architectural Decisions

- Phoenix LiveView avoids a separate SPA and keeps UI, session handling, and persistence in a single Elixir runtime.
- PostgreSQL stores conversations and metrics so provider errors, answers, and token/cost behavior are debuggable.
- The knowledge base stays in Markdown files so updates are simple and reviewable.
- The prompt is grounded: the model must answer only from the provided context and return JSON with `answer` and `sources`.
- Chat generation is streamed to the browser over LiveView, while only completed or failed final exchanges are persisted.
- Ollama is the local default to reduce cost and avoid API key dependency during development.
- OpenAI is opt-in for production or cloud testing, configured only through environment variables.
- Error handling is split by responsibility: browser connectivity is detected in the client before a request is sent, while server-side provider, knowledge-base, parsing, and persistence failures are normalized inside the application layer before they reach LiveView.
- The Docker release runs migrations at runtime, not during image build, to avoid tying images to a specific database state.
- Production HTTP binds to IPv4 `0.0.0.0`, which is required to publish the port correctly both in local Docker and on Railway.

## Database

Migrations live in `priv/repo/migrations/`. The current application schema has two main tables.

### `chat_sessions`

Represents an anonymous browser session.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | Primary key generated by the app or database |
| `started_at` | `utc_datetime_usec` | Logical session creation time |
| `last_seen_at` | `utc_datetime_usec` | Updated when the session is reused |
| `conversation_title` | `string` | First 80 characters of the first useful question |
| `metadata` | `map` | JSON space for future attributes |
| `inserted_at` | `utc_datetime_usec` | Ecto timestamp |
| `updated_at` | `utc_datetime_usec` | Ecto timestamp |

### `chat_exchanges`

Represents a single question-answer exchange.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | Primary key |
| `chat_session_id` | `uuid` | Foreign key to `chat_sessions`, `on_delete: :delete_all` |
| `question` | `text` | User question, required |
| `answer` | `text` | Assistant answer or fallback |
| `status` | `string` | `completed` or `failed` |
| `error_reason` | `string` | Serialized reason when an error occurs |
| `sources` | `text[]` | Markdown files used in the answer |
| `provider` | `string` | `ollama` or `openai` |
| `model_name` | `string` | Model that was actually called |
| `input_tokens` | `integer` | Input tokens, when available |
| `output_tokens` | `integer` | Output tokens, when available |
| `total_tokens` | `integer` | Sum or provider value |
| `response_time_ms` | `integer` | LLM call duration |
| `prompt_bytes` | `integer` | Size of the prompt sent to the provider |
| `provider_request_id` | `string` | Provider request id, when available |
| `metadata` | `map` | Includes values such as `fallback_used` |
| `inserted_at` | `utc_datetime_usec` | Ecto timestamp |
| `updated_at` | `utc_datetime_usec` | Ecto timestamp |

Indexes:

- `chat_exchanges(chat_session_id, inserted_at)` to rebuild conversation history.
- `chat_exchanges(status)` for error analysis.
- `chat_exchanges(model_name)` for per-model analysis.
- `chat_exchanges(provider_request_id)` to correlate local logs with provider requests.

## Project Modules

### Core Application

- `BeaconAssistant.Application`: starts the supervision tree, repo, endpoint, telemetry, DNS cluster, and chat task supervisor.
- `BeaconAssistant.Repo`: Ecto boundary for PostgreSQL.
- `BeaconAssistant.Conversations`: persistence API for sessions and exchanges.
- `BeaconAssistant.Conversations.ChatSession`: Ecto schema for anonymous sessions.
- `BeaconAssistant.Conversations.ChatExchange`: Ecto schema for question-answer exchanges and metrics.
- `BeaconAssistant.KnowledgeBase`: Markdown document loader and context builder.
- `BeaconAssistant.Chatbot`: orchestrates question handling, prompt generation, streaming LLM calls, visible answer deltas, parsing, source validation, and persistence.
- `BeaconAssistant.LLMClient`: HTTP boundary for Ollama/OpenAI, streaming and non-streaming response parsing, metrics, and OpenAI fallback model handling.
- `BeaconAssistant.Release`: runtime task module for migrations in Docker/Railway releases.

### Web

- `BeaconAssistantWeb.Router`: routing, browser pipeline, and `/health` endpoint.
- `BeaconAssistantWeb.Plugs.EnsureChatSession`: creates an anonymous UUID in the session when missing.
- `BeaconAssistantWeb.ChatLive`: chat UI, history loading, streaming answer updates, and question submission.
- `BeaconAssistantWeb.HealthController`: minimal liveness check.
- `BeaconAssistantWeb.Endpoint`: Phoenix endpoint configuration, LiveView socket, and static assets.
- `BeaconAssistantWeb.Telemetry`: standard Phoenix metrics.
- `BeaconAssistantWeb.Components`: generated Phoenix components and layouts.

## Knowledge Base Algorithm

Source documents live in `priv/knowledge_base/` and are `.md` files.

`BeaconAssistant.KnowledgeBase.build_context/1` runs these steps:

1. Determine the directory:
   - first `KNOWLEDGE_BASE_DIR`;
   - then `Application.get_env(:beacon_assistant, :knowledge_base_dir)`;
   - finally `Application.app_dir(:beacon_assistant, "priv/knowledge_base")`, which also works inside the Docker release.
2. Look for `*.md` files only.
3. Sort paths alphabetically to keep prompts deterministic.
4. Read every file from disk on each request. In local development, Markdown changes are therefore visible immediately without a restart.
5. Extract the title from the first Markdown `# Title` line; if missing, use the filename without extension.
6. Build a single context by separating each document with markers:

```text
--- BEGIN DOCUMENT: 01-getting-started.md ---
...
--- END DOCUMENT: 01-getting-started.md ---
```

7. Return the context text, the loaded document list, and the filename list allowed as sources.

If there are no Markdown documents, the chatbot does not call the LLM provider and uses this fallback:

```text
I'm not able to retrieve that information from the available knowledge base.
```

The prompt generated by `BeaconAssistant.Chatbot.build_prompt/2` requires the model to:

- use only the provided context;
- not invent policies, prices, or procedures;
- return JSON only in the shape `{"answer":"...","sources":["filename.md"]}`;
- use empty sources when the answer is the fallback.

After the response, `Chatbot` validates sources: only filenames that actually exist in the loaded knowledge base are kept. This prevents the model from citing files that do not exist.

## LLM Provider

### Ollama

Payload sent:

```json
{
  "model": "qwen3-coder:30b",
  "prompt": "...",
  "stream": true
}
```

Streaming responses arrive as newline-delimited JSON chunks. Each chunk can contain a `response` delta; the final `done=true` chunk can include token metrics such as `prompt_eval_count` and `eval_count`.

### OpenAI Responses API

Payload sent:

```json
{
  "model": "<LLM_MODEL>",
  "input": "...",
  "stream": true
}
```

Streaming responses arrive as server-sent events. Text deltas are read from `response.output_text.delta`; completion metadata is read from `response.completed`, including `usage.input_tokens`, `usage.output_tokens`, and `usage.total_tokens` when available.

If the primary model is unavailable and `LLM_FALLBACK_MODEL` is set, the client retries once with the fallback model and stores `fallback_used=true` in metadata.

## Knowledge Base

Current files:

- `01-getting-started.md`
- `02-plans-and-pricing.md`
- `03-billing-and-refunds.md`
- `04-account-and-security.md`
- `05-data-and-integrations.md`

Practical rules:

- add new content as `.md` files in `priv/knowledge_base/`;
- use sortable names, for example `06-topic.md`;
- start each file with a `#` heading;
- do not add secrets or real customer data;
- update or add tests if you change the format expected by the loader.

## Tests

Full Phoenix test suite:

```bash
mix test
```

Local precommit:

```bash
mix precommit
```

Essential Docker verification:

```bash
docker compose up --build -d
docker compose exec -T db pg_isready -U postgres -d beacon_assistant_dev
curl -i http://localhost:4000/health
curl -i http://localhost:4000/
```

## Troubleshooting

### `curl http://localhost:4000/health` does not respond

Check status and logs:

```bash
docker compose ps
docker compose logs app
```

If the container is restarting, the most likely cause is a missing runtime variable or a database connection error.

### The local model does not respond

Verify Ollama on the host machine:

```bash
ollama list
curl http://localhost:11434/api/tags
```

The model in `OLLAMA_MODEL` must be available locally and `ollama serve` must be running.

### The local database looks dirty

To delete local project data and the local volume:

```bash
docker compose down -v
docker compose up --build -d
```

Use this only if you can lose locally saved conversations.

### Railway fails before startup

Check these variables first:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_SERVER`
- `LLM_PROVIDER`
- `LLM_API_KEY`
- `LLM_MODEL`
- `OPENAI_RESPONSES_URL`

`DATABASE_URL` must be a Railway reference to the Postgres service, for example `${{Postgres.DATABASE_URL}}`, not a manually copied URL.
