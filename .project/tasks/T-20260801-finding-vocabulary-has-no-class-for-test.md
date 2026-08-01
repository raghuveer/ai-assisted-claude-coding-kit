---
id: T-20260801-finding-vocabulary-has-no-class-for-test
title: Finding vocabulary is unreachable below the opus tier and lacks a test-coverage class
epic: feedback-loop
tier: T2
state: open
---

## Intent

Two defects in the same contract. The second was found later and is the larger one.

### 1. No class for test coverage or verification defects

`kit-finding.sh --vocab` accepts:

    class:    fail-open race false-rationale perf compliance correctness style unclassified
    severity: critical major minor nit

On a real T2 review, `implementation-reviewer` raised a missing regression test for CLI
glue and an unverified claim about whether commands had been run. Neither has a home.
`unclassified` exists, but routing a whole defect category through it destroys the signal
the table is for -- the README's accelerator query groups by `lang, class`.

### 2. The vocabulary is not reachable below the opus tier

Measured by running the SAME agent on the SAME prompt against the same blind checkout,
varying only the model:

| tier | findings emitted | valid | notes |
|---|---|---|---|
| opus   | 18 | **18** | -- |
| opus (security-reviewer) | 17 | **17** | read `kit-finding.sh:23-24` from source to confirm |
| sonnet | 9  | **0**  | emitted `design-gap`, `unverified-claim`, `scope-creep`, `missing-alternative` |
| haiku  | 8  | **0**  | emitted `assumption`, `design`; appended prose after the 4th pipe field |

The opus agents cannot run `--vocab` either -- no shell -- but they locate and read the
script. The tiers below invent plausible class names instead.

Per `docs/MODELS.md`, `coder`, `implementation-reviewer`, `tester` and `adr-scribe` are
all pinned to sonnet. That is "the working tier -- most of the volume". So the agents
producing most of the review volume cannot produce an ingestible finding.

Consequence, and this is the part that matters: once
[[T-20260801-nothing-invokes-kit-finding-so-the-findi]] is fixed and something actually
pipes findings in, the table will fill with **opus-tier findings only** and will look like
it is working. The accelerators would then be derived from design review exclusively, with
implementation review silently absent, and nothing in the output would say so.

## Acceptance criteria

- [ ] a class exists for test-coverage gaps
- [ ] a decision is recorded on whether verification/process defects belong in this table
      at all, or somewhere else
- [ ] a sonnet-tier agent emits valid classes at the same rate as an opus-tier one, and
      that is measured rather than assumed
- [ ] rejected findings are visible at the point of rejection, not discovered later by
      querying an empty table
- [ ] the batch parser rejects or repairs a malformed line rather than dropping it, since
      haiku's trailing prose broke the format silently
- [ ] adding a class does not require editing it in four places -- the drift that
      `--vocab` was introduced to fix

## Notes

Tier raised T1 -> T2 when defect 2 was measured. This is no longer a vocabulary-ergonomics
item; it decides whether the accelerator corpus is representative or is a biased sample of
one model tier.

The obvious fix -- inline the vocabulary into each agent file -- is the exact duplication
that caused the original four-way drift recorded in `kit-finding.sh`'s own header. A
generator that writes the agent files from one source, or a validator that fails CI when an
agent file's stated vocabulary diverges from the script's, avoids reintroducing it.
