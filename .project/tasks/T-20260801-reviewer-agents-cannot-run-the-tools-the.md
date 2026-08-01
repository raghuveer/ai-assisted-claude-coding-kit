---
id: T-20260801-reviewer-agents-cannot-run-the-tools-the
title: Reviewer agents cannot run the tools their instructions require
epic: agent-contracts
tier: T2
lang: markdown
state: open
---

## Intent

`implementation-reviewer`, `approach-reviewer` and `security-reviewer` are all
`tools: Read, Grep, Glob`. All three carry this line:

> Run `kit-finding.sh --vocab` for the accepted class and severity values rather than
> guessing: an unrecognised value is rejected, not stored, and the finding is simply lost.

None of them can run it. The instruction is unexecutable as written, in all three.

DIAGNOSIS NARROWED after the model-tier test -- see the numbers in
[[T-20260801-finding-vocabulary-has-no-class-for-test]]. The failure is not random
guessing. Vocabulary compliance tracks MODEL TIER, and the opus-tier agents work around
the missing shell while the tiers below cannot:

- `security-reviewer` (opus, no shell) READ `tooling/kit-finding.sh:23-24` directly and
  confirmed the vocabulary from source. 17/17 valid. It then disclosed that it could not
  run `--vocab` and had verified the list another way.
- `approach-reviewer` (opus) 18/18 valid.
- `approach-reviewer` forced onto sonnet: 0/9 valid.
- `approach-reviewer` forced onto haiku: 0/8 valid, and it appended prose after the
  fourth pipe field, breaking the batch format outright.

`implementation-reviewer` is pinned to sonnet per `docs/MODELS.md`. Its 3-of-4 rejection
rate is not an outlier -- it is the sonnet tier behaving as the sonnet tier does.

So the fix is not "tell the agent where the vocabulary lives". An opus agent already finds
it. The fix has to make the contract satisfiable WITHOUT inference, because the tiers that
carry most of the review volume do not infer it.

The second, separate cost of the same tool gap stands unchanged.
`implementation-reviewer` was asked to confirm four ladder commands exit 0. It cannot
execute, so it ranked "independently confirm the commands run" as its TOP required change
-- unresolvable by construction, and it will recur on every run where verification
matters. 104,769 tokens, comparable to the coder it was reviewing, to reach "strong
circumstantial evidence, but this is not independent confirmation."

It also has no `git`, so on an uncommitted change it cannot diff. It reviewed the whole
tree instead of the change, and read the operator's `.claude/settings.local.json` to
reverse-engineer which commands the coder had run.

## Acceptance criteria

- [ ] every instruction in an agent file is executable with that agent's declared tools,
      or the tool is granted
- [ ] the vocabulary reaches sonnet- and haiku-tier agents without requiring them to
      locate and read the script -- inlining, or validation at emission, or both
- [ ] a reviewer asked to verify behaviour can execute, or is never asked to
- [ ] `implementation-reviewer` can diff the change under review rather than reading the
      whole tree
- [ ] a check that fails when an agent file references a script the agent cannot run --
      this drifted back after being fixed once, so it needs a test, not just a fix

## Notes

`approach-reviewer` at 19 tool uses versus `implementation-reviewer` at 45 is the tell:
design review is a reading task and the current toolset fits it; implementation review is
an execution task and it does not. The two rungs have identical tool grants and should not.

Tool-use count also predicts review depth across tiers. On the same prompt: opus 19 tool
uses, sonnet 20, haiku 5. Haiku reviewed the prompt rather than the repository and missed
the one critical security finding the other two confirmed independently.

Cheapest fix for the verification half is granting Bash to `implementation-reviewer`.
The vocabulary half cannot be fixed by tool grants alone, because inlining the list is
what caused the original four-way drift -- see the sibling task.
