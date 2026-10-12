# Disciplined docs

This folder explains the parts of Disciplined that the code can't explain by itself: how the pieces fit together, why they were built this way, and how to do recurring development tasks. Read this file before adding or editing anything here.

## Layout

| Folder | Holds | Answers | Changes when |
| --- | --- | --- | --- |
| [`architecture/`](architecture/README.md) | How a subsystem works today | "How does X work?" | The code changes |
| [`decisions/`](decisions/README.md) | One decision each, with its reasons and the options that lost | "Why is X like this?" | Never (a new decision supersedes it) |
| [`guides/`](guides/README.md) | Step-by-step instructions for a task | "How do I do X?" | The steps change |
| [`templates/`](templates/) | A starting file for each kind of doc | — | The rules here change |

Each folder's `README.md` is its index: one line per document with its summary. Start there instead of opening files at random.

### Relationship to `CLAUDE.md`

`CLAUDE.md` at the repo root is loaded into every AI session, so it has to stay short. It holds commands, the architecture in brief, cross-file invariants and gotchas that bite on almost any change. This folder holds the depth.

- When a `CLAUDE.md` section grows past a short paragraph or a few bullets, move the detail into a doc here and leave one line in `CLAUDE.md` that links to it.
- Don't copy text between the two. If `CLAUDE.md` and a doc disagree, one of them is a bug: fix it in the same change.

## Choosing where something goes

1. **Is it already obvious from reading one source file?** Then it doesn't need a doc. Improve the code or add a comment instead.
2. **Is it about why something was chosen over an alternative?** Write a decision.
3. **Is it a sequence of steps someone will repeat?** Write a guide.
4. **Is it about how parts interact across files, processes or layers?** Add to the architecture doc for that subsystem, or create one.
5. **Does it fit none of these?** It probably doesn't belong in `docs/`. See "What doesn't belong".

When a topic needs more than one kind, split it and link the parts. For example, a decision explains why the Firefox policy has two modes, and the architecture doc describes how the modes work now and links to the decision.

## Rules

### Files and names

- **One topic per file.** If a heading could become its own doc, and other docs would link to it, split it out.
- **Names are lowercase kebab-case and say the topic:** `native-messaging-host.md`, not `notes.md`, `misc.md`, `new-design.md` or `host-v2.md`.
- **Decisions are numbered:** `NNNN-short-title.md`, four digits, the next free number, never reused. Nothing else gets numbers or dates in its name.
- **No new top-level folders** without a decision record explaining why the existing three don't fit. No nested folders inside them until a folder has more than about 15 files.
- **Start from the template** in `templates/` for the kind of doc you're writing.
- **Every new, renamed or deleted file updates its folder's `README.md` index** in the same change.

### Front matter

Every doc except the indexes starts with YAML front matter, then an `#` title:

```markdown
---
summary: One sentence saying what this doc covers, specific enough to decide whether to open it.
---

# Title
```

Decisions also carry `status` and `date` (see [`decisions/README.md`](decisions/README.md)). The `summary` is copied into the folder index word for word. "Notes about the extension" is a bad summary. "How the browser extension turns the blocklist into one `declarativeNetRequest` rule, and when it re-checks open tabs" is a good one.

### Content

- **Explain what the code can't.** Docs exist for intent, reasons, cross-file flows, invariants and traps. Don't restate a function's body, list every property of a type or paraphrase a single file.
- **Each fact lives in one place.** Link to it everywhere else. Duplicated facts drift apart and then neither can be trusted.
- **Be concrete.** Use the exact names a reader would search for: file paths (`Sources/BlockerModel.swift`), types and functions (`BlockerModel.refresh()`), settings keys (`appTheme`), paths on disk. Write "every second", not "frequently".
- **Point at code by path and symbol, never by line number.** Line numbers go stale with the next edit.
- **Use relative links** for anything in the repo, such as `[BlockerModel](../../Sources/BlockerModel.swift)` from a doc in `architecture/`, so links work on GitHub and in editors.
- **Separate fact from opinion.** State what is true now in the present tense. Put open questions, known limitations or unverified behavior under a heading that says so ("Known limitations", "Unverified"). Never present a guess as fact.
- **Headings are meaningful and searchable.** A reader or AI should be able to jump to the right section from the heading alone. Avoid headings like "Details", "Other" or "Misc".
- **Prefer short docs.** Over about 300 lines usually means several topics, so split it.
- **Diagrams are text:** Mermaid or ASCII inside the Markdown. Add an image only when text really can't show it, and then also describe it in words.
- **Write in English**, in plain, short sentences. Skip the preamble ("This document aims to…"), filler and conclusions that repeat the content.

### Privacy

Site names are sensitive in this app, and that applies to the docs as well. Never use a real site from anyone's blocklist in an example. Use `example.com`, `example.org` and `example.net`. Don't paste real `/etc/hosts` contents, real `blocklist.txt` contents or any personal paths beyond `~`.

### Keeping docs true

- **Update docs in the same change as the code.** A change that makes a doc wrong includes the fix to that doc.
- **A wrong doc is worse than no doc.** If you find something false and can't fix it now, delete the false part, or mark it with a clear `> **Outdated:**` note saying what's wrong. Don't leave it silently.
- **Delete docs for code that no longer exists.** Git keeps the history. Decisions are the exception: mark them `Superseded` or `Deprecated` instead of deleting them.
- **Verify before writing.** Read the code or run it. Don't document from memory or from another doc.
- **Back rules with tests where you can.** If a doc says something must stay true across files, a test should fail when it isn't. Name that test in the doc (see [`architecture/testing.md`](architecture/testing.md#which-test-guards-which-invariant)). A rule that only lives in prose will eventually be broken without anyone noticing.

## What doesn't belong

- **Changelogs, session logs and progress reports** ("Today I fixed…", "Phase 2 done"). Git history and commit messages hold these.
- **To-do lists, roadmaps and plans in progress.** Use issues, or keep them out of the repo. Once a plan is decided, its outcome becomes a decision record.
- **Copies of code, generated output, logs or AI transcripts.** Link to the source file instead, and summarize only what matters.
- **General knowledge** that isn't specific to this project, such as how SwiftUI or launchd work in general. Link to the official docs if it helps, and write down only what is particular to how Disciplined uses it.
- **Duplicates of `CLAUDE.md`,** or of another doc.
- **Secrets, credentials, real site names or personal data.**

## Checklist before committing a doc

- [ ] It's in the right folder, under a descriptive kebab-case name, and it started from the template.
- [ ] Its front matter has a specific `summary`, and the folder index has that line.
- [ ] Every path, symbol and command in it exists and is spelled exactly. Every relative link resolves.
- [ ] It doesn't repeat `CLAUDE.md` or another doc. It links to them instead.
- [ ] It contains nothing from "What doesn't belong", and no real site names.
- [ ] If it changes or replaces an earlier decision, that decision's `status` now points to the new one.
