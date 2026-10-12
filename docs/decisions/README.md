# Decisions

Each file records one decision: the situation that called for it, what was chosen, the alternatives that were turned down and why, and what follows from it. These records keep the reasoning that the code can't show, so nobody has to rediscover why a tempting alternative was rejected.

Write one when a choice is hard to reverse, when it affects more than one file or layer, or when a reasonable person would otherwise ask "why not just…?". Routine implementation choices don't need one.

Start from [`templates/decision.md`](../templates/decision.md). The general rules are in [`docs/README.md`](../README.md).

## Rules for decisions

- **Numbering:** `NNNN-short-title.md`, using the next free number. Numbers are never reused, even after a deletion.
- **Front matter:** `summary`, `status` and `date` (`YYYY-MM-DD`, the day it was accepted).
- **Status** is one of:
  - `Proposed`: under discussion, not yet acted on.
  - `Accepted`: in effect.
  - `Superseded by NNNN`: replaced by a later decision.
  - `Deprecated`: no longer in effect, and nothing replaced it.
- **Accepted decisions are not rewritten.** To change course, write a new decision that links back to the old one, then change the old one's `status` to `Superseded by NNNN` and update its index line. Fixing a typo or a broken link is fine.
- **Record the losing options** with the real reason each lost. "Alternatives considered: none" is almost always wrong.
- **Only record what's known.** If the reasoning behind an existing choice is unknown, don't invent one. Ask, or leave it unrecorded.

## Index

<!-- One line per decision, in number order: - [NNNN Title](file.md) — status — summary -->

- [0001 Keep development docs in the repo](0001-keep-development-docs-in-the-repo.md) — Accepted — Store architecture, decisions and guides as Markdown in `docs/`, kept short and separate from `CLAUDE.md`.
