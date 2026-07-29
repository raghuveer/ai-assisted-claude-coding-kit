# Project profile — &lt;PROJECT&gt;

The agents read this. Keep it short and true; a profile that describes aspirations rather than the
current state teaches every agent to assert things that are false.

## Tech stack

&lt;Languages, frameworks, test runner, package manager, database, container runtime. Name the exact
commands: how to run one service's tests, how to build, how to lint.&gt;

## Conventions (authoritative sources)

&lt;Where the rules actually live — the agent-instructions file, the decision-record directory, the coding
conventions. Point at files rather than restating them, or you have created a second source of truth.&gt;

## Risk tiering — how much pipeline a change gets

**This is the single highest-leverage section in the file.** Without it, routine work defaults up to the
full pipeline and the expensive model tier becomes the largest cost line.

| Tier | Triggers | Pipeline |
|---|---|---|
| **HIGH-STAKES** | &lt;crypto/key custody · authn/authz decision points · any fail-closed path · DB migrations · the request hot path · quota/limit enforcement&gt; | researcher → approach-reviewer → coder → implementation-reviewer **+ security-reviewer** → tester |
| **ROUTINE** | &lt;CRUD · UI · read-only analytics · docs · config with no security meaning&gt; | coder → implementation-reviewer → tester |
| **TRIVIAL** | &lt;typo, comment, one-line fix with an obvious blast radius&gt; | direct edit; no agents |

**Name the tier and cite the trigger before spawning anything.** When genuinely unsure, treat as
high-stakes — but "unsure" should be rare, and if it is not, the trigger list is too vague.

## Session hygiene — cap context, split at unit boundaries

&lt;Your measured numbers go here once you have them. Until then: a long window re-reads its growing
context every turn, and that cache-read tends to dominate spend. Clear between units; compact mid-unit.
A group boundary is a clear boundary.&gt;

## Domain-specific review checks (for the reviewers)

&lt;The things a generic reviewer would not know to look for in THIS system. Start empty. Add an entry
only when a review or an incident proves one is needed — an invented checklist is noise that dilutes the
real ones.&gt;

## Status tracking

&lt;How item status is recorded. If you adopt the commit-trailer convention, say so here and name the
sync script; if you maintain it by hand, say that too — but expect drift, and expect it to be invisible
until someone audits.&gt;
