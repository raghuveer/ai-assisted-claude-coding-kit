#!/usr/bin/env bash
# kit-event.sh <task-id> <kind> [json-payload] — append one event. Never read-modify-write.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
printf '{"task":"%s","kind":"%s","at":"%s"%s}\n' \
  "$(esc "${1:-}")" "$(esc "${2:-note}")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${3:+,\"payload\":$3}" >> "$ROOT/$STATE_DIR/events.ndjson"
