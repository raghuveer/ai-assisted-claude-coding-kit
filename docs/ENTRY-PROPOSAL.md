# The entry proposal — format, and who writes it

A reference file, not an agent and not a skill. `docs/DESIGN-NOTES.md` §0: an agent is a permanent
context charge on every session; a reference file costs nothing until something reads it. Turning
a codebase into a candidate task list is a once-per-adoption act, so it gets a document.

ADR 0001 decided the split. `kit-entry.sh` produces facts. A model produces judgement. The
orchestrator writes files. Nothing files work.

## The procedure

1. **`kit-entry.sh`** — writes `entry-facts.tsv`, `entry-comment-runs.tsv` and `entry-report.md`
   under `paths.state`. All three are derived and gitignored.
2. **`researcher`** — given the report, the TSVs and a bounded, named file list, it **returns**
   the proposal text as its reply. It has `Read, Grep, Glob, WebFetch, WebSearch` and **no
   `Write`**; do not grant it one. Ask it for the format below rather than its usual design-input
   template, which is a different artefact with a different shape and a ~2000-word cap.
3. **The orchestrator** writes two files, because it is the actor that holds `Write`:
   - `<paths.state>/entry-candidates.md` — **committed**, and overwritten by the next run.
     This said *"disposable, gitignored"* and was wrong on both halves. It is not derived:
     `kit-entry.sh` writes the census TSVs and the report, **not this file** — the model does,
     which is why a re-run cannot reproduce the same judgement the way it reproduces a count.
     Ignoring it cost a real conclusion: a brownfield readiness review reported that the
     inventory half *"does not exist in any form"* while a complete proposal sat on disk,
     unreadable at HEAD.
   - `<paths.design_input>/YYYY-MM-DD-entry-questions.md` — **committed**. Questions are a durable
     record of what was asked. Both are now durable; what still differs is their lifetime —
     questions accumulate, candidates are superseded wholesale by the next run.
4. **`kit-entry.sh --check <file>`** — validates the shape and refuses a candidate line that is
   unsafe to paste. Run it on what the model returned, before a human reads it.
5. **The operator** answers the questions, then runs the `kit-task.sh` lines they accept.
   `adr-scribe` turns an answered question into a decision record under `paths.adr`.

## The format

```markdown
## Open questions

1. Why is the retry count 7?
   evidence: src/retry.go:3, docs/note.md:5
   answer:

## Candidate tasks

- [ ] Document the retry budget
      evidence: src/retry.go:3
      kit-task.sh --title 'Document the retry budget' --tier T1

## Could not determine

- co-change: empty — indistinguishable from withheld / disabled / no history / no index
```

**Questions come first, and carry no checkbox.** A checkbox is a thing to be ticked and then done;
a question is a thing to be answered. The task this mechanism serves says an undocumented design
choice is a QUESTION, not a defect — putting a checkbox on one invites it to be closed rather than
answered, which is the failure the rule exists to prevent.

**Every question and every candidate cites evidence**, as `path` or `path:line`. A candidate with
no evidence is an opinion, and the point of the census is that opinions are separable from facts.

**Every candidate carries the literal `kit-task.sh` line** the operator would run. There is no code
path from this file to a task file: the operator copies the line, or does not. That is the whole of
the structural prevention and it is exactly as strong as that sentence.

## Dispositions — a candidate is not always new work

On a brownfield census most of what is found **already exists**, and some of it **should not be
done at all**. A format that can only propose new work forces both into the one shape it has, and
the inventory that results is wrong in a way nobody can see.

**The disposition IS the task state.** There is no second vocabulary — `docs/adr/0008` defines one,
and inventing another set of words meaning the same things is the drift that ADR removed from
twenty-five places.

| what the census found | how the candidate says it |
|---|---|
| work that should be done | *(nothing — a task is `created` by default)* |
| it already exists and is finished | `--state completed --via <how>` |
| it exists but should not be done at all | `--state cancelled` |

```markdown
## Candidate tasks

- [ ] Document the retry budget
      evidence: src/retry.go:3
      kit-task.sh --title 'Document the retry budget' --tier T1

- [ ] The retry budget is already documented, in a file the census found
      evidence: docs/retry.md:1
      kit-task.sh --title 'Retry budget is documented' --state completed --via manual --paths 'docs/retry.md'

- [ ] The legacy poller is dead code behind a flag that is never set
      evidence: src/poll.go:12, config/flags.yml:8
      kit-task.sh --title 'Legacy poller is unreachable' --state cancelled
```

**A `completed` candidate is proposing an inventory record, not work.** That is the point: it is
how the backlog comes to describe what exists rather than only what is missing, which is what
`docs/design-input/2026-08-16-artifact-model-and-distribution.md` §1.2 means by a per-component
disposition.

**`--via` is a PROPOSAL, always.** `.claude/CLAUDE.md` is explicit that a model may propose how
work was done and a human confirms it. That holds here for the same structural reason everything
else does — the operator runs the line, or does not. Nothing in this file writes anything.

**`--paths` populates the declared-paths tier floor**, which was previously unpopulatable because
`kit-task.sh` had no way to set it. Globs are allowed, because `tier.rule` matches globs.

Legacy state spellings — `open`, `done`, `progress` — remain valid input and resolve to canonical
values when the index is built, so a census reading a repository that predates ADR 0008 can quote
what it finds.

## What `--check` does and does not enforce

It enforces: questions section present and before candidates; no checkbox on a question; every
candidate has a `kit-task.sh` line; a `Could not determine` section that is not merely a heading;
and **every candidate line is safe to paste**.

That last one is a **whitelist, not a blacklist**: the whole line must match

    kit-task.sh --title '<A-Za-z0-9 space . _ ->' [--tier T0-3] [--lang ...] [--epic ...]
                [--paths '<A-Za-z0-9 space . _ / , * ->'] [--state <a task state>]
                [--via <a provenance>] [--blocked-by <ids>]

**`--state` and `--via` accept exactly what their vocabularies define, and the grammar is BUILT
from those definitions rather than written out here or in `kit-entry.sh`.** A copy in the gate
would go stale the day a state is added — silently, and in the fail-open direction, because an
unlisted value is simply refused and a proposal that should pass would not. Legacy state
spellings are included the same way, from the same definition.

and anything else is refused unread. Two earlier attempts inspected an *extracted* title against a
list of forbidden characters, and both failed open — one because a BSD sed class silently matched
nothing, one because the extraction stopped at the first quote and so could never see a quote. A
line that cannot be parsed is refused rather than parsed. Adding a flag to `kit-task.sh` means
widening this grammar, deliberately.

This closes one of the two conventions ADR 0001 recorded, and that ADR carries a superseded note
saying so. Its premise — "the tool never sees the titles" — was true of the design, where nothing
read the proposal back; it stopped being true when this check was added.

**It does not enforce the hold.** Nothing stops an operator, or an agent with `Bash`, running
`kit-task.sh` before answering a single question. That remains convention, as ADR 0001 says, and
`--check` does not change it. A check that validated shape and then let the list be filed anyway
would look like a gate while gating nothing.

**It does not check that cited paths exist.** `T-20260814-nothing-checks-that-a-finding-s-file-and`
is the same gap for findings and should be solved once, for both.
