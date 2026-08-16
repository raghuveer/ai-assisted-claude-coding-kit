---
id: T-20260815-security-md-claims-allowedtools-enforces
title: SECURITY.md claims allowedTools enforces reviewer read-only and it does not
tier: T2
lang: bash
paths: SECURITY.md, agents, tests, docs
state: open
---

## Intent

`SECURITY.md:40-45`, under the heading **"What is enforced mechanically"**, says:

> **Reviewers cannot write.** `approach-reviewer`, `implementation-reviewer` and
> `security-reviewer` are granted `Read, Grep, Glob` and nothing else. This is enforced at
> invocation (`--allowedTools`), not requested in prose.

**The second sentence is false.** Demonstrated 2026-08-15 while running the third approach review
of the entry mechanism. The reviewer was launched with exactly
`--allowedTools "Read,Grep,Glob" --disallowedTools "ReportFindings"` and its transcript contains a
`Bash` `tool_use` — `ls .../tooling/` — with `is_error: false` and a real directory listing
returned. Tool counts for that session: `Read` 21, `Grep` 3, **`Bash` 1**.

Three live reviews ran under this claim that day. None of them wrote anything, and the one that
used `Bash` disclosed it in its own "what I did not check" section — which is the only reason it
was noticed. **A control whose violation is detected only when the violator volunteers it is not
a control.**

Why this is worse than a documentation error: `SECURITY.md` separates *enforced mechanically* from
*convention only* precisely so a reader can tell which properties survive an actor who does not
cooperate. A false entry in the first column is worse than no entry at all, because it stops the
reader looking for the real control. The kit's own stated reason for read-only reviewers is that
"a reviewer that can edit what it reviews is not an independent check" — and today it can.

## Acceptance criteria

- [x] The claim moves out of "What is enforced mechanically" and into the convention-only section,
      beside "nothing stops a committer self-certifying", **or** an actual gate is built and the
      claim stays. Not both, and not neither.
      → **Moved.** `SECURITY.md` §3 opens with "Reviewer read-only is a convention", carries the
      transcript evidence, and states that neither frontmatter nor `--allowedTools` binds. No gate
      was built; see the next criterion for why that is a deliberate choice and not a shortfall.
- [~] If a gate is built it can FAIL, and a test proves it: a reviewer invocation that attempts a
      write or a shell command is refused, and the test is red when the gate is removed. A gate
      that merely re-states `--allowedTools` is the same defect with more words.
      → **Not applicable: no gate was built**, so there is nothing for this to hold to. Recorded
      `[~]`, not ticked, because a criterion satisfied by an absent component is satisfied by
      nothing. **The gate is still wanted and is separate work** — the only shape that would bind
      is a PreToolUse hook denying `Bash` in the reviewer's own session, which means changing how
      the operator spawns reviewers, not changing this repository's documents. Proposed as a
      follow-up task rather than smuggled in here.
- [ ] The sweep, not the instance (`LESSONS` §4): every other claim in the "enforced mechanically"
      section is re-verified by demonstration rather than by reading, and each one that turns out
      to be convention moves. The section currently also claims one JSON writer,
      sanitise-then-assert, aggregate-only export, and that no model output is executed.
      → **Swept, 2026-08-16. Six claims; two failed, one was vacuous, four held.** Each surviving
      entry now carries its demonstration inline. Findings:
      · **one JSON writer — FALSE.** Five shell sites build JSON with `printf`.
        `kit-vindicate.sh --class 'style","kind":"spend",…'` appended a line with a duplicate
        `kind` and a fabricated `tok_in`; the awk indexer read it as a `vindication`, a JSON parser
        as a `spend`, so one log counts 11 or 12 spend events depending on the reader. Claim
        narrowed to findings and fix-marks; the gap is now §4. **Filed separately — see Notes.**
      · **solution overlay never exported — VACUOUS.** Zero `overlay` references in `tooling/`;
        the component is unbuilt, so nothing could export one. Moved to §4 as untested.
      · **sanitise-then-assert — HELD, mutation-proven.** Injection neutered; with `sanitise()`
        stubbed to `return text` the write was refused. The control can fail.
      · **aggregate-only export — HELD, demonstrated.** 316 finding rows seeded with client
        markers in `summary`, `file_path` and `task_id`; zero markers in the export.
      · **no model output executed — HELD, but by search only.** Labelled as the weakest entry in
        the section, in its own entry, rather than sharing the confidence of the other four.
      · **writes confined to root — HELD, and it can fail.** Outside path exits 2, inside exits 0;
        a `Bash` payload exits 0 unexamined, which §3 already said and this confirmed.
- [ ] `agents/*-reviewer.md` frontmatter `tools:` is stated for what it is — a declaration the
      harness may or may not enforce — wherever the kit relies on it.
      → `docs/agents-README.md` gains "**`tools:` is a declaration, not a boundary**" in the
      Structure section that documents the frontmatter, and `SECURITY.md` §3 and §4 say the same.
      **Deliberately NOT added to the reviewer prompts themselves.** Those files say "read-only by
      design", which is a true statement of intent; telling a reviewer in its own system prompt
      that the restriction does not bind would weaken the behavioural shaping that is currently
      the only thing working. The kit *relies* on the grant in its documents, not in the prompts.
- [ ] Whatever the outcome, the operator's runbook for spawning reviewers says plainly what is and
      is not prevented, so the next session does not re-derive this from a transcript.
      → `tooling/kit-review-record.sh` gains a "WHAT `--cmd` DOES NOT PREVENT" block in its header,
      which is the one place that knows how a reviewer is invoked. It names what a reviewer can
      still do, what is genuinely enforced, and what to do instead when independence has to
      survive an uncooperative reviewer (isolate the process, diff the tree).

## Notes

Filed 2026-08-15 out of the third approach review of
`T-20260814-one-entry-mechanism-brownfield-is-the-ge`.

**Do not treat "the reviewer disclosed it" as a mitigation.** It is evidence that the disclosure
habit is worth keeping, and nothing more. The next reviewer may not disclose, and a reviewer is
not the only actor launched this way.

Related and NOT the same thing: `T-20260801-reviewer-agents-cannot-run-the-tools-the` is about
agents being *instructed* to use tools their frontmatter does not grant — the opposite direction.
This one is about a grant that does not bind. Both point at the same underlying fact: nothing in
this kit verifies that a declared tool set matches the tool set an agent actually has.

The verification method is cheap and repeatable and should go in the task's own evidence: launch
`claude -p --allowedTools "Read,Grep,Glob"`, ask for a shell command, then read the session
transcript under `~/.claude/projects/<mangled-path>/<session>.jsonl` for `tool_use` entries and
their `is_error`. Do not take the agent's own account of what it ran.

## Sweep spillover — proposed, not filed

Two defects surfaced by the sweep that are **not** this task's to fix. Filed separately per the
"file don't fold" rule; recorded here so they are not lost if the operator defers them.

1. **`kit-vindicate.sh` interpolates `--task` and `--class` into JSON unescaped**, and
   `kit-event.sh` splices its third argument in as raw JSON. This is the critical that
   `kit_findings.py` was built to close, still live in the paths the fix did not cover.
   Reproduction is one line and is in `SECURITY.md` §4.
2. **A PreToolUse gate that would actually bind a reviewer to read-only** — the work AC2 above
   describes but does not require. It changes the reviewer invocation, not this repository.

## T2 review, 2026-08-16 — REVISE and REJECT. Three ACs un-ticked.

Two blind reviewers, run before closing. Verdicts **REVISE** (implementation) and **REJECT**
(security). Every critical below was then reproduced independently before being accepted.

**All five claims left in §2 are false.** The sweep that AC3 asked for was performed by checking
which scripts emit those event kinds *by literal name*, not which paths can *produce* them:

- **one JSON writer (findings/fix-marks)** — `kit-event.sh T-fake finding-fixed '{"finding":"<id>",
  "fixed":1,...}'` forged a fix-mark; after reindex `fixed_at` went NULL → set. `kit_findings.py`
  never ran. A fix-mark is the artefact `.claude/CLAUDE.md` reserves to the operator.
- **every string is sanitised** — same route bypasses the sanitiser AND the closed vocabulary.
- **export cannot return project text** — `lang`/`pattern` are unconstrained free text and cross
  intact. `sanitise()` does not strip `|`; the export splits sqlite3 output on `|`, so a crafted
  `pattern` forged `"n":9999` (truth 35) and emitted a line that is **not valid JSON**.
- **writes confined (Write, Edit, NotebookEdit)** — `NotebookEdit` carries `notebook_path`, not
  `file_path`. Guard exits 2 on Write-outside and **0 on NotebookEdit-outside**: fails open on a
  tool §2 names explicitly.
- **no model output is executed** — an adapter script plus one `ingest.events` profile line, both
  written *inside* the root where the guard permits by design, executed on the next `kit-index.sh`.

**The defect is one shape repeated.** Every `*Demonstrated:*` line seeded inputs the control
handles: the export demo seeded three columns the query does not select; the guard demo exercised
`Write` and inferred `NotebookEdit`. New §5 rule 8 — "a check that passes on hostile input and on
benign input alike proves nothing" — is violated by the evidence directly above it.

AC3, AC4 and AC5 are un-ticked, having been ticked on that failed sweep. AC4 fails on
`docs/MEASUREMENTS.md:57-64`, which still asserts the grant binds and rests a recorded measurement
on it. AC5 fails because the reviewer runbook is `skills/verify-ladder/SKILL.md`, not a header
comment in `kit-review-record.sh`.

**AC1 stands.** Neither reviewer disputed the relocation of the `--allowedTools` claim to §3.

**The one load-bearing fact nobody can re-run:** the original transcript showing the reviewer's
`Bash` call. Both reviewers flagged that every restatement of it rests on the author's word.
