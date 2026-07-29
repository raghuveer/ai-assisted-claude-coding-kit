#!/usr/bin/env bash
# kit-finding.sh --task ID --agent NAME --class CLASS --severity SEV [--lang L] [--model M]
#
# Records one review finding. This table is what the technology and industry
# accelerators are later derived from, so a silently mis-filled row is worse
# than a missing one: named flags, and vocabularies are validated.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0

CLASSES="fail-open race false-rationale perf compliance correctness style unclassified"
SEVERITIES="critical high medium low"

task=""; agent=""; class=""; sev=""; lang=""; model=""; domain=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task=${2:-}; shift; shift ;;
    --agent) agent=${2:-}; shift; shift ;;
    --class) class=${2:-}; shift; shift ;;
    --severity) sev=${2:-}; shift; shift ;;
    --lang) lang=${2:-}; shift; shift ;;
    --domain) domain=${2:-}; shift; shift ;;
    --model) model=${2:-}; shift; shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

for req in task agent class sev; do
  eval "v=\$$req"
  [ -n "$v" ] || { kit_warn "missing --${req/sev/severity}"; exit 2; }
done
case " $CLASSES " in *" $class "*) ;; *)
  kit_warn "unknown --class '$class' (one of: $CLASSES)"; exit 2 ;; esac
case " $SEVERITIES " in *" $sev "*) ;; *)
  kit_warn "unknown --severity '$sev' (one of: $SEVERITIES)"; exit 2 ;; esac

STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
printf '{"task":"%s","kind":"finding","at":"%s","agent":"%s","class":"%s","severity":"%s","lang":"%s","domain":"%s","model":"%s"}\n' \
  "$task" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$class" "$sev" "$lang" "$domain" "$model" \
  >> "$ROOT/$STATE_DIR/events.ndjson"
