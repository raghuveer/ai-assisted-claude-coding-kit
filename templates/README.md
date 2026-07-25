# templates/ — starting points you fill in

These are the files that cannot be portable, because they describe *your* project. They are written
generically and are safe to copy, but each one has a gap only you can close.

| File | Copy to | What you must supply |
|---|---|---|
| `project-profile.TEMPLATE.md` | your docs directory, as `project-profile.md` | **everything** — stack, test commands, and above all the **risk-tiering table** |
| `commands/checkpoint.md` | `.claude/commands/` | the status-pointer path, your test commands, which repositories to sweep, whether status is derived |
| `commands/resume-context.md` | `.claude/commands/` | the status-pointer path, the repositories to check |
| `commands/drift-check.md` | `.claude/commands/` | the status-pointer path, your truth-doc names |
| `settings.json` | `.claude/` | **merge, do not clobber** an existing one; add project-specific hooks and permission globs |

## Start with the profile

`project-profile.TEMPLATE.md` is the highest-leverage file here. Its risk-tiering table decides how much
pipeline each change gets — and without it, everything defaults to the full pipeline and the expensive
model tier quietly becomes your largest cost line. Name your tiers and their triggers concretely enough
that "which tier is this?" is answerable in seconds, not debated.

## The commands encode discipline, not just steps

Read them before adapting. Several lines exist because something went wrong once and the cheapest fix was
a sentence in a ritual:

- **verify what you actually changed**, with the tool that fits it — and say plainly when no product code
  changed rather than implying a suite was re-run;
- **mutation-test the wiring**, because a test that would still pass with the fix reverted proves nothing;
- **append to an archive verbatim before compressing** what stays, so no analysis is lost to a line budget;
- **scan operator-authored prose for credentials before staging it**, and report hits rather than
  committing quietly;
- **check every repository**, because the one you forget is the one that silently diverges;
- **stage deletions separately from edits** — `git rm` then `git add` on the same path aborts the whole
  `add` and commits half your change.

Adapt the paths freely. Think twice before deleting a rule: most of them are one line and each is
someone's bad afternoon.

## settings.json

The hooks are deliberately minimal and generic: a start-of-session reminder to rebuild from files, an
end-of-session nudge if anything is uncommitted, and a long-session hygiene warning. Add your own —
a status-derivation check is a good one if you adopt that pattern — and keep machine-specific overrides
in `settings.local.json` rather than here.
