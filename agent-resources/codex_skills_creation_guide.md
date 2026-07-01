# Codex Skills Creation Guide — Beacon Support Assistant

Questo documento descrive le skill consigliate da creare per Codex durante lo sviluppo del progetto **Beacon Support Assistant**.

L'obiettivo delle skill è guidare Codex in task ricorrenti e delicati, mantenendo il progetto piccolo, funzionante, ben organizzato e coerente con `AGENTS.md`.

## Principio generale

Codex non deve essere lasciato libero di costruire feature non richieste. Ogni skill deve rafforzare questi principi:

1. costruire una slice end-to-end funzionante;
2. mantenere Phoenix LiveView come app unica, senza frontend separato;
3. separare UI, logica applicativa, knowledge base, LLM client e persistenza;
4. evitare overengineering;
5. gestire sempre errori e timeout del modello;
6. aggiornare documentazione e decision log;
7. mantenere una commit history pulita.

## Struttura consigliata delle skill

Puoi creare una cartella dedicata, ad esempio:

```text
.codex/
  skills/
    phoenix-liveview-feature.md
    elixir-architecture-review.md
    llm-failure-handling.md
    readme-decisions-writer.md
    deployment-checklist.md
```

Oppure, se preferisci tenerle visibili nel repository:

```text
docs/
  codex-skills/
    phoenix-liveview-feature.md
    elixir-architecture-review.md
    llm-failure-handling.md
    readme-decisions-writer.md
    deployment-checklist.md
```

La cosa importante è che Codex possa leggerle e che tu possa richiamarle nei prompt.

Esempio:

```text
Use the phoenix-liveview-feature skill. Read AGENTS.md first. Implement the chat LiveView, but keep all LLM and knowledge base logic outside the LiveView.
```

---

# Skill 1 — phoenix-liveview-feature

## File suggerito

```text
.codex/skills/phoenix-liveview-feature.md
```

## Scopo

Usare questa skill quando Codex deve implementare o modificare feature Phoenix LiveView.

È la skill principale per:

- UI chat;
- form LiveView;
- loading state;
- visualizzazione domanda/risposta;
- visualizzazione errori;
- visualizzazione fonti;
- integrazione tra LiveView e moduli applicativi.

## Contenuto consigliato

```md
# Skill: Phoenix LiveView Feature

Use this skill when implementing or modifying Phoenix LiveView features for the Beacon Support Assistant project.

## Primary goal

Build small, working LiveView features that keep the web layer thin and delegate business logic to application modules.

## Mandatory rules

- Read `AGENTS.md` before making changes.
- Keep LiveView focused on UI state, events, rendering, and user feedback.
- Do not put LLM calls inside LiveView modules.
- Do not put Markdown loading or grounding logic inside LiveView modules.
- Do not put database persistence details directly inside LiveView unless calling a context function.
- LiveView should call high-level functions such as:
  - `BeaconAssistant.Chatbot.ask/1`
  - `BeaconAssistant.Conversations.create_exchange/1`
  - `BeaconAssistant.KnowledgeBase.load_context/1`
- Use clear assigns for UI state:
  - `:messages`
  - `:loading`
  - `:error`
  - `:sources`
- Never leave the user stuck in a loading state.
- Every user question must result in either a successful answer or a graceful error message.
- Keep the UI simple and functional. Do not over-polish.

## Expected architecture

The web layer should live under:

```text
lib/beacon_assistant_web/
  live/
    chat_live.ex
  components/
```

Business logic should live under:

```text
lib/beacon_assistant/
  chatbot.ex
  knowledge_base.ex
  llm_client.ex
  conversations.ex
```

## Implementation checklist

Before finishing a LiveView task, verify:

- The form submits correctly.
- Empty questions are ignored or validated.
- The user message appears in the chat.
- The assistant answer appears in the chat.
- Loading state is visible while the request is being processed.
- Loading state is cleared on success and on failure.
- LLM errors are shown gracefully.
- The LiveView does not crash on unexpected errors.
- The code is formatted with `mix format`.
- Relevant tests are added or updated when reasonable.

## Anti-patterns

Avoid:

- Calling the LLM provider directly from `handle_event/3`.
- Reading files directly from `ChatLive`.
- Building long prompts inside LiveView.
- Adding authentication unless explicitly requested.
- Adding streaming unless the core flow is already complete.
- Adding embeddings or vector search unless explicitly requested.
```

---

# Skill 2 — elixir-architecture-review

## File suggerito

```text
.codex/skills/elixir-architecture-review.md
```

## Scopo

Usare questa skill per revisionare codice Elixir/Phoenix prima di considerare un task completato.

È particolarmente utile perché il progetto usa Elixir e Phoenix, stack che potrebbe essere nuovo per chi sviluppa il progetto.

## Contenuto consigliato

```md
# Skill: Elixir Architecture Review

Use this skill to review Elixir/Phoenix code before finalizing a task.

## Primary goal

Ensure the code is simple, idiomatic enough, maintainable, and aligned with the project architecture described in `AGENTS.md`.

## Review priorities

Check the project in this order:

1. The feature works end-to-end.
2. The code follows the architecture boundaries.
3. LLM and grounding logic are not mixed with the LiveView layer.
4. Errors are represented explicitly with `{:ok, value}` and `{:error, reason}` where appropriate.
5. User-facing flows do not raise unexpected exceptions.
6. The code remains small and readable.
7. No unnecessary dependencies or abstractions were added.

## Architecture boundaries

Expected separation:

```text
lib/beacon_assistant_web/
  = LiveView, controllers, components, rendering, web events

lib/beacon_assistant/
  = business logic, chatbot orchestration, knowledge base, LLM client, persistence contexts
```

LiveView modules should call application-level modules, not implement the whole workflow.

## Elixir style checklist

Verify:

- Functions have clear names.
- Pattern matching is used clearly, not cryptically.
- `case` statements handle both success and error paths.
- Functions that can fail return `{:ok, value}` or `{:error, reason}`.
- Bang functions such as `File.read!` or `Repo.insert!` are not used in user-facing flows unless intentionally safe.
- Long functions are split into smaller private helpers.
- Module responsibilities are narrow and clear.
- No dead code or unused aliases/imports remain.
- `mix format` passes.
- `mix test` passes if tests exist.

## Project-specific rules

- Do not introduce pgvector, embeddings, LangChain, or vector databases for the MVP.
- Keep grounding prompt-based and inspectable.
- Keep persistence simple.
- Do not add user accounts or admin panels unless explicitly requested.
- Do not add multi-turn memory unless explicitly requested.
- Prefer a small complete implementation over an incomplete larger one.

## Output expected from Codex

When performing a review, report:

- What looks good.
- What should be changed before committing.
- Any risk related to failure handling.
- Any risk related to scope creep.
- Any missing tests or documentation.
```

---

# Skill 3 — llm-failure-handling

## File suggerito

```text
.codex/skills/llm-failure-handling.md
```

## Scopo

Usare questa skill quando si implementa o modifica il client LLM, la costruzione del prompt, la gestione delle risposte o gli stati di errore nella chat.

Questa skill è fondamentale: il sistema deve essere robusto se il modello fallisce.

## Contenuto consigliato

```md
# Skill: LLM Failure Handling

Use this skill when implementing or reviewing LLM provider integration, prompt handling, and user-facing failure behavior.

## Primary goal

The application must never crash or leave the user stuck when the LLM provider fails, times out, returns an API error, or returns malformed output.

## Mandatory behavior

Every user question must produce one of these outcomes:

1. a grounded assistant answer saved to PostgreSQL;
2. a graceful fallback answer saved to PostgreSQL with a failed status.

The user must never remain stuck on a spinner.

## Failure cases to handle

The LLM client must handle:

- Missing API key.
- Invalid API key.
- HTTP 401.
- HTTP 429.
- HTTP 500 or other provider errors.
- Network errors.
- Timeout.
- Malformed JSON.
- Empty response body.
- Unexpected response shape.
- Empty assistant message.

## Return shape

LLM functions should return explicit tuples:

```elixir
{:ok, answer}
{:error, reason}
```

Do not let provider-specific exceptions leak into LiveView.

## User-facing fallback message

Use a simple fallback message such as:

```text
Sorry, I couldn't generate an answer right now. Please try again.
```

Do not expose raw provider errors, stack traces, API keys, request bodies, or sensitive configuration to the user.

## Persistence rules

When the model succeeds, save:

- question;
- answer;
- status: `success`;
- sources used, if available;
- latency if implemented.

When the model fails, save:

- question;
- fallback answer;
- status: `failed`;
- normalized error message for debugging;
- latency if implemented.

## Prompt rules

The prompt must enforce grounding:

- The assistant answers only from the provided Markdown context.
- The assistant must not use external knowledge.
- If the context is insufficient, the assistant must say it does not have enough information.
- The assistant must not invent Beacon policies or product behavior.

## Scope rules

- Use a single LLM call per user question.
- Do not add a second model call for intent detection, reranking, or validation unless explicitly requested.
- Do not add embeddings or vector search unless explicitly requested.

## Testing checklist

Where practical, test or manually verify:

- Successful answer.
- Missing API key.
- Simulated timeout.
- Simulated malformed response.
- Simulated empty answer.
- Failed request still clears loading state.
- Failed request is persisted.
```

---

# Skill 4 — readme-decisions-writer

## File suggerito

```text
.codex/skills/readme-decisions-writer.md
```

## Scopo

Usare questa skill per aggiornare `README.md` e `DECISIONS.md` durante lo sviluppo, non solo alla fine.

Il progetto deve essere facile da capire per una persona che apre la repo per la prima volta.

## Contenuto consigliato

```md
# Skill: README and Decisions Writer

Use this skill when creating or updating project documentation.

## Primary goal

Keep the repository understandable for another engineer. Documentation should explain how the app works, how to run it, how grounding is handled, how model failures are handled, and what tradeoffs were made.

## README.md must include

- Project name.
- Short description.
- Live application URL placeholder or final URL.
- Stack used:
  - Elixir;
  - Phoenix;
  - Phoenix LiveView;
  - PostgreSQL;
  - chosen LLM provider;
  - Markdown knowledge base.
- Requirements:
  - Elixir version;
  - Erlang/OTP version if relevant;
  - PostgreSQL;
  - required environment variables.
- Local setup commands:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

- Environment variables:
  - `DATABASE_URL` if needed;
  - `SECRET_KEY_BASE` for production;
  - `LLM_API_KEY` or provider-specific variable;
  - `LLM_MODEL` if configurable.
- How to run tests:

```bash
mix test
```

- How the chat flow works.
- How the Markdown knowledge base is loaded.
- How the assistant is grounded.
- How LLM failures are handled.
- How persistence works.
- Known limitations.
- What would be improved with more time.
- Notes about AI agent usage.

## DECISIONS.md must include

- What was built.
- Key architecture choices.
- Grounding strategy.
- Why embeddings/vector search were not used.
- Persistence strategy.
- Failure handling strategy.
- Deployment choice.
- Deliberately excluded features.
- Known issues.
- Future improvements.

## Tone

Use clear, direct engineering documentation.

Avoid:

- marketing tone;
- vague claims;
- pretending incomplete features are complete;
- mentioning that the project is for an interview or for a specific client unless explicitly requested.

## Suggested sections for DECISIONS.md

```md
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

## Documentation rules

- Keep documentation consistent with the actual code.
- Do not document features that are not implemented.
- Add TODOs only when they are honest known limitations.
- Prefer concise but specific explanations.
```

---

# Skill 5 — deployment-checklist

## File suggerito

```text
.codex/skills/deployment-checklist.md
```

## Scopo

Usare questa skill quando si prepara o verifica il deploy.

Il progetto deve essere accessibile da URL pubblico e funzionare davvero end-to-end.

## Contenuto consigliato

```md
# Skill: Deployment Checklist

Use this skill before deploying or when debugging production deployment issues.

## Primary goal

Ensure the Phoenix LiveView app is publicly reachable, connected to PostgreSQL, configured with the LLM provider, and able to answer a question without crashing.

## Pre-deploy checklist

Verify:

- The app runs locally with `mix phx.server`.
- `mix format` has been run.
- `mix test` passes or known failing tests are documented.
- PostgreSQL migrations are present.
- The Markdown knowledge base is included in the repository and deployment artifact.
- Runtime configuration reads environment variables correctly.
- No API keys or secrets are committed.
- The README includes local setup instructions.
- The README includes production/deployment notes.

## Required production environment variables

Check the deployment platform has:

- `DATABASE_URL` or equivalent database configuration.
- `SECRET_KEY_BASE`.
- LLM provider API key, for example `LLM_API_KEY`.
- LLM model name if configurable.
- Phoenix host configuration if needed.

## Database checklist

Verify:

- Database exists.
- Migrations have run.
- `chat_exchanges` or equivalent table exists.
- New user questions are persisted.
- Failed LLM attempts are persisted.

## Runtime checklist

Manually test the deployed URL:

1. Open the public URL.
2. Ask a question that is answerable from the Markdown docs.
3. Confirm the assistant responds.
4. Confirm the answer is grounded in the knowledge base.
5. Ask a question that is not covered by the docs.
6. Confirm the assistant does not invent an answer.
7. Temporarily simulate or reason through LLM failure handling.
8. Confirm the UI does not remain stuck in loading state.

## Production failure risks

Check specifically for:

- Missing `SECRET_KEY_BASE`.
- Missing or invalid LLM API key.
- Database connection errors.
- Migrations not executed.
- Knowledge-base files missing from release.
- Wrong Phoenix host or port configuration.
- Timeout too short or too long.

## README deployment section

Ensure README contains:

- Live URL.
- Deployment platform.
- Required environment variables.
- Any manual migration step.
- Known production limitations.

## Output expected from Codex

When using this skill, Codex should provide:

- A pass/fail checklist.
- Any blocking deploy issue.
- Any non-blocking improvement.
- Exact commands to run where useful.
```

---

# Skill opzionale — agent-transcript-manager

Questa skill è opzionale, ma utile se vuoi mantenere ordine sui transcript delle sessioni AI.

## File suggerito

```text
.codex/skills/agent-transcript-manager.md
```

## Contenuto consigliato

```md
# Skill: Agent Transcript Manager

Use this skill to keep track of AI agent usage during the project.

## Goal

Maintain a clear record of how AI agents were used while building the project.

## Repository structure

Use:

```text
docs/
  ai-agent-transcripts/
  agent-setup/
```

## Track

- Which AI agents were used.
- What tasks they were used for.
- Which outputs were accepted as-is.
- Which outputs were modified manually.
- Any important mistakes caught during review.
- Any custom instructions or MCP setup used.

## README section

Add a concise section describing AI agent usage without exposing sensitive information.

## Rules

- Do not include secrets.
- Do not include private credentials.
- Do not include irrelevant chat logs.
- Keep transcripts organized by date or task.
```

---

# Prompt template per usare le skill

Quando lavori con Codex, usa prompt piccoli e specifici.

## Esempio 1 — implementare LiveView

```text
Read AGENTS.md first.
Use the phoenix-liveview-feature skill.
Implement the minimal chat LiveView.
The LiveView must call an application-level Chatbot module and must not call the LLM provider directly.
Keep the UI simple.
After implementation, stop and summarize the diff.
```

## Esempio 2 — implementare LLM client

```text
Read AGENTS.md first.
Use the llm-failure-handling skill.
Implement the LLM client with one provider call per user question.
Return {:ok, answer} or {:error, reason}.
Handle timeout, HTTP errors, malformed JSON, and empty responses.
Do not let provider errors reach LiveView.
After implementation, add or update tests where practical.
```

## Esempio 3 — review architetturale

```text
Read AGENTS.md first.
Use the elixir-architecture-review skill.
Review the current codebase for architecture boundaries, error handling, scope creep, and Elixir style.
Do not add new features.
Return a list of required fixes and optional improvements.
```

## Esempio 4 — documentazione

```text
Read AGENTS.md first.
Use the readme-decisions-writer skill.
Update README.md and DECISIONS.md to match the current implementation.
Do not document features that are not implemented.
Keep the project context neutral and refer only to Beacon Support Assistant.
```

## Esempio 5 — deploy readiness

```text
Read AGENTS.md first.
Use the deployment-checklist skill.
Review the project for deployment readiness.
Check env vars, migrations, knowledge-base files, Phoenix config, README deployment notes, and manual testing steps.
Do not add new features.
```

---

# Ordine di utilizzo consigliato

Usa le skill in questa sequenza:

```text
1. phoenix-liveview-feature
2. elixir-architecture-review
3. llm-failure-handling
4. elixir-architecture-review
5. readme-decisions-writer
6. deployment-checklist
```

Per ogni fase, chiedi a Codex di fermarsi e riassumere il diff prima di passare alla fase successiva.

---

# Regole finali per Codex

Qualunque skill venga usata, Codex deve rispettare sempre queste regole:

- leggere `AGENTS.md` prima di agire;
- non introdurre feature bonus se il core non è completo;
- non usare embeddings o vector DB salvo richiesta esplicita;
- non creare frontend separato;
- non mettere logica LLM dentro LiveView;
- salvare ogni domanda e risposta;
- gestire sempre errori e timeout del modello;
- non lasciare la UI bloccata in loading;
- mantenere documentazione aggiornata;
- eseguire `mix format` dopo modifiche Elixir;
- eseguire `mix test` quando possibile;
- proporre commit piccoli e leggibili.
