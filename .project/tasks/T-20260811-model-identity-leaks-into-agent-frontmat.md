---
id: T-20260811-model-identity-leaks-into-agent-frontmat
title: Model identity leaks into agent frontmatter
epic: portability
tier: T1
lang: bash
paths: agents, docs/MODELS.md
state: open
---

## Intent

All eight agents carry a `model:` line naming a Claude tier — `opus`, `sonnet`, `haiku`
(verified 2026-08-11). That is model identity living inside the kit, and it contradicts the
stated boundary: **the kit supplies context; the harness and whatever endpoint it is configured
against supply access to intelligence.** The kit connects through whatever OpenAI- or
Anthropic-compatible endpoint its coding agent provides, and it should not care which.

Today the leak is harmless because there is exactly one harness. It stops being harmless the
moment the kit runs anywhere else, and by then it is spread across eight files plus docs.

## The change

**This task is the audit half only.** Find and document every place a model name, provider name
or version reaches the kit: `agents/*.md` frontmatter, `docs/MODELS.md`, skills, README claims,
and anything in `templates/`. Produce the inventory and a deterministic check that keeps it
from growing.

**Deliberately NOT in scope: the capability-alias indirection.** Replacing `model:` with an
alias plus a per-project mapping builds an abstraction against exactly one harness. That is
generalising at n=1, and the thing that would prove it — a second harness adapter — does not
exist and is a stated future direction, not current work. Do the audit now; revisit the
indirection when a second harness is real.

**Naming, when that day comes: do not call it `tier`.** `Tier: T0-T3` already means RISK in this
kit — a git trailer with floors, a `tier.rule` config, an index column and conformance checks.
A second meaning of the same word in the one codebase whose most expensive documented failure
is vocabulary drift across four files would be self-inflicted. Use `capability:` or `weight:`.

## Acceptance criteria

- [ ] An inventory naming every file and line where a model, provider or version appears, with
      a note on whether Claude Code requires it there or the kit chose to put it there.
- [ ] A check that fails when a NEW model name appears outside the places the inventory
      sanctions. It must be able to fail: prove it by adding one.
- [ ] `docs/MODELS.md` states the boundary explicitly — the kit names capability needs, never
      models — and says the frontmatter `model:` values are a harness requirement, if they are.
- [ ] No behaviour change. Agents still resolve and run exactly as they do today.

## Notes

Filed 2026-08-11 from R-01 of the recommendations register, split in half on review. The
register placed the whole of R-01 in Wave 0 ahead of everything else; that was challenged
because the indirection delays the brownfield trial, which is the actual gate, for portability
value that cannot be tested yet.

Out of scope permanently: how models are reached — gateway, Bedrock, self-hosted open weights,
virtual keys. That is the harness's concern and the operator's, never the kit's.
