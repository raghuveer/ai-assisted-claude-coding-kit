---
# Copy to .claude/project-profile.md in the target repo. Its presence is what
# activates the kit — without it every script exits silently and writes nothing.
#
# Format: flat `key: value` pairs in this frontmatter block. Deliberately not
# nested YAML, so parsing needs nothing beyond awk. Repeatable keys are noted.

paths.tasks:  .project/tasks
paths.state:  .project
paths.status: STATUS.generated.md

# Where each kind of state is ingested from. Defaults are the built-in text sources; point
# one at an executable to read from somewhere else (GitHub issues, an API, a database).
# See docs/ADAPTERS.md for the contract. `none` disables a source entirely.
# ingest.tasks:   files      # files  | none | <path to executable>
# ingest.events:  ndjson     # ndjson | none | <path to executable>
# ingest.commits: git        # git    | none
# ingest.extra:   <path>     # repeatable; additive, never replaces a built-in

git.adopted_at:           
# warn = print what is missing and commit anyway. enforce = reject the commit.
# Those two words are the whole vocabulary; anything else is treated as enforce and
# says so, rather than quietly downgrading a repo you believed was protected.
git.trailer_enforcement:  warn
git.trivial_pattern:      ^(chore|docs|style)(\(.*\))?:

# --- how the verification ladder is satisfied here. No core skill names a tool. ---
commands.build:
commands.test:
commands.lint:
commands.typecheck:

# Rung 3 (wiring proof) and rung 5 (independent second reader). Leave a rung EMPTY
# if this stack has no tooling for it — verify-ladder then declares it unavailable
# and raises the tier, which is the intended behaviour, not a workaround.
ladder.rung3:
ladder.rung5:

# --- tier floors. Repeatable. `<path-glob> <tier>`. Floors only, never ceilings. ---
tier.default: T1
# tier.rule: src/auth/** T3
# tier.rule: migrations/** T3

# --- semantic clustering -------------------------------------------------------
# Tasks are grouped by what they are ABOUT: a shared `epic:`, a shared source file, or a
# declared dependency. A file touched by more than hub_cap open tasks is treated as a hub
# (central config, main(), a barrel export) and does not link tasks — without that, one
# shared file fuses the whole backlog into a single cluster. Raise it if your clusters
# come out too fragmented; lower it if everything lands in cluster 1.
cluster.hub_cap: 5

# --- co-change: files that historically change together, from raw history -------
# touches edges need a Task-Id, so a repo adopted brownfield has none and blast radius is
# unknown for everything. Co-change needs no trailers. Parameters are measured, not guessed
# (docs/DESIGN-NOTES.md): a minimum edge weight was tested and HURT, so there is no knob for
# one. max_degree is the self-check -- a graph whose average file co-changes with more than
# this is withheld rather than emitted, because answering "everything" is worse than unknown.
cochange.enabled:    true
cochange.commit_cap: 50
cochange.hub_pct:    20
cochange.max_degree: 50

# --- accelerators are imported per project, never installed globally ------------
# Three axes, because reuse has three shapes and they do not overlap:
#   technology  what is true of the LANGUAGE          (go, typescript)
#   industry    what is true of the VERTICAL          (bfsi, govtech, health)
#   pattern     what is true of the DESIGN, whatever  (cache-port, idempotent-consumer)
#               the language and whatever the vertical
# The pattern axis exists because reviewers kept putting exactly this in `domain`. A cache
# port degrades the same way in TypeScript and in Go, and that is the reuse with the best
# amortisation: the design cost is paid once, not once per project.
# accelerator.technology: .claude/accelerators/go.md
# accelerator.industry:   .claude/accelerators/bfsi.md
# accelerator.pattern:    .claude/accelerators/cache-port.md -> approach-reviewer,researcher

# Salt for the project handle written by `kit-accel.sh export`. Without it that handle is
# an unsalted digest of the origin URL, which anyone able to guess the URL can reverse.
# Set one random value once and then leave it: changing it makes this project look like a
# new one to cross-project aggregation, and the promotion ladder counts distinct projects.
kit.export_salt:
---

# Project profile

Prose below the frontmatter is for humans and for the overlay agents. Record what is
true of **this codebase** and nothing that is true of the stack in general — stack facts
belong in an accelerator, where other projects can reuse them.
