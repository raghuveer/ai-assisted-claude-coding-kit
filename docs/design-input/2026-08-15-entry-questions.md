# Entry questions — 2026-08-15, self-ingest

Produced by the entry mechanism reading THIS repository: `kit-entry.sh` gathered the facts,
`researcher` read them and returned this, the orchestrator wrote it. `kit-entry.sh --check`
passed on the returned proposal on the first attempt — 8 questions, 9 candidates.

The candidate list is NOT here. It is derived and disposable, at `.project/entry-candidates.md`,
and gitignored. Questions are committed because they are a durable record of what was asked;
candidates stop mattering once confirmed or discarded. Two lifetimes, two files.

An answered question becomes a decision record under `paths.adr` via `adr-scribe`. Answering
one here, in place, is also fine — the `answer:` slots are why they are blank.

---

## Open questions

1. Is `docs/HANDOFF.md` §6 a living inventory of the tree, or a dated snapshot of the 0.2.0 handoff that should be labelled as one? The answer decides whether candidate 3 is a correction or a retitle.
   evidence: docs/HANDOFF.md:268, docs/HANDOFF.md:274, .claude-plugin/plugin.json:3
   answer:

2. `python3` is a hard runtime dependency of the findings loop, not an authoring check. What is the floor version, and when `python3` is absent should `kit-finding.sh` fail loudly or degrade? It currently `exec`s and inherits whatever the shell does.
   evidence: tooling/kit-finding.sh:41, tooling/kit-finding.sh:123, docs/LESSONS.md:123, INSTALL.md:8
   answer:

3. `.gitattributes` is excluded from the census whole, as kit-owned — but `kit-init.sh` only *appends* one line to it, and this repository's own `.gitattributes` was independently nominated as load-bearing rationale before the entry mechanism existed. Should a file the kit appends to be excluded entirely, counted, or given a third label?
   evidence: tooling/kit-entry.sh:166, tooling/kit-init.sh:104, docs/design-input/2026-08-15-entry-mechanism-2.md:280
   answer:

4. The hub cap at 20% was tuned on a microservices repository, where the suppressed hubs were "a roadmap doc, `docker-compose.yml`, service entry points". Here it suppresses `tests/conformance.sh` (51 commits) and `tooling/kit-index.sh` (33) — the two highest-churn *source* files. Is a kit-shaped repository the hairball case the cap exists for, or the case where it discards the signal?
   evidence: tooling/kit-index.sh:670, docs/DESIGN-NOTES.md:407, .project/entry-facts.tsv
   answer:

5. What is `doc_shaped` for? On this repository it is 1 for every `.md` file and for nothing else except one `.txt` under `docs/`, so on a 47-of-81-markdown tree it is a restatement of `ext`. What decision is a reader meant to make with it that `ext` does not already support?
   evidence: tooling/kit-entry.sh:259, .project/entry-facts.tsv, .project/entry-report.md:28
   answer:

6. `tests/conformance.sh` is 2832 lines with 261 comment blocks and the most commits of any file. `kit-index.sh` has a filed decomposition task; the suite does not. Is the suite's single-file shape a deliberate choice, and if so what is the reason that does not also apply to `kit-index.sh`?
   evidence: tests/conformance.sh:1, .project/entry-facts.tsv, tooling/kit-index.sh:30
   answer:

7. Six files are kept "for reference, not wired up" — `legacy-sync-agents.ps1`, three `legacy-commands/`, two `templates/*.LEGACY.*`. All are one commit, 2026-07-29, untouched since. What condition retires them, or is the reference value permanent?
   evidence: docs/MIGRATION.md:16, docs/MIGRATION.md:25, docs/agents-README.md:74
   answer:

8. `plugin.json` reads 0.8.0, last touched 2026-08-08. Four scripts and a schema change have landed since, all MINOR by the table in VERSIONING. Does the version move only at release, or is a bump owed now?
   evidence: .claude-plugin/plugin.json:3, docs/VERSIONING.md:33, docs/VERSIONING.md:105
   answer:

