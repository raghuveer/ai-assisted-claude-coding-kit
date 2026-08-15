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

- [ ] The claim moves out of "What is enforced mechanically" and into the convention-only section,
      beside "nothing stops a committer self-certifying", **or** an actual gate is built and the
      claim stays. Not both, and not neither.
- [ ] If a gate is built it can FAIL, and a test proves it: a reviewer invocation that attempts a
      write or a shell command is refused, and the test is red when the gate is removed. A gate
      that merely re-states `--allowedTools` is the same defect with more words.
- [ ] The sweep, not the instance (`LESSONS` §4): every other claim in the "enforced mechanically"
      section is re-verified by demonstration rather than by reading, and each one that turns out
      to be convention moves. The section currently also claims one JSON writer,
      sanitise-then-assert, aggregate-only export, and that no model output is executed.
- [ ] `agents/*-reviewer.md` frontmatter `tools:` is stated for what it is — a declaration the
      harness may or may not enforce — wherever the kit relies on it.
- [ ] Whatever the outcome, the operator's runbook for spawning reviewers says plainly what is and
      is not prevented, so the next session does not re-derive this from a transcript.

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
