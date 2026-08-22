#!/usr/bin/env bash
# kit-lib.sh — shared helpers. Sourced, never executed directly.
# Dependencies: git, sqlite3, awk, sed. Nothing else, by design.

kit_root() { git rev-parse --show-toplevel 2>/dev/null; }

kit_profile() { printf '%s/.claude/project-profile.md' "$1"; }

# The kit is inert in any repo that has not opted in.
kit_active() { [ -f "$(kit_profile "$1")" ]; }

# kit_cfg <file> <key> [default]  -> first value for key in the frontmatter block
#
# One awk per call, and every caller uses $(kit_cfg ...), so memoising inside this function
# buys nothing -- the cache dies with the subshell. Callers that read MANY keys from MANY
# files must not loop over this; see the single-pass reader in kit-index.sh.
# A CRLF profile is not a corrupt profile. It is what a Windows checkout of a repository
# without `*.md text eol=lf` produces, and the value is `.project<CR>`, which names no
# directory. Stripped once per line rather than added to each trim below, so it covers the
# key, the value and the `---` test together -- and so the next field added here inherits it.
#
# It went unseen because the gawk shipped in git-bash strips CR on input; a POSIX awk does
# not. A value that parses only because one platform's awk is lenient is the fail-open
# direction: correct until it reaches a platform that is not.
kit_cfg() {
  local v
  v=$(awk -v k="$2" '
    { sub(/\r$/, "") }
    /^---[[:space:]]*$/ { fm++; next }
    fm==2 { exit }
    fm==1 {
      i = index($0, ":")
      if (i > 1) {
        key = substr($0, 1, i-1); val = substr($0, i+1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == k && !done) { print val; done = 1 }
      }
    }' "$1" 2>/dev/null)
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "${3:-}"
}

# kit_cfg_all <file> <key>  -> every value for a repeatable key, one per line
kit_cfg_all() {
  awk -v k="$2" '
    { sub(/\r$/, "") }                        # see kit_cfg
    /^---[[:space:]]*$/ { fm++; next }
    fm==2 { exit }
    fm==1 {
      i = index($0, ":")
      if (i > 1) {
        key = substr($0, 1, i-1); val = substr($0, i+1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == k) print val
      }
    }' "$1" 2>/dev/null
}

# kit_version -> the plugin version, read from the single place it is defined.
#
# No hardcoded fallback on purpose. A literal here would be a second source of truth that
# goes stale in silence, and this value is stamped into shared accelerator exports — a
# wrong version is worse than an absent one, because a wrong one is believed. Empty means
# "could not determine", which callers can say out loud.
kit_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null | head -1
}

kit_warn() { printf 'kit: %s\n' "$*" >&2; }

# kit_plan_digest <index.db> -> an opaque string for "the backlog this plan was computed from".
#
# ADR 0004 makes the plan survive a rebuild, which means it can now outlive its inputs — a
# possibility the old behaviour did not have, because the plan never outlived anything.
# `kit-plan.sh` stamps this into the plan file and `kit-index.sh` recomputes it on every
# rebuild, so THE TWO MUST AGREE ON WHAT IT COVERS. One home, called from both: two copies
# would report a plan permanently stale or permanently fresh, and both failures are silent.
#
# Deliberately NOT over `touches` edges, though clustering uses them. Those move on every
# commit, so including them would mark the plan stale the moment anyone commits anything —
# a warning that is always on is one people learn to skip, and this repository has already
# paid for that once (`git.trivial_pattern`, docs/MEASUREMENTS.md §B.6).
#
# `cksum` rather than a hash: POSIX, present on all three platforms the kit runs on, and this
# detects change rather than resisting forgery — the digest is recomputed from the index and
# only COPIED into the plan file, so no hash would resist an editor who writes the current
# value. `state` is a filter and not a field: a task moving open -> progress does not reorder
# the plan, and stamping it would say otherwise.
#
# WHAT IT DOES NOT COVER, said here rather than discovered later. This answers "is this the
# same BACKLOG the plan was computed from", NOT "is this still the ordering that backlog
# produces". The score is `w_unblocks*unblocks + w_escapes*escapes + w_tier*tier` and clustering
# unions on shared non-hub files, so a new `escaped` event, a new `touches` edge, or an edit to
# `priority.w_*` / `cluster.hub_cap` in the profile all reorder the plan while this value is
# unchanged. Two T3 reviewers raised the gap independently. `touches` is excluded deliberately —
# it moves on every commit, and a warning that is always on is one people learn to skip — but
# that argument does not extend to the profile weights, and callers must not read "fresh" as
# "the ordering is still current".
#
# Returns EMPTY when the query fails, and callers treat empty as stale. It used to swallow the
# failure and pipe an empty stream into `cksum`, which yields the same value an empty backlog
# does — so two uncomputable digests compared equal and cleared the staleness warning.
kit_plan_digest() {
  _kpd=$(sqlite3 "$1" "SELECT id||'|'||COALESCE(tier,'')||'|'||COALESCE(epic,'')||'|'||COALESCE(blocked_by,'')
                         FROM task WHERE state NOT IN ($(kit_state_sql "$(kit_state_closed)")) ORDER BY id;") || return 1
  printf '%s\n' "$_kpd" | tr -d '\r' | cksum | awk '{print $1 "-" $2}'
}

# kit_via_vocab -> how a unit of work was executed. THE definition; every consumer reads it
# from here, and tests/conformance.sh asserts that no second copy exists. The finding
# vocabulary was restated in four places once and the agents emitted values the recorder threw
# away; this one starts with a single home.
#
#   kit      this project's own pipeline ran on it -- tiered, spawned, reviewed
#   agent    a coding agent did it, without the kit
#   manual   a human did it
#   unknown  nobody can say, which on a brownfield back-fill is most of the backlog
#
# `unknown` is a real value that reports as unknown. It is not a synonym for `manual`, and it
# is the default precisely so that an unrecorded task is visibly absent from a comparison
# rather than quietly counted into one.
#
# THE HUMAN GATE IS THE POINT. A model may propose the value; a person confirms it. A
# self-reported `kit` from the agent that did the work is the one value nobody should take on
# trust, which is why nothing in the kit ever writes this for you.
kit_via_vocab() { printf 'kit agent manual unknown'; }

# ---- TASK STATE: one home for the vocabulary and for every partition of it ----------------
#
# Same rule as kit_via_vocab above and for the same reason, measured rather than argued. On
# 2026-08-22 the question "is this task closed?" was answered by the literal `'done','abandoned'`
# in NINETEEN places across four files, while "is this a legal state?" was answered once. A rule
# with nineteen copies is a rule that will disagree with itself; the finding vocabulary already
# did exactly that across four locations here. See docs/adr/0008.
#
#   grep -rc "'done','abandoned'" tooling/     # 19, in kit-status(7) kit-index(6) kit-plan(5) kit-lib(1)
#
# SQL CONSUMERS DO NOT READ THESE FUNCTIONS DIRECTLY. kit-index.sh derives a `state_class` table
# from them and the queries join against it, because the derivation SQL lives in a QUOTED heredoc
# (`cat <<'DERIVE'`) where no shell expansion happens. Text is truth, the table is derived and
# disposable -- the same split this repository applies to task files and index.db.
# A LIFECYCLE, not a bag of values. The previous six were `started progress blocked unblocked
# done abandoned`, of which THREE had never been used across 130 tasks -- `blocked`, `unblocked`
# and `abandoned` all measured zero -- while `open`, the most-used value in the repository at 115
# tasks, was not in the list at all. See docs/adr/0008.
#
#   created      filed, after research and task segregation; not yet planned
#   planned      implementation approach decided and written down
#   in-progress  development or testing under way
#   on-hold      deliberately not being worked, after creation
#   completed    implementation finished
#   cancelled    NO LONGER RELEVANT -- a judgement about the WORK
#   abandoned    WE STOPPED -- a judgement about the ATTEMPT
#
# `cancelled` and `abandoned` are both kept and that is the point of the change. Collapsing them
# either way loses the distinction: filing dropped attempts as `cancelled` asserts they were never
# worth doing, which is the original complaint mirrored.
#
# There is no `paused`: blockedness is carried structurally by `blocked_by:`, which kit-plan.sh
# reads for layering, and the measured fate of a state that duplicates it is `blocked` -- zero uses.
kit_state_vocab()    { printf 'created planned in-progress on-hold completed cancelled abandoned'; }

# Closed = the work is not coming back, whether it finished or was dropped. Read by kit-plan.sh
# for what may be ordered, by kit-status.sh for what counts as open, and by kit_plan_digest below.
kit_state_closed()   { printf 'completed cancelled abandoned'; }

# The states whose actor is the task's OWNER. Deliberately not "vocab minus closed": a task nobody
# has picked up yet has no owner to infer. Maps forward from the old `started progress blocked`.
kit_state_activity() { printf 'in-progress on-hold'; }

# IN THE ESCAPE-RATE DENOMINATOR -- the tasks that count toward judging the pipeline.
#
# EVERY STATE EXCEPT `cancelled`, and the exception is the whole reason this partition exists:
# work that was never work must not count toward what the pipeline did or failed to do. A census
# that files 200 inventory items of which 120 are cancelled turns 5 escapes over 80 real tasks --
# 6.25% -- into 5 over 200 -- 2.5%, and the pipeline looks better for having filed nothing.
#
# `abandoned` IS measured: it was real work this pipeline touched, and hiding it would flatter the
# record in the other direction. Open states are measured too -- work in flight is still work, and
# this is deliberately NOT `kit_state_closed` inverted.
#
# ORTHOGONAL TO is_closed, which is why one boolean cannot carry it: `cancelled` is closed and
# unmeasured, `abandoned` is closed and measured, `in-progress` is open and measured.
kit_state_measured() { printf 'created planned in-progress on-hold completed abandoned'; }

# LEGACY SPELLINGS ARE ACCEPTED FOREVER, as `written:canonical` pairs. Nothing is rewritten: 127
# commits already carry `Task-Status: started|progress|done` and are immutable, and 130 task files
# carry `open` or `done`. They stay valid input; the canonical value is what is stored and queried.
#
# Normalisation happens ONCE, where the index is built, so every consumer downstream sees exactly
# the seven values above and no query is more complex than before. Accepting both spellings at
# nineteen partition sites instead would be the drift this whole change removes, doubled.
kit_state_legacy()   { printf 'open:created started:in-progress progress:in-progress unblocked:in-progress blocked:on-hold done:completed'; }

# `a b c` -> `'a','b','c'` for interpolation into SQL built in shell. The values are this file's
# own literals, never caller input, so quoting is about correctness of the emitted SQL and not
# about injection.
kit_state_sql() { printf "%s" "$(for _s in $1; do printf "'%s'," "$_s"; done | sed "s/,\$//")"; }
