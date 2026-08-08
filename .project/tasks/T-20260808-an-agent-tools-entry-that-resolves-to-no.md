---
id: T-20260808-an-agent-tools-entry-that-resolves-to-no
title: An agent tools entry that resolves to nothing is dropped silently
epic: agent-contracts
tier: T1
lang: bash
paths: tests/conformance.sh
state: open
---

## Intent

An agent's `tools:` frontmatter is an allowlist of tool names. A name that does not resolve to
a real tool is **dropped without a warning** — the agent launches with fewer tools than it
declared and nothing says so. Claude Code errors only if the list resolves to nothing at all.

This is not hypothetical. Anthropic's own `feature-dev/agents/code-reviewer.md` declares ten
tools of which four (`LS`, `NotebookRead`, `KillShell`, `BashOutput`) do not resolve; it runs
with six. The same file's body says to review changes from `git diff` while `Bash` is absent
from its allowlist — the identical defect this repository recorded against its own reviewers
on 2026-07-31, filed upstream as claude-plugins-official#4235.

This kit's eight agents currently use only real names, so this is a regression guard rather
than a fix. It is worth having because the failure is silent and the file that declares the
tools is the one place nobody re-reads.

## Acceptance criteria

- [ ] A conformance step asserts every `tools:` entry across `agents/*.md` resolves to a real
      tool name. It sits beside the existing "no Bash-less agent is instructed to execute a
      script" check, which is the same species of assertion.
- [ ] The list of valid names has ONE definition and the check reads it from there. If that
      list must be maintained by hand it is a second source of truth, so say where it comes
      from and how it is kept current — an assertion that goes stale silently is the defect it
      is guarding against.
- [ ] It fails on a fixture agent declaring a nonexistent tool, proven by mutation rather than
      by the suite being green today.
- [ ] Record the second constraint found alongside it: declaring ANY `tools:` allowlist
      silently excludes every `mcp__*` tool from that agent, permanently. Moot while the kit
      ships zero MCP servers, but it means the choice to write an allowlist is also a choice
      about MCP, and that belongs in the agent-authoring documentation rather than being
      rediscovered.

## Notes

From an ecosystem survey on 2026-08-08 of twelve real code-reviewer and architect-review agent
definitions. The related finding is recorded on
T-20260801-reviewer-agents-cannot-run-the-tools-the: reviewers without Bash is not normal
practice — ten of the twelve effectively have it, though only four by deliberate choice, the
rest by omitting `tools:` entirely and inheriting the default.
