---
id: T-20260808-a-malformed-tier-rule-glob-silently-empt
title: A malformed tier.rule glob silently empties the task index
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

`globre` (`tooling/kit-index.sh:178`) turns a `tier.rule` glob into a regex by escaping
`[.^$+(){}|]`. It does not escape `[`, `]` or `\`. An unbalanced bracket or a `\(` therefore
compiles to an invalid regex, awk takes a **fatal** mid-pass, and the task-frontmatter
ingest dies part way through — leaving the tasks it had already emitted and dropping every
one after.

Reproduced on 2026-08-08. Profile with `tier.rule: src/[ab T3`, four task files each
declaring `tier: T3` and `paths: src/a.go`:

    exit=0
    awk: fatal: invalid regexp: Unmatched [ : /^src/[ab$/
    tasks indexed: 1   (4 expected)
    T-1|NULL|NULL      tier and floor both gone

**`kit-index.sh` exits 0.** The DB is written, its path is printed, and the run reads as a
success. The only signal is one line on stderr, and the conformance step that builds an index
discarded it with `2>&1` until this was found.

`globre` is only reached for tasks that declare `paths:`. Without that, the same typo is
quieter still: every task indexes, and every `tier_floor` is silently NULL — a floor that
does not apply rather than one that fails.

## Why this is T3 and not a papercut

The trigger is a typo in a documented config field, not an attacker. The consequence is that
the tier floor — the control that decides how many reviewers a change gets — stops applying,
and the backlog reads as shorter than it is. `docs/MEASUREMENTS.md` §B.4 already records that
two of three recorded tiers were too low and that under-tiering is the dangerous direction;
this makes the mechanism that was built to catch it fail open, without saying so.

`tooling/kit-index.sh` also carries a T3 floor of its own in this project's profile.

## Acceptance criteria

- [x] A malformed glob cannot empty or truncate the index. Either escape the remaining regex
      metacharacters in `globre`, or validate the rule and skip it with a `kit_warn` naming
      the rule — but a rule the kit cannot compile must not take the ingest down with it.
      BOTH, split by what each metacharacter can mean. `\` is escaped in `globre`, because
      SQLite GLOB treats it as an ordinary character (measured) and escaping makes the two
      floor paths agree. `[` and `]` are REFUSED, by name, where `TIER_RULES` is built — not
      escaped, because they cannot be made to agree: SQLite GLOB honours `[ab]` as a
      character class (measured), so escaping them in the regex would leave one floor
      quietly meaning something different from the other. Refusing at the single point both
      paths read from means the SQL path cannot receive the rule either.
- [x] The task pass fails CLOSED. A non-zero awk exit in that pipeline must reach `kit_warn`
      and a non-zero script exit, the way `run_adapter` already does at `kit-index.sh:84-101`.
      Today the pipeline's exit status is discarded and the build reports success.
      Done, and NOT by checking the exit status alone, which is not sufficient: awk exits **0**
      after skipping an argument it could not read, having emitted a short backlog (measured —
      a directory named `*.md` reproduces it). So the pass now reports how many files it READ,
      as a SQL comment, and the shell compares that against the same glob it expanded. The
      status check is kept as well; it costs nothing and catches a death before any output.
      Both fire before the existing index is touched, so a bad run leaves yesterday's correct
      index in place rather than today's truncated one.
- [x] A conformance step covers both: a profile with an uncompilable glob, asserting the
      index still contains every task and that the run says something. Assert on stderr, not
      only on the DB — the whole defect is that the DB looks fine.
      Three halves, asserting on stderr and on the DB: the bad rule is named and the build
      still completes with the surviving rule's floor applied; a lost task file fails the run,
      says `read 4 of 5`, and leaves the good index intact; and it recovers once the cause is
      removed, because a guard that stays latched is one people work around. Mutation-verified
      — removing the validation alone turns it red, removing the read-count guard alone turns
      it red.
- [x] Check whether the same shape exists for the OTHER glob source: the shell-side floor loop
      at `kit-index.sh:661-677` feeds the same globs to SQLite's `GLOB`, which has different
      metacharacters and different failure behaviour. Report the answer either way.
      **It exists, and it is the quiet version.** Measured against SQLite directly:

          'f:src/ab' GLOB 'f:src/[ab'   ->  no match, NO error
          'f:src/a'  GLOB 'f:src/[ab]'  ->  match: the class is honoured
          'f:src\a'  GLOB 'f:src\a'     ->  match: backslash is literal

      So an unbalanced `[` never errors on the SQL side — it simply never matches, and the
      floor silently does not apply. Same defect, no fatal, no message: worse to find and
      less damaging to suffer. It is closed by the same fix, because the refusal happens
      before either consumer sees the rule. The bracket and backslash results are also what
      decided the escape-versus-refuse split above.

## Outcome

Three changes in `tooling/kit-index.sh`:

1. `TIER_RULES` refuses any rule whose glob contains `[` or `]`, naming it on stderr.
2. `globre` escapes `\` along with the metacharacters it already escaped.
3. The task pass emits how many files it read, and the shell fails the build when that does
   not match how many it handed over — before the existing index is replaced.

The original reproduction, before and after:

    before:  exit=0   tasks indexed: 1 of 4   survivor untiered and unfloored
    after:   exit=0   tasks indexed: 4 of 4   floors applied from the surviving rule
                      kit: tier.rule ignored — [ and ] are not supported in a glob: src/[ab T3

The second control, which the first would not have caught:

    a task file the reader cannot read:
             exit=1   kit: task ingest read 4 of 5 task file(s); the existing index
                      was left unchanged.
             index preserved: 4 tasks, intact

## Notes

Found by `security-reviewer` (opus) during the T3 review of
T-20260808-kit-cfg-strips-space-and-tab-from-a-valu, and reproduced independently before
filing. It is pre-existing and was not introduced by that commit — but it sits inside the
function that commit edited, in the dimension that commit claimed to be strengthening, which
is how it came to light.

Recorded as `fail-open|critical` in the findings table.

The blind second reviewer found this and the first reviewer did not. That is the second
recorded instance of the T3 second reader behaving as a COMPLETENESS control rather than a
correctness one — the same result `docs/MEASUREMENTS.md` §C reports from the design-stage
comparison.
