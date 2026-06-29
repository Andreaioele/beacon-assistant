---
name: agent-transcript-manager
description: Organize Beacon Support Assistant AI-agent evidence, prompts, transcripts, and agent setup notes. Use when collecting deliverables about Codex or other coding-agent usage, preparing handoff evidence, or documenting which agent outputs were accepted or modified.
---

# Agent Transcript Manager

## Goal

Maintain clear AI-agent usage evidence without secrets or irrelevant chat noise.

## Repository Structure

Use:

```text
docs/
  ai-agent-transcripts/
  agent-setup/
```

Keep transcript artifacts organized by date or task. Store only useful evidence needed for transparency and handoff.

## Track

- which AI agents were used;
- what tasks they were used for;
- which outputs were accepted as-is;
- which outputs were modified manually;
- important mistakes caught during review;
- custom instructions, prompts, or MCP setup used.

## Rules

- Do not include secrets, API keys, credentials, or private tokens.
- Do not include raw logs that expose sensitive environment values.
- Do not include irrelevant chat logs.
- Keep summaries concise and factual.
- Add a short README section describing AI agent usage when docs are updated.

## Deliverable Check

Before final handoff, confirm:

- `AGENTS.md` is present;
- relevant skill/config files are included;
- transcript or summary files exist under `docs/`;
- sensitive values were redacted;
- README mentions AI agent usage accurately.
