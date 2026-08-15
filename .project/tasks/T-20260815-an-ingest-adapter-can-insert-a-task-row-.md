---
id: T-20260815-an-ingest-adapter-can-insert-a-task-row-
title: An ingest adapter can insert a task row the invariant comment forbids
tier: T3
lang: bash
paths: tooling/kit-index.sh, docs/ADAPTERS.md, SECURITY.md
state: open
---

## Intent

`kit-index.sh` §4 carries a long comment explaining why a `Task-Id` with no file gets a `node`
and not a `task` row. Its last paragraph names the invariant a future reader is meant to rely on:

> WHERE THE RULE ACTUALLY LIVES, since this is the third thing a reader looks at and the first
> two were misleading: `task` rows come from section 2 and from nowhere else — one INSERT per
> parsed FILE. There is no statement here that admits a task, so a file is the only way in.

That is true of §4 and of the built-in path. It is **not true of the pipeline**. §3b runs
`ingest.extra` adapters, which emit arbitrary SQL into the same stream, before any derivation:

    for _spec in $(kit_cfg_all "$PROFILE" ingest.extra); do
      run_adapter "$_spec" emit || { ADAPTER_FAILED=1; break; }
    done

Nothing constrains what an adapter emits, so an adapter can `INSERT INTO task`. A file is
therefore not the only way in, and the comment that exists specifically to stop the next reader
being misled is itself the third misleading thing.

The blast radius is the same one the comment is about: a task row with no file lands in the Open
list, the backlog count and the escape-rate denominator, and `delete the index and rebuild` no
longer round-trips through committed text — the row's only home is the adapter's source.

Found by the blind approach reviewer on 2026-08-15 while reviewing
`T-20260814-one-entry-mechanism-brownfield-is-the-ge`, as a correction running the OTHER way to
that design's Option 1 rejection: the rejection is sound and better motivated than it stated,
because the invariant it appeals to is weaker than the comment claims.

## Acceptance criteria

- [ ] The comment states the rule that actually holds across the whole pipeline, or the pipeline
      is changed so the stated rule holds. Naming §3b in the comment is the minimum.
- [ ] If the fix is mechanical, a fixture with an adapter that emits `INSERT INTO task` proves
      what happens, and the assertion is a PRESENCE — the refusal is observed, not inferred from
      the row being absent for some other reason.
- [ ] `docs/ADAPTERS.md` states what an adapter may and may not emit. It currently documents the
      contract without bounding the SQL.
- [ ] The same sweep covers `event` and any other table §4 assumes it alone populates.

## Notes

Filed 2026-08-15 out of the entry-mechanism approach reviews.

Do not "fix" this by adding a guarded INSERT back into §4 — that exact move was made, measured,
found to be dead code and deleted, and the comment records it. The defect is in the claim, and
possibly in the adapter seam's freedom, not in §4's absence.

Tension worth naming before choosing: bounding adapter SQL means parsing or whitelisting it,
which is a second implementation of a standard inside a kit that has already rejected that shape
once (the JSON Schema decision). The cheap honest fix may be the comment plus a documented
adapter obligation, with the trust boundary stated in `SECURITY.md` alongside the other
convention-only items.
