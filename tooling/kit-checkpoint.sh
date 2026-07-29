#!/usr/bin/env bash
# kit-checkpoint.sh — Stop hook. Deterministic session checkpoint.
# This is a hook and not a skill on purpose: a checkpoint that depends on someone
# remembering to invoke it is skipped exactly when sessions run long, which is when
# it matters. Costs no context; emits no prose.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
DIRTY=$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')
HEAD=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)
printf '{"task":"","kind":"checkpoint","at":"%s","head":"%s","dirty_files":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HEAD" "${DIRTY:-0}" >> "$ROOT/$STATE_DIR/events.ndjson"
exit 0
