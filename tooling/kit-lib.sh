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
