# AGENTS.md — Beacon Support Assistant

This file provides instructions for AI coding agents working on the Beacon Support Assistant project.

The goal is to build a small, complete, deployed Phoenix LiveView application that lets a user ask support questions and receive answers grounded only in the provided Beacon Markdown knowledge base.

Prioritize a working, deployed, well-documented slice over a large or over-engineered system.

---

## 1. Project Goal

Build a simple support assistant for Beacon.

The user should be able to:

1. Open a public deployed web app.
2. Ask a question in a Phoenix LiveView chat UI.
3. Receive a precise answer based only on the provided Markdown help-center documents.
4. Have every question and answer persisted in PostgreSQL.
5. Receive a graceful fallback message if the LLM fails.

The application must be small, readable, robust, and easy to explain.

---

## 2. Required Stack

Use the following stack:

- Elixir
- Phoenix
- Phoenix LiveView
- PostgreSQL
- A bring-your-own-key LLM provider via HTTP API

Recommended provider for the MVP: a cloud LLM API such as OpenAI, Anthropic, Gemini, Groq, or similar.

Avoid using Ollama for the first deployed version unless deployment constraints are already solved, because a local model can complicate hosting.

---

## 3. Core Requirements

The completed app must:

- provide a simple chat UI built with Phoenix LiveView;
- accept user questions;
- load the provided Markdown knowledge base;
- ground the LLM response in the Markdown content;
- make one LLM call per user question;
- persist every question and answer in PostgreSQL;
- persist failed LLM attempts as well;
- handle model/API failures gracefully;
- never crash the LiveView because of an LLM failure;
- never leave the UI stuck in a loading/spinner state;
- be deployable to a public URL;
- include clear README, DECISIONS.md, and this AGENTS.md file.

---

## 4. Scope Discipline

This project has an initial delivery budget of about 6 focused hours for the MVP. Keep the implementation small.

Build the smallest complete version that works end-to-end.

### Build

Implement:

- Phoenix LiveView chat page;
- PostgreSQL persistence for exchanges;
- Markdown knowledge base loader;
- deterministic grounding prompt;
- LLM client with timeout and error handling;
- graceful error fallback;
- optional source display if easy;
- README and decision log.

### Do Not Build in the MVP

Do not introduce these unless the core is already complete, deployed, and documented:

- vector database;
- embeddings;
- pgvector;
- LangChain;
- authentication;
- user accounts;
- multi-tenancy;
- admin upload panel;
- complex document management;
- advanced reindexing;
- streaming token-by-token;
- multi-turn conversation memory;
- complex UI polish.

The brief explicitly allows prompt-based grounding without embeddings or a vector database. Prefer a simple, inspectable solution.

---

## 5. Repository Strategy

Use one Phoenix repository.

Do not split frontend and backend into separate repos for this project. Phoenix LiveView already combines server-rendered interactive UI and backend logic in a single Phoenix application.

Recommended structure:

```text
beacon_assistant/
  lib/
    beacon_assistant/
      chatbot.ex
      knowledge_base.ex
      llm_client.ex
      conversations.ex
      conversations/
        exchange.ex

    beacon_assistant_web/
      live/
        chat_live.ex
      components/
      router.ex

  priv/
    repo/
      migrations/
    knowledge_base/
      billing.md
      security.md
      plans.md
      ...

  config/
  test/
  mix.exs
  README.md
  DECISIONS.md
  AGENTS.md
```

Keep domain/application logic under `lib/beacon_assistant/`.
Keep web/UI logic under `lib/beacon_assistant_web/`.

---

## 6. Architecture Rules

Separate responsibilities clearly.

### `BeaconAssistantWeb.ChatLive`

Responsibilities:

- render the chat UI;
- handle form submission;
- show loading/error states;
- render previous exchanges;
- call the application context.

Do not put Markdown parsing, prompt construction, or HTTP LLM logic directly inside the LiveView.

### `BeaconAssistant.Chatbot`

Responsibilities:

- orchestrate the full flow:
  - receive question;
  - fetch relevant knowledge base context;
  - build grounded prompt;
  - call LLM client;
  - persist result;
  - return a safe response to the LiveView.

### `BeaconAssistant.KnowledgeBase`

Responsibilities:

- read Markdown files from `priv/knowledge_base/` or the provided `knowledge-base/` folder;
- return document title, source filename, and content;
- optionally select relevant documents using simple keyword matching;
- return the source filenames used in the answer.

### `BeaconAssistant.LLMClient`

Responsibilities:

- call the selected LLM provider;
- apply timeouts;
- handle non-2xx HTTP responses;
- handle malformed JSON;
- handle empty or missing answer content;
- return `{:ok, answer}` or `{:error, reason}` only.

This module must not leak unhandled exceptions into LiveView.

### `BeaconAssistant.Conversations`

Responsibilities:

- persist every question and answer;
- persist failed attempts;
- expose functions for creating and listing exchanges;
- keep persistence logic out of the LiveView.

---

## 7. End-to-End Flow

Expected flow:

```text
User submits question
  ↓
ChatLive.handle_event("send", params, socket)
  ↓
BeaconAssistant.Chatbot.ask(question)
  ↓
KnowledgeBase.relevant_context(question)
  ↓
Build grounded prompt
  ↓
LLMClient.complete(prompt)
  ↓
Conversations.create_exchange(...)
  ↓
LiveView updates messages and clears loading state
```

The LiveView manages UI state. The application modules manage domain behavior.

---

## 8. Grounding Strategy

The Markdown knowledge base is the single source of truth.

The assistant must not answer from general model knowledge. It must answer only from the provided Beacon help-center context.

If the answer is not available in the provided context, the assistant must say that it does not have enough information in the Beacon help docs.

### Recommended MVP Approach

Because the provided knowledge base is small, use direct prompt grounding:

1. Read the Markdown files.
2. Include all documents in the prompt, or select a small relevant subset with deterministic keyword matching.
3. Ask the LLM to answer only from that context.
4. Store the source filenames used.

Do not use embeddings or vector search for the MVP.

### README/DECISIONS Justification

Use this reasoning in the documentation:

> The provided knowledge base is intentionally small and the project scope allows prompt-based grounding without embeddings or a vector database. I chose direct Markdown prompt grounding to keep the solution inspectable, simple, and aligned with the MVP scope.

---

## 9. Prompt Requirements

Use a strict system prompt.

Example:

```text
You are Beacon's support assistant.
Answer customer questions using only the provided Beacon help-center context.
Do not use outside knowledge.
If the context does not contain enough information to answer, say that you don't have enough information in the Beacon help docs.
Be concise, precise, and helpful.
```

Example user prompt template:

```text
Beacon help-center context:

--- BEGIN DOCUMENT: billing.md ---
<markdown content>
--- END DOCUMENT: billing.md ---

--- BEGIN DOCUMENT: security.md ---
<markdown content>
--- END DOCUMENT: security.md ---

Customer question:
<question>

Instructions:
- Answer only from the context above.
- Do not guess.
- If the answer is not present, say you do not have enough information in the Beacon help docs.
- Prefer a direct answer over a long explanation.
```

Do not let the LLM improvise policies, pricing, billing behavior, security behavior, or support procedures that are not in the Markdown files.

---

## 10. Persistence Requirements

Create a PostgreSQL table for exchanges.

Recommended schema:

```text
chat_exchanges
- id
- question: text, required
- answer: text
- status: string, required
- error_message: text
- sources: jsonb or array
- latency_ms: integer
- inserted_at
- updated_at
```

Recommended statuses:

```text
completed
failed
```

Persist successful responses and failed attempts.

If the model fails, save something like:

```text
question: "How do I reset 2FA?"
answer: "Sorry, I couldn't generate an answer right now. Please try again."
status: "failed"
error_message: "timeout"
sources: []
```

Never lose a user question because the LLM failed.

---

## 11. Failure Handling Rules

Failure handling is critical.

The application must handle:

- missing API key;
- timeout;
- network failure;
- provider unavailable;
- HTTP 401;
- HTTP 429;
- HTTP 500;
- malformed JSON;
- empty response;
- response without expected text field;
- unexpected exceptions during HTTP call.

The LLM client must return:

```elixir
{:ok, answer}
```

or:

```elixir
{:error, reason}
```

The user-facing fallback should be simple and non-technical:

```text
Sorry, I couldn't generate an answer right now. Please try again.
```

Do not expose stack traces, raw provider errors, API keys, request IDs, or internal details in the UI.

Always clear loading state after success or failure.

---

## 12. Phoenix LiveView Guidelines

The chat UI can be simple.

Minimum UI state:

```elixir
assign(socket,
  exchanges: [],
  loading: false,
  error: nil
)
```

On submit:

1. Ignore or reject empty questions.
2. Set loading state.
3. Call `BeaconAssistant.Chatbot.ask/1`.
4. Append or reload the persisted exchange.
5. Clear input.
6. Set loading to false in both success and failure paths.

Do not let the LiveView process crash because of an LLM error.

---

## 13. Testing and Manual Validation

At minimum, manually test:

- app loads locally;
- app loads from public deployment URL;
- user can ask a question;
- answer is grounded in Markdown docs;
- unknown question gets an “I don't have enough information” style answer;
- exchange is saved in PostgreSQL;
- bad/missing API key does not crash the app;
- provider timeout/error does not leave spinner stuck;
- README instructions work from a clean checkout.

Where practical, add tests for:

- Markdown loading;
- prompt construction;
- LLM client response parsing;
- conversation changeset validation.

---

## 14. Documentation Requirements

Create a strong README. Treat it as documentation for a teammate.

README must include:

- project description;
- live URL;
- stack;
- architecture overview;
- local setup;
- required environment variables;
- database setup and migration commands;
- how to run tests;
- how grounding works;
- why no embeddings/vector database were used;
- how LLM failures are handled;
- data model summary;
- known limitations;
- what would be improved with more time;
- short note on AI agent usage.

Also create `DECISIONS.md` or a clear README section covering:

- what was built;
- key tradeoffs;
- what was deliberately cut;
- known issues;
- future improvements.

---

## 15. Suggested `DECISIONS.md` Content

Use a structure like:

```markdown
# Decisions

## Scope
Built a small Phoenix LiveView support assistant for Beacon.

## Grounding strategy
Used Markdown files as direct prompt context instead of embeddings.

## Persistence
Stored each question/answer exchange in PostgreSQL.

## Failure handling
Wrapped LLM calls with timeout/error handling and persisted failed attempts.

## Deliberately cut
- Authentication
- Admin document upload
- Embeddings/vector search
- Streaming
- Multi-turn memory
- Advanced UI polish

## Known limitations
- Assumes a small knowledge base
- Basic document selection
- No user accounts
- No advanced hallucination verification
```

---

## 16. AI Agent Deliverables

The project requires clear AI agent evidence for transparency and handoff.

Prepare:

- a zip of coding-agent conversations/transcripts;
- this `AGENTS.md` file in the repo;
- any additional agent config used, such as:
  - `CLAUDE.md`;
  - `.cursorrules`;
  - custom commands;
  - MCP server config;
  - prompts used to drive the agent.

When implementing with AI assistance, keep a clear record of:

- what the agent generated;
- what was accepted as-is;
- what was manually changed;
- why architectural choices were made.

Do not forget to include the transcript zip in the final handoff package.

---

## 17. Codex Skills Usage

Project-specific Codex skills live in:

```text
.codex/skills/
```

When a task matches one of these skills, read that skill's `SKILL.md` before making changes. Also read this `AGENTS.md` first. If several skills apply, use the smallest set that covers the task.

### Available Skills

- `phoenix-liveview-feature`
  - Use when implementing or modifying Phoenix LiveView features: chat UI, forms, loading state, error state, source display, and integration with application modules.
  - Use during implementation steps 3, 4, and 10.

- `llm-failure-handling`
  - Use when implementing or reviewing LLM provider calls, prompt grounding, response parsing, timeouts, malformed responses, missing API keys, and failed-attempt persistence.
  - Use during implementation steps 6, 7, 8, and 9.

- `elixir-architecture-review`
  - Use before finalizing any code task or when reviewing a diff for architecture boundaries, Elixir/Phoenix style, failure handling, and MVP scope.
  - Use after LiveView work, after LLM/client work, before deployment, and before committing larger changes.

- `readme-decisions-writer`
  - Use when creating or updating `README.md`, `DECISIONS.md`, deployment notes, environment variable docs, limitation notes, or AI-agent usage notes.
  - Use during implementation steps 12, 13, and 14.

- `deployment-checklist`
  - Use before deploying, after deploying, or when debugging production issues around Phoenix config, PostgreSQL, migrations, knowledge-base files, environment variables, or LLM provider config.
  - Use during implementation step 11 and final submission checks.

- `agent-transcript-manager`
  - Use when collecting AI-agent prompts, transcripts, setup notes, and final handoff evidence.
  - Use during implementation step 15 and whenever agent evidence is updated.

### Recommended Skill Sequence

Use this order for the MVP:

```text
1. phoenix-liveview-feature
2. elixir-architecture-review
3. llm-failure-handling
4. elixir-architecture-review
5. readme-decisions-writer
6. deployment-checklist
7. agent-transcript-manager
```

For each phase, keep the work scoped, verify the result, and summarize the diff before moving to the next phase.

---

## 18. Branch Strategy

Follow GitFlow as defined in `branch_strategy_gitflow.md`. Treat that file as the source of truth for branch, release, hotfix, merge, and tagging rules.

### Branch Roles

- `master` is production.
- `dev` is the main development branch.
- Feature branches start from `dev`.
- Release branches start from `dev` and use version names like `v.1.0.1`.
- Hotfix branches start from `master` and use names like `hotfix-llm-timeout`.

Do not work directly on `master`. Do not work directly on `dev` except for exceptional repository maintenance. Keep changes isolated in small feature branches.

### Feature Branches

Create feature branches from `dev`:

```bash
git checkout dev
git pull origin dev
git checkout -b chat-interface
```

Naming rules:

- use lowercase letters;
- use hyphens instead of spaces;
- describe one coherent feature or fix;
- avoid vague names like `update`, `fix`, `changes`, `test`, `wip`, or `final`.

Recommended Beacon feature branch names:

```text
project-setup
chat-persistence
chat-liveview
knowledge-base-loader
llm-client
grounded-answering
failure-handling
sources-display
deployment-config
documentation
```

Before merging a feature branch into `dev`, run format and tests where possible:

```bash
mix format
mix test
```

Use Pull Requests for feature and release merges when possible.

### Release Branches

Create release branches from `dev`:

```bash
git checkout dev
git pull origin dev
git checkout -b v.1.0.1
git push origin v.1.0.1
```

On release branches, only make bugfixes, final polish, README/DECISIONS updates, deploy config fixes, and release preparation. Do not add new features.

When stable, merge release into `master`, tag the same version, and push tags:

```bash
git checkout master
git pull origin master
git merge v.1.0.1
git tag v.1.0.1
git push origin master --tags
```

After production merge, merge the release branch back into `dev` so release fixes are retained:

```bash
git checkout dev
git pull origin dev
git merge v.1.0.1
git push origin dev
```

### Hotfixes

Create hotfix branches from `master` for urgent production fixes:

```bash
git checkout master
git pull origin master
git checkout -b hotfix-llm-timeout
```

After verification, merge the hotfix into `master`, tag a patch release if needed, then merge the hotfix back into `dev`.

### Merge Checklist

Before any merge:

- code compiles;
- `mix format` has run;
- `mix test` passes or any failure is documented;
- `mix credo` passes if Credo is present;
- no `.env`, API keys, tokens, secrets, local logs, or temporary files are included;
- diff was reviewed with `git status` and `git diff`;
- branch scope matches the change;
- documentation is updated when architecture, setup, deploy, or behavior changed.

Avoid:

- direct commits on `master`;
- direct commits on `dev` unless exceptional;
- feature branches from `master`;
- new features on release branches;
- releases without tags;
- hotfixes merged only to `master` and not back to `dev`;
- vague branch names;
- vague commit messages;
- merges without format and tests.

---

## 19. Commit Guidelines

Keep commit history readable.

Prefer small commits such as:

```text
init phoenix liveview app
add chat exchange persistence
add markdown knowledge base loader
add grounded prompt builder
add llm client with failure handling
add chat liveview
persist successful and failed exchanges
show answer sources
add deployment config
add README decisions and agents documentation
```

Avoid one large final commit.

Never commit secrets, API keys, `.env`, or provider credentials.

Include `.env.example` with placeholder variables.

---

## 20. Environment Variables

Document and use environment variables for secrets and runtime config.

Suggested variables:

```text
DATABASE_URL=postgres://...
SECRET_KEY_BASE=...
LLM_PROVIDER=openai
LLM_API_KEY=...
LLM_MODEL=...
LLM_TIMEOUT_MS=15000
```

Use placeholders in `.env.example`.

Do not commit real secrets.

---

## 21. Deployment Checklist

Before final submission, verify:

- public URL works in incognito/private browser;
- app connects to production PostgreSQL;
- migrations have run;
- `SECRET_KEY_BASE` is configured;
- `LLM_API_KEY` is configured;
- knowledge base Markdown files are included in the deploy;
- a real question returns an answer;
- unknown questions do not hallucinate;
- exchange is persisted;
- LLM error path works;
- README contains the live URL;
- repository includes README, DECISIONS.md, and AGENTS.md.

Choose the fastest reliable hosting option. Acceptable options include Fly.io, Render, Gigalixir, Railway, or a VPS Docker deployment.

---

## 22. Implementation Order

Follow this order to reduce risk:

1. Create Phoenix LiveView app with PostgreSQL.
2. Add `chat_exchanges` migration and schema.
3. Build minimal chat UI.
4. Persist fake question/answer exchanges.
5. Load Markdown files from the knowledge base.
6. Build grounded prompt.
7. Integrate LLM provider.
8. Add timeout, API error, and malformed response handling.
9. Persist failed attempts.
10. Show source filenames if easy.
11. Deploy publicly.
12. Write README.
13. Write DECISIONS.md.
14. Keep/update AGENTS.md.
15. Export AI agent transcripts.
16. Run final manual test checklist.

Do not start with advanced RAG. Start with UI + persistence + deterministic grounding.

---

## 23. Final Acceptance Checklist

### Functional

- [ ] Public URL opens.
- [ ] User can submit a question.
- [ ] Assistant answers using the Markdown knowledge base.
- [ ] Assistant refuses or says it lacks information when the answer is not in the docs.
- [ ] Every question and answer is saved.
- [ ] Failed LLM calls are saved.
- [ ] LLM errors do not crash the app.
- [ ] Loading state never remains stuck.

### Technical

- [ ] Phoenix LiveView used for chat UI.
- [ ] PostgreSQL used for persistence.
- [ ] Web layer separated from grounding/LLM logic.
- [ ] LLM client returns `{:ok, answer}` or `{:error, reason}`.
- [ ] Markdown loader is isolated and testable.
- [ ] Prompt is strict about using only provided context.
- [ ] Secrets are not committed.

### Documentation

- [ ] README includes live URL.
- [ ] README explains local setup.
- [ ] README explains grounding.
- [ ] README explains failure handling.
- [ ] README lists known limitations.
- [ ] DECISIONS.md exists or equivalent section is present.
- [ ] AGENTS.md exists.
- [ ] AI agent transcripts are exported.
- [ ] AI agent setup/config is included.

### Repository

- [ ] Clean commit history.
- [ ] `.env` ignored.
- [ ] `.env.example` present.
- [ ] Knowledge base files included.
- [ ] App deploy config included if relevant.

---

## 24. Main Principle

Do not over-engineer.

The best solution for this project is:

```text
One Phoenix LiveView monolith
PostgreSQL persistence
Markdown files as direct grounded context
Single LLM call per question
Graceful LLM failure handling
Simple deployed chat UI
Clear README + DECISIONS + AGENTS documentation
```

Optimize for:

- end-to-end functionality;
- public deployment;
- graceful failure behavior;
- clear architecture;
- sensible scope;
- strong communication;
- transparent AI-agent usage.
