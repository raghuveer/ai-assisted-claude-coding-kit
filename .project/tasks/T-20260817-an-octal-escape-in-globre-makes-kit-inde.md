---
id: T-20260817-an-octal-escape-in-globre-makes-kit-inde
title: An octal escape in globre makes kit-index unparseable under POSIXLY_CORRECT
epic: portability
tier: T3
lang: bash
paths: tooling/kit-index.sh, docs/LESSONS.md
state: open
---

## Intent

`tooling/kit-index.sh:351`, inside `globre` — the glob-to-regex converter both tier-floor paths
depend on:

```awk
gsub(/\052+/, ".*", r)
```

Under `POSIXLY_CORRECT=1` the whole program fails to parse:

```
$ POSIXLY_CORRECT=1 bash tooling/kit-index.sh
awk: cmd. line:28: error: Invalid preceding regular expression: /\052+/
kit: task ingest read 0 of 109 task file(s); not read: …
kit: the task ingest did not complete; the index at .project/index.db was NOT rebuilt.
exit 1
```

**It fails safely**, which is why nobody noticed: the ingest refuses, the previous index is left
untouched, and the refusal is announced. This is not silent corruption.

**Reproduced against the parent commit `7c04bef`, so it predates the ADR 0004 work** — the same
error, the same exit code, from `git show 7c04bef:tooling/kit-index.sh`.

**It is this one construct, not a class.** Isolated 2026-08-17:

| regex | `POSIXLY_CORRECT=1` |
|---|---|
| `/\052+/` | **error** |
| `/\052/` | **error** — so the `+` is not the trigger |
| `/\052*/`, `/\052?/` | **error** |
| `/\001/`, `/\001+/`, `/\003.*$/` | fine |

The other octal escapes in this file (`\001`, `\003`, used as record and field separators) are
unaffected. A sweep of `tooling/`, `tests/` and `templates/` for octal escapes inside regex
literals found no other instance.

## What this does NOT establish, stated because it bounds the severity

**No supported platform is known to reject it at runtime.** CI is green on
`conformance (ubuntu-latest)` (mawk) and `conformance (macos-latest)` (BSD awk) on every recent
commit, so neither of the two awks the kit actually ships against has a problem with it. This is
a `gawk --posix` result, and `gawk --posix` is not any platform's awk.

**So the cost is not a broken build. The cost is that the kit's own pre-push check cannot be run
on its largest script.** `docs/LESSONS.md` §12 makes `POSIXLY_CORRECT=1` the partial-BSD
reproduction to run before pushing anything that shells out, on the evidence that it has already
caught two shipped defects that had turned `conformance (macos-latest)` red. That technique is
unusable against `kit-index.sh` — the file every session runs at `task-context` step 1 — because
it dies at parse time before reaching anything else. **A check that cannot be run on the code
most in need of it is the defect here**, and it is worth fixing for that reason rather than for a
portability failure nobody can demonstrate.

## Acceptance criteria

- [ ] `POSIXLY_CORRECT=1 bash tooling/kit-index.sh` completes and rebuilds the index, so §12's
      technique covers this file.
- [ ] The replacement is **proved equivalent, not assumed**. `/[*]+/` is a candidate and was
      checked on five realistic globs — `tooling/**`, `src/*.go`, `a/**/b`,
      `tooling/kit-index.sh`, `**` — producing byte-identical output under gawk and under
      `POSIXLY_CORRECT=1` gawk. Re-run that comparison as part of the fix rather than trusting
      this note, and include a glob containing no `*` at all, which is the case that must not
      change.
- [ ] **Do not "fix" the other octal escapes while here.** `\001` and `\003` are separator
      sentinels, they pass under POSIX mode, and rewriting them would be an unrequested change to
      the git-log reader for no demonstrated gain. If a sweep finds a genuine second instance,
      that is a finding; a tidy-up is not.
- [ ] A conformance step, or an addition to an existing one, that runs the affected converter
      under `POSIXLY_CORRECT=1`. Without it this regresses the next time someone reaches for an
      octal escape, and the whole point is that ordinary CI is green either way — **no existing
      check can fail on this**, which is why one has to be added rather than relied upon.
- [ ] `docs/LESSONS.md` §12 records the construct alongside the two argument-permutation cases it
      already carries, with the detection. It is a third instance of the same lesson and the
      section is where the next person will look.

## Notes

Found 2026-08-17 while running §12's own check against the scripts changed by
`T-20260817-kit-index-deletes-the-plan-so-task-conte`. `kit-plan.sh` and `kit-status.sh` both
pass under `POSIXLY_CORRECT=1`; only `kit-index.sh` fails, and it failed identically before that
work touched it.

Filed at T3 because `tier.rule: tooling/kit-index.sh T3` — the floor, not a judgement about the
size of the change, which is one character class.

Related: `T-20260731-remove-hex-escapes-from-awk-programs-so-` is the same family one escape
notation over, and its reasoning (macOS awk does not interpret hex escapes) is why this file
prefers octal in the first place. Any fix must not reintroduce hex.
