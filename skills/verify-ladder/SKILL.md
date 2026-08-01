---
name: verify-ladder
description: Determine which verification obligations apply at the declared tier, how each is satisfied in this project's stack, and what to do when a rung has no tooling. Use before claiming any work is complete.
---

# verify-ladder

The ladder states **obligations**, not commands. An obligation is portable across
stacks; a command is not. This is the seam that lets a technology accelerator be added
later without editing this skill.

## Obligations

| Rung | Obligation | From (T) |
|---|---|---|
| 1 | The change compiles and satisfies static analysis | T0 |
| 2 | Stated acceptance criteria are proven by tests that fail without the change | T1 |
| 3 | The **wiring** fails as designed, not just the parsers — integration points, error paths, timeouts | T2 |
| 4 | An adversarial reader has looked for what the tests cannot express: fail-open guards, races behind a green suite, comments whose rationale is false | T2 |
| 5 | A second reader, given no sight of the first's findings, has done the same | T3 |

Rung 5 is a **completeness control, not a correctness control**, and the difference decides
whether it is worth its cost. Measured on one T3 design: two reviewers, the second blind at
a commit predating the first's findings, both returned REJECT and shared roughly 70% of
findings. Same verdict either way — so as insurance against a wrong call it bought nothing.

The 30% that differed is what it bought. Only the security reader found an unpinned hash
whose ambiguous pre-image lets a same-tenant attacker poison a victim's cached answer. Only
the design reader found that the proposed port set had no invalidation method at all.
Neither list contained the other's.

So do not run rung 5 expecting a second opinion on the verdict. Run it expecting a
different half of the problem, and treat convergence on the verdict as normal rather than
as evidence the rung is redundant.

## Satisfaction

Read `.claude/project-profile.md` for `commands.*` and `ladder.*` keys. Never invoke a
tool this skill names itself — it names none deliberately.

If a rung has **no satisfaction declared** for this stack, do not skip it silently.
Declare it unavailable, name the compensating control, and **raise the tier by one**.
Less mechanical verification means more adversarial reading, not a lower bar. A T3
change in a stack with no mutation tooling gets more human and reviewer attention, not
less.

## Recording findings

Every finding gets recorded, including from reviewers you disagree with. Take the
reviewer's `Findings (recordable)` block and pipe it in unchanged:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-finding.sh \
  --task <task-id> --agent <agent> --batch <<'EOF'
fail-open | critical | go
race      | major    | go
EOF
```

One finding at a time takes named flags: `--task --agent --class --severity [--lang] [--domain]`.
Both forms reject an unknown value rather than storing it, and a batch with any rejected row
exits non-zero — a partly recorded review is a measurement gap, and you are the only one
still holding the findings needed to fix it.

Do not memorise the vocabularies; print them:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-finding.sh --vocab
```

`class` and `lang` are the entire mechanism by which technology and industry accelerators
are later improved from real work rather than invented. A finding recorded without them is
a finding that teaches nothing.

## Completion

Work is complete when every obligation at the declared tier is either satisfied or
explicitly declared unavailable with its tier raised. "I inspected it" satisfies no rung.
