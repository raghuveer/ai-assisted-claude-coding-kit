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

## Candidate tasks

- [ ] Both front-door documents promise no language runtime — "no Node, no Python, no PowerShell", with `validate.py` named as the one exception "never run by the kit itself". `kit-finding.sh` `exec`s `python3` on its ordinary path, four times. A Go or Rust team following INSTALL adopts a hard Python dependency the page told them they would not need.
      evidence: INSTALL.md:8, INSTALL.md:13, README.md:207, tooling/kit-finding.sh:41, tooling/kit-finding.sh:123
      kit-task.sh --title 'Two install documents promise no language runtime while kit-finding execs python3' --tier T1

- [ ] `kit-status.sh` justifies escaping the `kind` field on the grounds that "`Task-Status:` is checked against no vocabulary -- unlike `Via:`, which is checked". Both are checked, in the same file, ten lines apart, by the same shape. `tests/conformance.sh` repeats the claim. The escaping is right; the reason given for it is false, and it is the reason a future maintainer will use to decide which other fields need hardening.
      evidence: tooling/kit-status.sh:95, tooling/kit-trailers.sh:113, tooling/kit-trailers.sh:123, tests/conformance.sh:1213
      kit-task.sh --title 'A comment contrasts Task-Status with Via as unchecked when both are checked' --tier T0

- [ ] The handoff's current-state section says `v0.2.0` where `plugin.json` says 0.8.0, "14 scripts" where `tooling/` holds 22 entries, omits five shipped scripts from its script list, and names seven of the sixteen things now under `docs/`. It is the document a second person reads first.
      evidence: docs/HANDOFF.md:274, docs/HANDOFF.md:278, docs/HANDOFF.md:286, .claude-plugin/plugin.json:3, .project/entry-facts.tsv
      kit-task.sh --title 'Handoff current state names version 0.2.0 and 14 scripts against 0.8.0 and 22' --tier T1

- [ ] `entry-facts.tsv` carries no column saying whether a file was scanned for comments, so `comment_lines 0` means "no comments found", "extension not on the scan list", or "deliberately not scanned" — indistinguishable. `legacy-sync-agents.ps1` is 231 lines and reports 0. The report's prose admits the gap in general; the table a reader greps does not.
      evidence: tooling/kit-entry.sh:269, tooling/kit-entry.sh:307, .project/entry-facts.tsv, .project/entry-report.md:46
      kit-task.sh --title 'Comment counts of zero do not say whether the file was scanned' --tier T2

- [ ] The scan list is fifteen extensions plus a `#!` fallback. `.ps1`, `.cs`, `.kt`, `.swift`, `.php`, `.scala`, `.lua`, `.ex`, `.r`, `.m` are absent, and `tok()` would recognise the comment style of most of them. On a .NET or Kotlin subject the census reports zero rationale everywhere, which is the failure mode the uncapped design was built to avoid. This repository holds the live instance.
      evidence: tooling/kit-entry.sh:270, tooling/kit-entry.sh:284, .project/entry-facts.tsv
      kit-task.sh --title 'The comment scanner skips ps1 cs kt swift php and every unlisted language' --tier T2

- [ ] Marker detection matches nine manifests and misses `build.gradle`, `settings.gradle`, `Makefile`, `CMakeLists.txt`, `Gemfile`, `composer.json`, `setup.py`, `mix.exs`. A Gradle or Rails subject gets `markers 0` under a line that reads "this is a measured zero, not an absent scan" — the report asserting confidence it has not got. Gradle in particular is the build system modernization work lands on.
      evidence: tooling/kit-entry.sh:357, .project/entry-report.md:23
      kit-task.sh --title 'Marker detection misses gradle make gemfile and composer so markers 0 misreads' --tier T1

- [ ] `cochange_degree 0` appears on 22 of 81 rows against a non-empty graph, and has three causes: the file was hub-suppressed, its only commits exceeded `commit_cap`, or it genuinely pairs with nothing. `tests/conformance.sh` at 51 commits and `tooling/kit-index.sh` at 33 read identically to a file nobody has touched. The filed defect covers the *empty table*; this is a per-file zero in a populated one.
      evidence: .project/entry-facts.tsv, tooling/kit-index.sh:638, tooling/kit-index.sh:670, .project/entry-report.md:12
      kit-task.sh --title 'A cochange degree of zero conflates hub suppression bulk commits and no pairing' --tier T2

- [ ] The predicate that decides whether a refutation is unambiguous is hand-written four times — in the status report, the pre-flight gate, the resolve listing, and again inside the fixture that checks them. `kit-status.sh` names the duplication in a comment and leaves it. The fixture compares status against pre-flight in one scenario; `kit-resolve.sh` is compared against neither, and a fifth caller would be copied from whichever file the author happened to open.
      evidence: tooling/kit-status.sh:509, tooling/kit-status.sh:514, tooling/kit-preflight.sh:87, tooling/kit-resolve.sh:91, tests/conformance.sh:1659
      kit-task.sh --title 'One refutation predicate is hand copied into four files with no agreement test' --tier T2

- [ ] Every row mixes two states: `lines`, `comment_lines` and `comment_blocks` come from the working tree, `commits`, `first`, `last` and `authors` from committed history. Run on a dirty tree — as this one was, with six modified files including `kit-entry.sh` itself — the halves of a row describe different repositories, and nothing in the report says which. `kit-init.sh` already reasons about derived artefacts perturbing their own measurement.
      evidence: tooling/kit-entry.sh:293, tooling/kit-entry.sh:331, tooling/kit-entry.sh:371, tooling/kit-init.sh:87
      kit-task.sh --title 'The entry report does not say whether the tree was clean when it ran' --tier T1

## Could not determine

- **Most of what the census surfaces is already filed, and that is the headline result.** 96 task files, ~76 open. Everything the facts pointed at in `kit-index.sh`, the trailer path, the findings loop, the accelerator ladder, conformance portability, and adoption footprint already has a task. The nine above are what survived checking each against that backlog. Three near-misses I deliberately did not re-file: the empty co-change table (already `T-20260815-co-change-withheld-disabled-and-empty-ar` — candidate 7 is the per-file zero, not the empty table), the root-dotfile exclusion (already filed, and the fix has landed), and `kit-index.sh` decomposition.

- **The docs corpus contributed nothing to the census.** 47 of 81 files are `.md`, all scanned=0 by design, so 0 of the 600 comment runs come from them. Everything I found in `README.md`, `INSTALL.md`, `HANDOFF.md` and `VERSIONING.md` I found by reading, not by following a fact. On a repository the tool itself estimates is a sixth non-comment rationale, that is a large blind area and the proposal's coverage of it is unbounded and unclaimed.

- **The co-change arithmetic is modelled, not measured.** I could not run `sqlite3` in this session — the call was refused — so the hub threshold that explains `tests/conformance.sh` at degree 0 is derived from `kit-index.sh:670` plus the degrees in the facts table, bracketing `cochange_commits` between 115 and 165. I did not read `cochange_pairs`, `cochange_files` or `cochange_avg_degree` from `meta`.

- **Nothing about ownership, review load or bus factor is derivable here.** `authors` is 1 on all 81 rows and `merges` is 0, so the column is constant and the merge caveat is inert. Whether that is permanent or an artefact of pre-team-mode is question 7's neighbour and the facts cannot settle it.

- **I sampled the comment runs, I did not read them.** I read the five longest, the `kit-entry.sh` header, and greped the rest for specific claims. 261 runs in `tests/conformance.sh` alone went unread. There is almost certainly more of what candidate 2 turned out to be — a correct control with a wrong reason attached — and I have no basis for saying how much.

- **Dormant versus dead is not a fact the census can produce.** `legacy-sync-agents.ps1`, `legacy-commands/`, `templates/*.LEGACY.*` and the three seeded accelerators all read as one commit, degree 0, untouched — which is equally consistent with "kept deliberately" and "forgotten". The documents say the first; the facts cannot confirm it, which is why it is question 7 and not a candidate.

- **Test coverage is not in the facts at all.** No column links a source file to the fixture covering it, so "is this change tested" — the question two open tasks are about — is unanswerable from the census. For candidates 4, 5, 7 and 8 I asserted no coverage claim either way.

- **Candidate 1's tier is contingent on question 2.** If the answer is "documents only", T1 is right. If it is "add a dependency check to pre-flight or `kit-init.sh`", it is a code change on an adoption path and should be re-tiered before anyone starts.
