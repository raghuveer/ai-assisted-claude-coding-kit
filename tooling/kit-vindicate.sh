#!/usr/bin/env bash
# kit-vindicate.sh --task ID --class CLASS (--real | --false) [--note TEXT]
#
# Marks whether a finding was actually a defect. Without this the promotion ladder
# runs on raw occurrence counts, which include reviewer false positives — and an
# accelerator built from unvindicated findings launders noise into shared config
# that every future project then loads.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0

task=""; class=""; verdict=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task=${2:-}; shift; shift ;;
    --class) class=${2:-}; shift; shift ;;
    --real)  verdict=1; shift ;;
    --false) verdict=0; shift ;;
    --note)  shift; shift ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$task" ] && [ -n "$class" ] && [ -n "$verdict" ] || {
  kit_warn "usage: --task ID --class CLASS (--real|--false)"; exit 2; }

STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
printf '{"task":"%s","kind":"vindication","at":"%s","class":"%s","vindicated":%s}\n' \
  "$task" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$class" "$verdict" \
  >> "$ROOT/$STATE_DIR/events.ndjson"
