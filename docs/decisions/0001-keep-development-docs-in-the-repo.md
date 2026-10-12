---
summary: Store architecture, decisions and guides as Markdown in `docs/`, kept short and separate from `CLAUDE.md`.
status: Accepted
date: 2026-10-12
---

# 0001 Keep development docs in the repo

## Context

Until now, everything written about the code lived in `CLAUDE.md`. That file is loaded into every AI session, so each line costs context on every task. It works for commands, invariants and gotchas, but it can't hold reasoning or long explanations without slowing down every session. The reasons behind choices weren't written down anywhere, so a later change could undo one without knowing why it was made.

The docs are read by people and by AI agents. Both need to find the right document quickly and trust what it says.

## Decision

Add a `docs/` folder with three kinds of document, each in its own folder: `architecture/` (how it works now), `decisions/` (why, one per file, never rewritten) and `guides/` (how to do a task). Each folder has an index of one-line summaries, and every doc has a `summary` in its front matter. [`docs/README.md`](../README.md) sets the rules for naming, content, privacy and upkeep.

`CLAUDE.md` stays the short, always-loaded summary. It links into `docs/` for detail, and the two don't duplicate each other.

## Alternatives considered

- **Keep everything in `CLAUDE.md`.** Rejected: it would grow without limit and spend context on every session for detail that most tasks don't need.
- **An external wiki or notes app.** Rejected: it isn't versioned with the code, can't be updated in the same commit, and AI agents working in the repo can't see it.
- **Code comments only.** Rejected for anything that spans files. Comments suit local intent but can't hold a flow across the app, the root helper and the extension, or record options that were never written.
- **One folder with no structure.** Rejected: without separate kinds and indexes, files mix current state with history and end up hard to search and easy to let go stale.

## Consequences

- A code change that makes a doc wrong now includes the doc fix.
- Adding a doc means updating its folder index. This small cost keeps the docs findable.
- Decisions pile up and are never rewritten, so to see what's in effect, check `status`.
