---
id: T-20260816-the-accelerator-export-leaks-project-tex
title: The accelerator export leaks project text and its counts can be forged
tier: T3
lang: bash
paths: tooling/kit-accel.sh, tooling/kit_findings.py, tests/conformance.sh, SECURITY.md
state: open
---

## Intent

`SECURITY.md` §2 called the accelerator export "aggregate-only **by construction**", claiming it
"*cannot* return finding text, file paths, task ids or titles, because those columns are not in
it", and concluded this "is what makes cross-project promotion safe to run against client work".

The SELECT list is genuinely narrow, and that part holds. But **the columns it does select are
free text authored by a model**, and the export writes its JSON with `printf`. Two consequences,
both reproduced 2026-08-16 in a throwaway clone.

**1. Project text crosses the boundary.** `lang` (0-40 chars) and `pattern` (0-60 chars) have no
vocabulary — `kit_findings.py` constrains only `class` and `severity`. `domain` is dropped unless
the project declared one; the other two are not:

```
$ sqlite3 .project/index.db "UPDATE finding SET lang='ACMEBANK-ledger-service' WHERE lang='bash';"
$ bash tooling/kit-accel.sh export
$ grep ACMEBANK .project/accelerator-export.ndjson
{"kind":"technology","key":"ACMEBANK-ledger-service","class":"compliance","n":5,...}
```

**2. The counts can be forged, and the line stops being JSON.** `sanitise()` strips quotes,
backslashes and control characters — it does **not** strip `|`, which is exactly the separator
`kit-accel.sh:211` splits sqlite3's output on (`IFS='|' read -r kind key class n vind refuted`).
`n`, `vindicated` and `refuted` are then printf'd as **bare, unquoted** JSON numbers:

```
$ python -c "...; print(sanitise('retry|9999|9999|0'))"   ->  retry|9999|9999|0     # pipe survives
$ sqlite3 ... "UPDATE finding SET pattern='retry|9999|9999|0' WHERE pattern<>'';"
$ bash tooling/kit-accel.sh export ; grep retry .project/accelerator-export.ndjson
{"kind":"pattern","key":"retry","class":"9999","n":9999,"vindicated":0,"refuted":correctness|35|0|0,"project":"p28...","kit":"0.8.0"}
$ ... | python -c "import json,sys; json.loads(sys.stdin.read())"
INVALID JSON: Expecting value: line 1 column 82
```

`n:9999` against a true count of **35**. The promotion ladder runs on those counts, and the file is
the cross-project artefact — so a value a reviewer typed into one project sets the evidence weight
of a shared accelerator, or breaks the consumer that parses it.

## Acceptance criteria

- [ ] **The export cannot be broken by any value in a column it selects.** Feed hostile `lang`,
      `pattern` and `domain` values through the **real door** (`kit-finding.sh --json`, not an
      `UPDATE`) and assert every emitted line parses as JSON and its counts match the database.
      Must go RED when the fix is reverted.
- [ ] **The separator is not a parsing assumption.** Splitting sqlite3's default `|` output is the
      root of the count forgery. Prefer a mode that cannot collide with content — `-json`, or a
      separator that is refused in input — over adding `|` to the sanitiser. **If `|` is added to
      `sanitise()` instead, say why, and note that it silently rewrites data on the way into the
      log to protect a consumer three steps downstream.**
- [ ] **The export stops hand-rolling JSON.** `SECURITY.md` §5 rule 2 says serialisation belongs in
      `kit_findings.py`; §4 now lists the export among the printf writers and — the sweep's own
      gap — gave it no escaping verdict while grading the other four. Its verdict is the same as
      `kit-vindicate.sh`'s: escapes nothing, interpolates model text.
- [ ] **The claim in `SECURITY.md` §2 is rewritten to the truth**, which is narrower and worth
      stating precisely: the export cannot return *summary, file path, task id or title* because
      those columns are not selected — and it **can** return `lang`, `pattern` and `domain`
      verbatim, which are model-authored free text. The "safe to run against client work"
      conclusion does not follow from the premise and must not survive unqualified.
- [ ] **Decide whether `lang` and `pattern` should be free text at all.** They are the axes the
      accelerators are built from; unconstrained, they are also the leak. A vocabulary, a charset,
      or an operator review step before export are all answers — "reviewers will type sensible
      values" is not, and is the assumption that produced this.

## Notes

Found by the security reviewer during the T2 review of
`T-20260815-security-md-claims-allowedtools-enforces`; both halves reproduced independently before
being accepted.

**The demonstration that was supposed to prove this claim seeded `summary`, `file_path` and
`task_id` — three columns the query does not select.** It proved the SELECT list, which nobody
doubted, and said nothing about the three columns it does. That is the exact shape new §5 rule 8
forbids, committed in the same change that wrote the rule.

**Both halves are reachable through the sanctioned path — confirmed end-to-end, not inferred.**
The text leak needs nothing but a reviewer typing a client name into `pattern`; that is the
*intended* use of the field. The count forgery was reproduced through the real door, with no
direct `UPDATE` anywhere:

```
$ printf '%s' '{"findings":[{"class":"perf","severity":"major","summary":"a summary long enough to pass",
    "lang":"bash","pattern":"retry|9999|9999|0"}]}' \
    | bash tooling/kit-finding.sh --task <id> --agent security-reviewer --json    # run twice, HAVING COUNT(*)>=2
kit: recorded 1 finding(s) from structured output
$ bash tooling/kit-index.sh && bash tooling/kit-accel.sh export
{"kind":"pattern","key":"retry","class":"9999","n":9999,"vindicated":0,"refuted":perf|2|0|0,...}
```

`n:9999` against a true count of **2**. A reviewer agent needs only to put a `|` in `pattern` —
a 17-character value — to forge the promotion counts of a shared, cross-project accelerator and
emit a line that is not valid JSON. No privileged access, no crafted encoding, one ordinary field.

This is the one finding whose blast radius is other people's repositories: the export exists to be
promoted across projects, so a bad line does not stay local. `kit.export_salt` protects the project
*handle*, not the payload.
