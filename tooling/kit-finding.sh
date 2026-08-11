#!/usr/bin/env bash
# kit-finding.sh --task ID --agent NAME --class CLASS --severity SEV [--lang L] [--domain D]
#                [--pattern P] [--model M]
# kit-finding.sh --task ID --agent NAME --batch    < lines of  class|severity|lang|pattern[|domain]
# kit-finding.sh --vocab                           prints the accepted vocabularies
#
# Records review findings. This table is what the technology and industry accelerators are
# later derived from, so a silently mis-filled row is worse than a missing one: named
# flags, and vocabularies are validated.
#
# --batch exists because a review produces many findings at once, and re-typing a flag line
# per finding is where class and lang get dropped. Those two are the only fields that make
# a finding teach anything, and they are the first casualties of tedium.
#
# --vocab exists because these lists were restated in the schema comment, in two skills and
# in the agent output contracts, and all four had drifted -- the agents emitted severities
# this script rejected outright, so most findings never recorded. Print the vocabulary
# rather than remembering it.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

# The one definition. Severity matches what the reviewer agents actually emit: a vocabulary
# its own producers do not use is a vocabulary that silently discards their output.
CLASSES="fail-open race false-rationale perf compliance correctness style unclassified"
SEVERITIES="critical major minor nit"

case "${1:-}" in
  --vocab) printf 'class:    %s\nseverity: %s\n' "$CLASSES" "$SEVERITIES"; exit 0 ;;
esac

ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0

task=""; agent=""; class=""; sev=""; lang=""; model=""; domain=""; pattern=""; batch=0; json=0
agent_id=""; unattributed=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task=${2:-}; shift; shift ;;
    # An explicit flag, not an empty --task. A caller that does not know the task must SAY so,
    # because the alternative -- accepting a blank id -- turns every mistyped invocation into a
    # silently unattributed finding, which is the shape this whole file exists to refuse.
    --unattributed) unattributed=1; shift ;;
    --agent-id) agent_id=${2:-}; shift; shift ;;
    --agent) agent=${2:-}; shift; shift ;;
    --class) class=${2:-}; shift; shift ;;
    --severity) sev=${2:-}; shift; shift ;;
    --lang) lang=${2:-}; shift; shift ;;
    --domain) domain=${2:-}; shift; shift ;;
    --pattern) pattern=${2:-}; shift; shift ;;
    --model) model=${2:-}; shift; shift ;;
    --batch) batch=1; shift ;;
    --json) json=1; shift ;;
    --vocab) printf 'class:    %s\nseverity: %s\n' "$CLASSES" "$SEVERITIES"; exit 0 ;;
    # The shape of a finding, printed rather than remembered -- the same reason --vocab
    # exists. Agents reference this; they must never restate it.
    --contract) exec python3 "$(dirname "$0")/kit_findings.py" --contract ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

[ -n "$agent" ] || { kit_warn "missing --agent"; exit 2; }
if [ -z "$task" ] && [ "$unattributed" = 0 ]; then
  kit_warn "missing --task (or --unattributed if the caller genuinely cannot know it)"
  exit 2
fi
if [ -n "$task" ] && [ "$unattributed" = 1 ]; then
  kit_warn "--task and --unattributed are contradictory; refusing rather than picking one"
  exit 2
fi

PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
EV="$ROOT/$STATE_DIR/events.ndjson"

# Name the bad value AND the accepted set. A rejection that does not say what was expected
# just gets retried with another guess.
validate() {  # validate <class> <severity>
  case " $CLASSES " in *" $1 "*) ;; *)
    kit_warn "unknown class '$1' (one of: $CLASSES)"; return 1 ;; esac
  case " $SEVERITIES " in *" $2 "*) ;; *)
    kit_warn "unknown severity '$2' (one of: $SEVERITIES)"; return 1 ;; esac
  return 0
}

record() {  # record <class> <severity> <lang> <pattern> <domain> [file] [line] [summary]
  # agent_id is carried so the harvesting hook can tell whether THIS agent has already been
  # recorded. Without it a second firing of SubagentStop re-harvests the same block, which is
  # the defect kit-spend.sh hit with four firings for two events.
  #
  # summary/file/line arrive only from --json, where kit_findings.py has already length-capped
  # them and stripped every quote and backslash from the summary. That normalisation is what
  # makes this printf safe: the awk reader in kit-index.sh matches "[^"]*" and cannot see past
  # an escaped quote, so an un-normalised summary would corrupt the row it is read back into.
  # `line` is emitted as a BARE integer, defaulting to 0, because the reader on the other side
  # (jn() in kit-index.sh) matches `"line": <digits>` and would never see a quoted one -- every
  # location would have silently stored NULL. 0 means "not supplied" and is mapped back to NULL
  # there; it is never a real line number.
  printf '{"task":"%s","kind":"finding","at":"%s","agent":"%s","agent_id":"%s","class":"%s","severity":"%s","lang":"%s","pattern":"%s","domain":"%s","model":"%s","file":"%s","line":%s,"summary":"%s"}\n' \
    "$task" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$agent" "$agent_id" "$1" "$2" "$3" "$4" "$5" "$model" \
    "${6:-}" "${7:-0}" "${8:-}" >> "$EV"
}

# A domain names an INDUSTRY and seeds the industry accelerator, so an arbitrary string
# there invents a vertical no project ever declared. Unlike an unknown class, which is
# rejected loudly, a wrong domain was accepted SILENTLY and polluted the thing it feeds.
#
# Reviewers reliably put the SUBJECT of the finding here instead -- `caching`,
# `cache-adapter-design` -- which is why `pattern` now exists: it was the axis they were
# reaching for. Accept a domain only if this project declared it.
declared_domain() {
  [ -n "$1" ] || return 0
  _decl=$(kit_cfg_all "$PROFILE" accelerator.industry |
          sed 's/[[:space:]]*->.*//' | sed 's|.*/||' | sed 's/\.md[[:space:]]*$//' | tr -d ' ')
  [ -n "$_decl" ] || return 1
  printf '%s\n' "$_decl" | grep -qx "$1"
}

# The structured path: a reviewer returns DATA and this records it. No block is scraped out
# of prose and nothing retypes fields by hand -- both of those were parsing, and every defect
# in the old harvester came from parsing (docs/LESSONS.md S5).
#
# Validation lives in kit_findings.py and is ALL-OR-NOTHING on purpose: a half-stored review
# is a finding table that disagrees with the review it came from, and afterwards nobody can
# tell which half is missing. So the validator runs to completion before a single line is
# appended, and its non-zero exit means this writes nothing at all.
if [ "$json" = 1 ]; then
  PY="$(dirname "$0")/kit_findings.py"
  TSV=$(python3 "$PY" --emit-fields) || {
    kit_warn "findings rejected by the contract; nothing recorded (see above)"
    kit_warn "run \`kit-finding.sh --contract\` for the field list"
    exit 2
  }
  n=0
  # A reviewer that found nothing sends `{"findings":[]}`. That is a measurement and must be
  # distinguishable from a reviewer that was never asked, so it is reported, not silent.
  if [ -z "$TSV" ]; then
    printf 'kit: reviewer %s returned zero findings (an empty review, recorded as such)\n' \
      "$agent" >&2
    exit 0
  fi
  # US (0x1f), not tab: tab is IFS whitespace and the shell collapses runs of it, so a row
  # with several empty fields would arrive short and every later value would shift into the
  # wrong column. Belt and braces on CR, which has reached a field on this platform before.
  while IFS="$(printf '\037')" read -r c s l pt d f ln sum; do
    c=$(printf '%s' "$c" | tr -d '\r'); sum=$(printf '%s' "$sum" | tr -d '\r')
    ln=$(printf '%s' "$ln" | tr -d '\r')
    [ -n "$c" ] || continue
    if [ -n "$d" ] && ! declared_domain "$d"; then
      kit_warn "domain '$d' is not declared in accelerator.industry — dropped"
      d=""
    fi
    # Re-checked here even though the validator already did it. This is the recorder's own
    # gate and it is the last one before the append-only log; a caller that learns to bypass
    # the validator must not thereby bypass the vocabulary.
    validate "$c" "$s" || { kit_warn "  ...on: $sum"; exit 2; }
    record "$c" "$s" "$l" "$pt" "$d" "$f" "$ln" "$sum"
    n=$((n + 1))
  done <<EOF
$TSV
EOF
  printf 'kit: recorded %d finding(s) from structured output\n' "$n" >&2
  exit 0
fi

if [ "$batch" = 1 ]; then
  n=0; bad=0; line=0
  while IFS= read -r L || [ -n "$L" ]; do
    line=$((line + 1))
    L=$(printf '%s' "$L" | tr -d '\r')
    case "$L" in ''|'#'*) continue ;; esac
    OIFS=$IFS; IFS='|'
    # shellcheck disable=SC2086
    set -- $L
    IFS=$OIFS
    c=$(printf '%s' "${1:-}" | tr -d ' '); s=$(printf '%s' "${2:-}" | tr -d ' ')
    l=$(printf '%s' "${3:-}" | tr -d ' '); pt=$(printf '%s' "${4:-}" | tr -d ' ')
    d=$(printf '%s' "${5:-}" | tr -d ' ')
    if [ -n "$d" ] && ! declared_domain "$d"; then
      kit_warn "line $line: domain '$d' is not declared in accelerator.industry — dropped"
      kit_warn "  (a domain is an industry; put the reusable design in the pattern field)"
      d=""
    fi
    if [ -z "$c" ] || [ -z "$s" ]; then
      kit_warn "line $line: expected class|severity|lang|domain, got: $L"; bad=$((bad + 1)); continue
    fi
    if validate "$c" "$s"; then
      record "$c" "$s" "$l" "$pt" "$d"; n=$((n + 1))
    else
      kit_warn "  ...on line $line: $L"; bad=$((bad + 1))
    fi
  done
  printf 'kit: recorded %d finding(s)' "$n" >&2
  [ "$bad" -gt 0 ] && printf ', rejected %d' "$bad" >&2
  printf '\n' >&2
  # Non-zero on any rejection. A partially recorded review is a measurement gap, and the
  # caller is the only one still holding the findings needed to fix it.
  [ "$bad" -gt 0 ] && exit 1
  exit 0
fi

[ -n "$class" ] || { kit_warn "missing --class"; exit 2; }
[ -n "$sev" ]   || { kit_warn "missing --severity"; exit 2; }
validate "$class" "$sev" || exit 2
if [ -n "$domain" ] && ! declared_domain "$domain"; then
  kit_warn "domain '$domain' is not declared in accelerator.industry — dropped"
  kit_warn "  (a domain is an industry; put the reusable design in --pattern)"
  domain=""
fi
record "$class" "$sev" "$lang" "$pattern" "$domain"
