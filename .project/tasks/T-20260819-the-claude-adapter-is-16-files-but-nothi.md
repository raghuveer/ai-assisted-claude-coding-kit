---
id: T-20260819-the-claude-adapter-is-16-files-but-nothi
title: The Claude adapter is 16 files but nothing records that or names the second one
epic: components
tier: T2
lang: markdown
paths: docs/DESIGN-NOTES.md, docs/ADAPTERS.md, .claude-plugin/plugin.json
state: open
---

## Intent

The kit is already two layers and **nothing says so**, which means the boundary is real but
undefended: any change may quietly cross it and nobody would notice until a port was attempted.

Measured 2026-08-18:

| | |
|---|---|
| `CLAUDE_PLUGIN_ROOT` in `tooling/` | **0 occurrences** |
| Model names or `anthropic` in `tooling/` or `tests/` | **none** |
| What the `.claude/` references in `tooling/` are | 12 × the path to `project-profile.md` — a directory name |
| The harness-coupled surface | **16 files**: `skills/` 5, `agents/` 8, `hooks/` 1, `.claude-plugin/` 2 |

So the **portable core** is 18 shell scripts, a sqlite schema and text files, knowing nothing about
Claude beyond a folder name; the **adapter** is 16 files. `tooling/kit-review-record.sh` was built
as the seam deliberately — its header states that `--cmd` *"is the only thing that knows how a
reviewer is invoked here, so no harness name, CLI or model appears in this file."*

Porting to another coding agent is therefore **writing a second adapter, not refactoring**. That is
a materially different piece of work from what it looks like from outside, and it is currently
recorded nowhere — it exists only as a Note in
`T-20260818-relicense-from-mit-to-apache-2-0-while-s` saying a rename is "deliberately not bundled",
which is a deferral rather than a record.

## Acceptance criteria

- [ ] The two-layer boundary is **documented where a contributor will hit it**, with the one
      genuine hardcode named: `kit_profile()` in `kit-lib.sh` fixes `.claude/project-profile.md`,
      and `paths.*` config keys already exist as the pattern for making it a value.
- [ ] A check that the boundary holds — no harness name, model name or `CLAUDE_*` variable appears
      under `tooling/`. It is true today, and true-by-accident becomes false the first time someone
      reaches for convenience. This is the cheap half and it is worth doing even if no port ever
      happens.
- [ ] What a second adapter must supply is enumerated from the 16 files rather than guessed:
      skill equivalents, agent definitions, the hook surface, and a manifest.
- [ ] **Do not port before the kit has been validated once.** The brownfield trial has never run.
      Generalising an unvalidated design is `T-20260808-cluster-packs-are-generated-and-read-by-`
      at architecture scale — built at both ends, documented, never measured. This criterion is a
      sequencing constraint and exists to be argued with, not silently dropped.
- [ ] The rename to a generic identity is decided **with** this, not before it. The name should
      follow from what the kit proves to be; renaming twice is the avoidable cost.

## Notes

Filed 2026-08-19 from an audit that found the finding recorded in conversation and in a Note, but
nowhere a future reader would look.

Licence work is separate and already filed
(`T-20260818-relicense-from-mit-to-apache-2-0-while-s`) — Apache 2.0 is the right licence for a
multi-adapter end product, but it does not depend on the port and should not wait for it.

**The operator's stated goal** is a kit usable with Claude Code as a plugin and subsequently with
other coding agents. The measurement above says that goal is closer than it appears; this task
exists so the distance is recorded rather than re-derived by whoever picks it up.
