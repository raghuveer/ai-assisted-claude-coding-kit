#!/usr/bin/env bash
# kit-event.sh <task-id> <kind> [json-payload] — append one event. Never read-modify-write.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
KIND=${2:-note}

# THE GENERIC WRITER MAY NOT ADDRESS A KIND THE INDEXER ACTS ON.
#
# The boundary is not a list of bad words, it is a property: kit-index.sh either MUTATES a row
# for a kind, or merely records the event. The kinds it mutates for are the four below, and each
# has its own writer that validates -- findings and fix-marks through kit_findings.py, spend
# through kit-spend.sh, vindication through kit-vindicate.sh. This script validates nothing: it
# takes the kind as a free argument and splices its third argument in as raw JSON, so before this
# refusal it could mint any of them.
#
# `kit-event.sh T-x finding-fixed '{"finding":"<id>","fixed":1}'` set fixed_at on a real finding
# after a reindex, with kit_findings.py never invoked -- forging the one artefact
# .claude/CLAUDE.md reserves to the operator, on the grounds that clearing the gate that gates
# your own work is the certification the author cannot give. The same route minted findings whose
# class and severity were outside kit-finding.sh --vocab.
#
# kit-index.sh's dispatch is the AUTHORITY for this list, not this file. tests/conformance.sh
# derives the kinds from its `k=="..."` branches and fails if the two disagree, so teaching the
# indexer to act on a fifth kind without adding it here goes red rather than reopening the hole.
case "$KIND" in
  finding|finding-fixed|finding-unassessable|spend|vindication)
    kit_warn "kit-event.sh will not write '$KIND': the indexer acts on it, so it belongs to"
    kit_warn "  the writer that validates it, not to the generic recorder."
    exit 2 ;;
esac

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
printf '{"task":"%s","kind":"%s","at":"%s"%s}\n' \
  "$(esc "${1:-}")" "$(esc "$KIND")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "${3:+,\"payload\":$3}" >> "$ROOT/$STATE_DIR/events.ndjson"
