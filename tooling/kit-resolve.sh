#!/usr/bin/env bash
# kit-resolve.sh --finding ID --fixed [--commit SHA] [--note TEXT]   mark a finding addressed
# kit-resolve.sh --finding ID --open  [--note TEXT]                  retract that mark
# kit-resolve.sh --list [--task ID] [--severity SEV] [--unfixed]     the ids, so the above is usable
#
# Answers "was this finding ADDRESSED". That is a DIFFERENT question from the one
# kit-vindicate.sh answers -- "was it real" -- and the two are orthogonal: a finding can be
# real and fixed, real and open, false and irrelevant. One column cannot carry two facts, and
# before this command the second fact was simply absent, so "is there an open critical on this
# task" could not be computed. Everything gating on it therefore either blocked forever or was
# waved through, and the trial protocol's very first checkbox was the latter.
#
# WHY AN EVENT AND NOT A COLUMN WRITE. `finding` rows are derived: kit-index.sh rebuilds them
# from events.ndjson every run. A mark written into the database would be erased by the next
# rebuild -- present, plausible and gone -- so it is recorded the same way the finding itself
# was, in the committed append-only log, and travels with the repository.
#
# WHY NOT KEYED LIKE kit-vindicate.sh. That command keys on (task, class) and updates every
# finding matching both. For "was it real" the coarseness is survivable. Here it is not: a task
# with two `fail-open` criticals, one fixed and one open, would read as clean the moment either
# was marked -- a gate reporting no open criticals while one is open is worse than no gate.
# So this keys on the finding's own id. See --list to get one.
#
# WHO MAY RUN THIS. Marking a finding addressed clears a gate. The session that wrote the code
# is the one party that must not also certify it -- and the first version of this shipped the
# instruction to do so into `skills/checkpoint/SKILL.md`, which is the file the AGENT reads.
# That is the wrong-addressee defect the provenance work found twice and split both CLAUDE
# files to prevent, repeated by the same hand that fixed it.
#
# **If you are an agent: propose the mark in your summary and stop.** Nothing here mechanically
# stops you -- there is no identity to check against and inventing one would be theatre. It is a
# convention the operator enforces, stated so it can be enforced, exactly as `Via:` is.
#
# ORDERING ACROSS MACHINES IS A KNOWN LIMIT. Two marks on one finding resolve last-write-wins
# over `at`, which is a LOCAL wall clock -- and .gitattributes marks events.ndjson merge=union,
# so two developers` clocks interleave in one file. Nothing here can establish a true order
# between them. A monotonic counter collides across branches; a vector clock is apparatus this
# kit has no other use for. Single-operator use is unaffected. A stated bound, not an oversight.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"
ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0

finding=""; verdict=""; commit=""; note=""; list=0; ftask=""; fsev=""; unfixed=0
while [ $# -gt 0 ]; do
  case "$1" in
    --finding)  finding=${2:-}; shift; shift ;;
    --fixed)    verdict=1; shift ;;
    --open)     verdict=0; shift ;;
    --commit)   commit=${2:-}; shift; shift ;;
    --note)     note=${2:-}; shift; shift ;;
    --list)     list=1; shift ;;
    --task)     ftask=${2:-}; shift; shift ;;
    --severity) fsev=${2:-}; shift; shift ;;
    --unfixed)  unfixed=1; shift ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
DB="$ROOT/$STATE_DIR/index.db"

# The database is only probed if it EXISTS. `sqlite3 <path> <query>` CREATES an empty database
# at that path, so the probe that was meant to detect a missing index quietly manufactured one
# -- and left it behind, where the next kit-status.sh run would read it as an index with no
# tasks in it.
db_readable() { [ -f "$DB" ] && sqlite3 "$DB" "SELECT COUNT(*) FROM finding;" >/dev/null 2>&1; }

if [ "$list" = 1 ]; then
  db_readable || {
    kit_warn "index at ${DB#$ROOT/} is missing or unreadable; run kit-index.sh"; exit 1; }
  # Single-quotes in a caller-supplied filter would end the literal and change the query, so
  # they are doubled -- the same treatment kit-index.sh gives every value it interpolates.
  esc() { printf '%s' "$1" | sed "s/'/''/g"; }
  W="1=1"
  [ -n "$ftask" ] && W="$W AND task_id='$(esc "$ftask")'"
  [ -n "$fsev" ]  && W="$W AND severity='$(esc "$fsev")'"
  [ "$unfixed" = 1 ] && W="$W AND fixed_at IS NULL"
  # THE QUERY'S EXIT STATUS IS READ, and an empty result is SAID rather than printed as
  # nothing. Unchecked, a filter naming a column this index does not have printed nothing and
  # exited 0 -- indistinguishable from "no findings match", which is the reading an operator
  # about to conclude "nothing left to fix" would take.
  out=$(sqlite3 -noheader -separator '  ' "$DB" \
    "SELECT id,
            CASE WHEN fixed_at IS NULL THEN 'OPEN ' ELSE 'fixed' END,
            severity, class, COALESCE(task_id,'-'), COALESCE(summary,''),
            CASE WHEN fixed_note IS NULL OR fixed_note='' THEN '' ELSE '  (fixed: '||fixed_note||')' END
       FROM finding WHERE $W ORDER BY at, id;" 2>&1) || {
    kit_warn "the listing query failed against ${DB#$ROOT/} -- NOT an empty result"
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    kit_warn "  if this index predates fixed_at, delete it and run kit-index.sh"
    exit 1; }
  if [ -z "$out" ]; then
    kit_warn "no finding matches that filter (this is an empty result, not a failed query)"
    exit 0
  fi
  printf '%s\n' "$out"
  exit 0
fi

[ -n "$finding" ] && [ -n "$verdict" ] || {
  kit_warn "usage: --finding ID (--fixed|--open) [--commit SHA] [--note TEXT]"
  kit_warn "       --list [--task ID] [--severity SEV] [--unfixed]"; exit 2; }

# REFUSE AN ID NO FINDING HAS. Appending it would put a mark in the permanent log that the
# indexer can only report as an orphan for the rest of the repository's life, and the operator
# who typed it would have seen exit 0 and believed the finding was marked. A typo must fail
# where it is made, not in a report nobody reads afterwards.
if db_readable; then
  fesc=$(printf '%s' "$finding" | sed "s/'/''/g")
  hit=$(sqlite3 -noheader "$DB" "SELECT COUNT(*) FROM finding WHERE id='$fesc';" 2>/dev/null)
  if [ "${hit:-0}" = 0 ]; then
    kit_warn "no finding has id '$finding' -- run kit-resolve.sh --list to see them"
    kit_warn "  (ids are content-derived; they change only if the event line does)"
    exit 2
  fi
  # REFUSED HERE, not silently discarded later. An id at a collided base cannot be attached to
  # one of its findings without guessing, so the indexer withholds the mark -- and this used to
  # print "kit: fixed recorded" anyway. A success message for something no rebuild will ever
  # apply is worse than an error, because the operator stops thinking about it.
  amb=$(sqlite3 -noheader "$DB" "SELECT COALESCE(id_ambiguous,0) FROM finding WHERE id='$fesc';" 2>/dev/null)
  if [ "${amb:-0}" = 1 ]; then
    kit_warn "'$finding' is AMBIGUOUS: another event hashes to the same id"
    kit_warn "  a mark here would be a guess about which finding it addresses, so it is refused"
    kit_warn "  (the indexer would withhold it on every rebuild; this fails now instead)"
    exit 2
  fi
  # The task the finding belongs to, carried on the event so a task timeline shows its findings
  # being resolved. Without it `event.task_id` is empty and the mark exists outside every
  # per-task view in the kit.
  ftask=$(sqlite3 -noheader "$DB" "SELECT COALESCE(task_id,'') FROM finding WHERE id='$fesc';" 2>/dev/null)
else
  # No index is not permission to guess. The check is the point of the command.
  kit_warn "index at ${DB#$ROOT/} is missing or unreadable; run kit-index.sh first"
  exit 1
fi

# A SHA THAT DOES NOT RESOLVE IS NOT EVIDENCE. `--commit` was optional and unchecked, so a mark
# with no evidence and a mark citing a commit that never existed were the same row -- and the
# second is worse, because it reads as substantiated. Optional still; but if given, it must name
# a commit in this repository.
if [ -n "$commit" ]; then
  if ! git -C "$ROOT" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    kit_warn "--commit '$commit' does not name a commit in this repository"
    kit_warn "  a mark citing a SHA that does not resolve reads as evidence and is not"
    exit 2
  fi
  # Stored in full. An abbreviation that is unambiguous today collides as the repository grows,
  # and the mark outlives the ambiguity.
  commit=$(git -C "$ROOT" rev-parse "${commit}^{commit}" 2>/dev/null)
fi

mkdir -p "$ROOT/$STATE_DIR"
# Serialisation stays with the one writer that owns it. Building JSON here with printf is the
# defect kit-finding.sh had recorded against it twice: a value carrying a quote corrupts an
# append-only committed log permanently, and the awk reader takes the FIRST match, so a crafted
# field can inject a key the indexer then prefers over the real one.
# The timestamp is stamped by the writer, not passed in from here. It needs sub-second
# resolution -- two marks on one finding in the same second are order-ambiguous and the
# retraction loses -- and `date -u` cannot produce it portably, because BSD date has no %N.
_out=$(python3 "$(dirname "$0")/kit_findings.py" --resolve \
         --finding "$finding" --fixed "$verdict" --commit "$commit" --note "$note" \
         --task "${ftask:-}") || {
  kit_warn "refusing to record: the event could not be serialised"; exit 1; }

# The append is CHECKED, and the value is built before it. Unchecked, a full or unwritable
# events.ndjson still exits 0 and the operator believes the mark landed -- the same false
# success kit-finding.sh had found in it by both round-4 reviewers.
if ! printf '%s\n' "$_out" >> "$ROOT/$STATE_DIR/events.ndjson"; then
  kit_warn "could not append to $STATE_DIR/events.ndjson -- NOTHING was recorded"
  exit 1
fi
printf 'kit: %s recorded for %s\n' "$([ "$verdict" = 1 ] && echo fixed || echo reopened)" "$finding" >&2
