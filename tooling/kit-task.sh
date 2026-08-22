#!/usr/bin/env bash
# kit-task.sh --title "..." [--tier T2] [--lang go] [--epic name] [--blocked-by "T-x,T-y"]
#
# Creates one task file. Tasks are FILES; the index is derived from them. Nothing is
# ever written to the database directly — kit-index.sh would overwrite it on the next
# rebuild, and a second source of truth is the failure this whole design avoids.
#
# Intended use: a researcher proposes a breakdown, a human confirms and edits, then
# this writes the confirmed tasks. The confirmation is the gate — a model writing
# straight to disk means the model is setting your backlog.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 1; }
kit_active "$ROOT" || { kit_warn "kit not adopted here (no .claude/project-profile.md)"; exit 1; }
PROFILE=$(kit_profile "$ROOT")
TASKS_DIR=$(kit_cfg "$PROFILE" paths.tasks ".project/tasks")

title=""; tier=""; lang=""; epic=""; blocked=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title) title=${2:-}; shift; shift ;;
    --tier) tier=${2:-}; shift; shift ;;
    --lang) lang=${2:-}; shift; shift ;;
    --epic) epic=${2:-}; shift; shift ;;
    --blocked-by) blocked=${2:-}; shift; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$title" ] || { kit_warn "--title is required"; exit 2; }
[ -z "$tier" ] || case "$tier" in T0|T1|T2|T3) ;; *) kit_warn "tier must be T0..T3"; exit 2 ;; esac

# Date-plus-slug: no central counter, so two branches never collide on an id, and it
# stays legible in git log — which is where a human actually reads it.
slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
       | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)
id="T-$(date -u +%Y%m%d)-$slug"
f="$ROOT/$TASKS_DIR/$id.md"
[ -e "$f" ] && { kit_warn "already exists: ${f#$ROOT/}"; exit 1; }
mkdir -p "$ROOT/$TASKS_DIR"

{
  printf -- '---\nid: %s\ntitle: %s\n' "$id" "$title"
  [ -n "$epic" ]    && printf 'epic: %s\n' "$epic"
  [ -n "$tier" ]    && printf 'tier: %s\n' "$tier"
  [ -n "$lang" ]    && printf 'lang: %s\n' "$lang"
  [ -n "$blocked" ] && printf 'blocked_by: %s\n' "$blocked"
  # `created`, the canonical value. This emitted `open` -- a legacy alias -- which the indexer
  # resolves, so nothing was broken; but every new task then ADDED to the legacy-spelling count
  # kit-status.sh reports, so the drain tracked by
  # T-20260822-legacy-state-spellings-in-task-files-sho could never reach zero. A backlog that
  # refills itself is not a backlog. See docs/adr/0008.
  printf 'state: created\n---\n\n## Intent\n\n\n## Acceptance criteria\n\n- [ ] \n- [ ] \n\n## Notes\n\n'
} > "$f"
printf '%s\n' "${f#$ROOT/}"
