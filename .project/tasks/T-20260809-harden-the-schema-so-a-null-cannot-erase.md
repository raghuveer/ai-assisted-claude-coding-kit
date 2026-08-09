---
id: T-20260809-harden-the-schema-so-a-null-cannot-erase
title: Harden the schema so a NULL cannot erase a row or empty a section
epic: measurement
tier: T3
lang: sql
paths: tooling/schema.sql, tooling/kit-status.sh, tooling/kit-index.sh
state: open
---

## Intent

Four defects on 2026-08-09 were one SQL fact wearing four faces, and each was found separately,
late, by a different reviewer:

1. **`x NOT IN (set containing NULL)` is NULL, never true.** One NULL `task.id` took the escape
   residue count to zero and would have hidden EVERY orphaned escape, not merely its own — in the
   one query whose entire job is proving no escape can disappear.
2. **SQLite does not enforce `NOT NULL` on a `TEXT PRIMARY KEY`.** That is what made (1)
   reachable at all. `task.id` and `node.id` are both declared this way.
3. **`a||b` is NULL if either side is.** A NULL `node.id` blanked a whole rendered row, putting
   the printed count out of step with the rows and — as the only unresolved id — emptying the
   section outright while the residue line below still fired.
4. **The same, in spend.** `spend.scope` is nullable and `By scope` groups on a bare
   concatenation, so a NULL-scope row rendered as an empty `- ` bullet with its cost in no figure
   at all. Reproduced with 5.4M billable token-equivalents vanishing from a report that told the
   reader they were included.

Each was patched where it was found. That is four patches for one fact, and the fifth face has
not been looked for.

## The change

Move the invariant to the schema, where it holds for every reader at once, instead of asking each
query to remember. sqlite3 is 3.53 here, so `STRICT` tables are available.

- `STRICT` tables plus explicit `NOT NULL` on `task.id`, `node.id` and `spend.scope`.
- A rule that report queries never concatenate a nullable column bare — `COALESCE`/`format()`
  only — with a check that enforces it rather than a comment asking for it.

## Acceptance criteria

- [ ] `task.id` and `node.id` cannot be NULL. Prove by attempting the insert that worked before
      and asserting it is refused, not by reading the DDL.
- [ ] A conformance case seeds NULLs into every nullable column feeding a report and asserts that
      no section vanishes, no row blanks, and no printed count disagrees with the rows it
      describes. One case for the whole class — that is the point of doing this at the schema.
- [ ] The report queries are swept for bare concatenation of a nullable column, and the sweep is
      recorded. "None remaining" must be distinguishable from "did not look" — the fifth face is
      the one this task exists to find.
- [ ] `STRICT` does not break the ingest adapters. `docs/ADAPTERS.md` lets an adapter write rows
      directly, and a stricter schema can reject what a documented adapter emits. Check the
      shipped template before landing.
- [ ] The index fingerprint moves, and that is expected — `sqlite_master` stores DDL text
      verbatim. Say so in the commit, or the next reader will read a schema change as drift.

## Notes

Filed 2026-08-09 out of `docs/LESSONS.md` §7. T3 by the `tier.rule` floor on `kit-index.sh` and on
its own merits: this changes what the database will accept, and a migration that silently drops
or refuses existing rows would corrupt the record the whole kit is built to keep. `index.db` is
derived and disposable, which lowers the risk considerably — but `events.ndjson` is not, and it is
where the rows come from.
