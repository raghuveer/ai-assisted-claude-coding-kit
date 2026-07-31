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
kit_cfg() {
  local v
  v=$(awk -v k="$2" '
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
