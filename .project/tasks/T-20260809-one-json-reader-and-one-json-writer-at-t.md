---
id: T-20260809-one-json-reader-and-one-json-writer-at-t
title: One JSON reader and one JSON writer at the two boundaries that touch JSON
epic: portability
tier: T2
lang: bash
paths: tooling/kit-spend.sh, tooling/kit-finding.sh, tooling/kit-review-findings.sh, tooling/kit-index.sh
state: open
---

## Intent

The kit reads JSON with `awk` and writes it with `printf`, and on 2026-08-09 that produced the
worst defects of the session:

- **The transcript envelope leaked into the log.** The last line of a harvested findings block
  picked up the trailing `"}]}}` from the surrounding JSON, and `kit-finding.sh` interpolated it
  into an event line unescaped. The result is a malformed record, appended to a log that is
  **append-only and committed**, with the `pattern` column — the field the technology accelerator
  is derived from — silently truncated.
- **Backslashes corrupted fields.** `sed 's/\\n/\n/g'` turns a literal backslash before `n` into
  a newline, splitting one finding into a truncated row and an unparseable fragment that is
  dropped with no warning.
- **Nothing escapes what it writes.** `record()` in `kit-finding.sh` interpolates every field into
  the event JSON with no escaping. An `esc()` helper exists in `kit-review-findings.sh` and is
  applied only to the gap event.

There are now **two hand-rolled readers** — `jf()` duplicated in `kit-spend.sh` and
`kit-review-findings.sh`, the second copied from the first on 2026-08-09 — which is the
duplicate-then-drift shape this kit has already been burned by: the finding vocabulary was
restated in four places, drifted, and reviewers emitted values the recorder discarded.

**The constraint that justified hand-rolling is not real.** `python3` is already a hard
dependency: `validate.py` sits in the repository root and CI runs it. The kit is not
dependency-free today, and pretending otherwise bought three defects.

## The change

One reader and one writer, used everywhere JSON is touched — which is only two boundaries: hook
payloads/transcripts, and `events.ndjson`. Everything else stays shell.

Whether that is a small `tooling/kit-json.py` or a single audited shell implementation is the
decision to make; the requirement is that there is exactly ONE of each, and that neither is
reimplemented inline again.

## Acceptance criteria

- [ ] Exactly one JSON reader and one JSON writer exist in `tooling/`. A conformance check
      asserts it, the way the via-vocabulary check already asserts a single definition — the
      drift this prevents is the same drift, and it has happened here before.
- [ ] The writer escapes `"`, `\`, and control characters. `events.ndjson` stays parseable line by
      line whatever a reviewer, a trailer or a filename contains.
- [ ] The reader decodes `\n`, `\"`, `\\` and `\t` correctly and does not confuse a literal
      backslash for an escape. Prove it with the exact input that broke: a field containing
      `C:\new-handling`.
- [ ] A transcript's surrounding envelope cannot reach a recorded field. Prove it with the input
      that broke: a findings block whose last line is followed by `"}]}}`.
- [ ] If Python is chosen, the dependency is DECLARED where an adopter reads it — `INSTALL.md`
      and `docs/ADAPTERS.md` — not left as a surprise. If shell is chosen, say why, and put the
      reasoning where the next person to reimplement it will look.
- [ ] Existing `events.ndjson` files are still readable. This log is committed history; a reader
      that rejects a line written last month is a regression, and one malformed line already
      exists from the defect above.

## Notes

Filed 2026-08-09 out of the retrospective — `docs/LESSONS.md` §7. This is the one place where the
"shell + regex" stack was straightforwardly the wrong tool rather than merely sharp: regex on a
structured format. Everywhere else the injuries came from interpolating untrusted text into
patterns, which is filed separately as
`T-20260809-lint-the-kit-for-untrusted-text-interpol`.

Interacts with `T-20260801-nothing-invokes-kit-finding-so-the-findi`: if the harvester is
replaced by structured output from the reviewer, the READ side of this task shrinks to hook
payloads only. Do that task first and this one gets smaller — which is the point of §5, prefer
deleting a component to hardening it.
