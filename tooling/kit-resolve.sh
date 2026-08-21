#!/usr/bin/env bash
# kit-resolve.sh --finding ID --fixed [--commit SHA] [--note TEXT]   mark a finding addressed
# kit-resolve.sh --finding ID --open  [--note TEXT]                  retract that mark
# kit-resolve.sh --finding ID --unassessable --reason TEXT           it cannot be judged at all
# kit-resolve.sh --finding ID --superseded --by NAME                 its SUBJECT was withdrawn
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
unass=0; reason=""; supers=0; by=""
while [ $# -gt 0 ]; do
  case "$1" in
    --finding)  finding=${2:-}; shift; shift ;;
    --fixed)    verdict=1; shift ;;
    --open)     verdict=0; shift ;;
    --unassessable) unass=1; shift ;;
    --superseded) supers=1; shift ;;
    --by) by=${2:-}; shift 2 ;;
    --reason)   reason=${2:-}; shift; shift ;;
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
  # The state column carries the REFUTATION too. §0 calls this listing "the ids", and it
  # disagreed with the gate whenever a critical was refuted: the gate excluded it, the listing
  # still showed it as OPEN, and the two numbers could not be reconciled by reading either.
  # `refutd` is a finding a reviewer withdrew; `OPEN?` is one whose refutation is class-scoped
  # and therefore untrustworthy -- it is still in the gate, and the listing now says so.
  out=$(sqlite3 -noheader -separator '  ' "$DB" \
    "SELECT id,
            CASE WHEN fixed_at IS NOT NULL THEN 'fixed'
                 WHEN COALESCE(vindicated,1) = 0 AND 1 = (SELECT COUNT(*) FROM finding g
                        WHERE COALESCE(g.task_id,'') = COALESCE(finding.task_id,'')
                          AND COALESCE(g.class,'')   = COALESCE(finding.class,''))
                   THEN 'refutd'
                 WHEN COALESCE(vindicated,1) = 0 THEN 'OPEN?'
                 ELSE 'OPEN ' END,
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

# Exactly one disposition per invocation. `--fixed --unassessable` is not a compound state: the
# first says the defect was dealt with, the second says nobody can tell what it was. Accepting
# both would write two marks from one command and let last-write-wins pick the meaning.
if [ "$unass" = 1 ] && [ -n "$verdict" ]; then
  kit_warn "--unassessable cannot be combined with --fixed or --open"
  kit_warn "  addressed and unjudgeable are different claims; record one of them"
  exit 2
fi
# Four dispositions now, so the exclusion is counted rather than enumerated pairwise. Written as
# three `if` chains it was already one missed combination away from wrong, and adding a fourth
# would have needed three more comparisons -- the shape where the one nobody writes is the one
# that ships.
_ndisp=0
[ -n "$verdict" ] && _ndisp=$((_ndisp + 1))
[ "$unass" = 1 ]  && _ndisp=$((_ndisp + 1))
[ "$supers" = 1 ] && _ndisp=$((_ndisp + 1))
if [ "$_ndisp" -gt 1 ]; then
  kit_warn "exactly one disposition per invocation; $_ndisp were given"
  kit_warn "  addressed, unjudgeable and superseded are different claims about different"
  kit_warn "  questions. Recording two from one command lets last-write-wins pick the meaning."
  exit 2
fi
if [ "$supers" = 1 ] && [ -z "$by" ]; then
  kit_warn "--superseded requires --by NAME"
  kit_warn "  name the ADR, the later revision, or the commit that withdrew the subject. A mark"
  kit_warn "  that clears a gate without saying what cleared it is a clearance, not a record."
  exit 2
fi
if [ "$supers" != 1 ] && [ -n "$by" ]; then
  kit_warn "--by is only meaningful with --superseded"
  exit 2
fi
[ -n "$finding" ] && { [ -n "$verdict" ] || [ "$unass" = 1 ] || [ "$supers" = 1 ]; } || {
  kit_warn "usage: --finding ID (--fixed|--open) [--commit SHA] [--note TEXT]"
  kit_warn "       --finding ID --unassessable --reason TEXT"
  kit_warn "       --finding ID --superseded --by NAME"
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
  # THE QUERY'S FAILURE IS NOT A ZERO. This read `2>/dev/null` with `${amb:-0}`, so against an
  # index built before `id_ambiguous` existed -- which the row-existence check above passes,
  # because `finding` is still there -- the column error became "not ambiguous" and the refusal
  # was skipped. The tool then printed "recorded" for a mark every rebuild discards. That is the
  # third time in this task that an absent value has been read as a benign one; assume the shape
  # rather than the instance.
  amb=$(sqlite3 -noheader "$DB" "SELECT COALESCE(id_ambiguous,0) FROM finding WHERE id='$fesc';" 2>&1)
  case "$amb" in
    0|1) ;;
    *) kit_warn "cannot tell whether '$finding' is ambiguous -- refusing rather than guessing"
       printf '%s\n' "$amb" | sed 's/^/  /' >&2
       kit_warn "  an index predating id_ambiguous fails here; delete it and run kit-index.sh"
       exit 2 ;;
  esac
  if [ "$amb" = 1 ]; then
    kit_warn "'$finding' is AMBIGUOUS: another event hashes to the same id"
    kit_warn "  a mark here would be a guess about which finding it addresses, so it is refused"
    kit_warn "  (the indexer would withhold it on every rebuild; this fails now instead)"
    exit 2
  fi
  # The task the finding belongs to, carried on the event so a task timeline shows its findings
  # being resolved. Without it `event.task_id` is empty and the mark exists outside every
  # per-task view in the kit.
  ftask=$(sqlite3 -noheader "$DB" "SELECT COALESCE(task_id,'') FROM finding WHERE id='$fesc';" 2>/dev/null)

  # UNASSESSABLE IS FOR FINDINGS THAT CANNOT BE READ, AND FOR NOTHING ELSE. A finding carrying a
  # summary says what it was, so it can be judged -- addressed, refuted, or left open. Allowing
  # this mark on one would turn a narrow escape hatch for rows that predate the `summary` column
  # into a general-purpose way of clearing the criticals gate, which is the laundering the whole
  # disposition exists to avoid. The route is closed by the DATA, not by asking the operator to
  # use it responsibly.
  if [ "$unass" = 1 ]; then
    fsum=$(sqlite3 -noheader "$DB" "SELECT COALESCE(summary,'') FROM finding WHERE id='$fesc';" 2>&1)
    case "$fsum" in
      *"no such column"*|*"Error"*|*"error"*)
        kit_warn "cannot read the summary of '$finding' -- refusing rather than guessing"
        printf '%s\n' "$fsum" | sed 's/^/  /' >&2
        kit_warn "  an index older than the summary column fails here; rebuild it"
        exit 2 ;;
    esac
    if [ -n "$fsum" ]; then
      kit_warn "'$finding' carries a summary, so it CAN be judged -- refusing --unassessable"
      kit_warn "  summary: $fsum"
      kit_warn "  this mark is only for findings whose text does not survive. Use --fixed once"
      kit_warn "  addressed, or kit-vindicate.sh --false if it was never a real defect."
      exit 2
    fi
  fi
  # THE SUBJECT MUST BE MARKED DEAD IN THE TREE, not merely asserted dead on the command line.
  #
  # The obvious guard -- "refuse if the subject file still exists" -- does not work, and finding
  # that out is what shaped this one. The case that produced this verb is 31 findings against
  # docs/design-input/2026-08-15-entry-mechanism.md, a document that is still on disk, still 15KB,
  # and still referenced by an ADR and by its own successor. Rejected designs are KEPT; that is
  # what makes the record worth having. What ended is the subject's STANDING, and standing is not
  # a property of the filesystem.
  #
  # So the operator must write the withdrawal into the subject itself, and this reads it back.
  # Two things follow that a `--by` citation alone would not give:
  #   - it is reviewable in a diff, like every other claim in this repository, instead of being
  #     visible only inside an append-only log nobody reads by hand;
  #   - it lands in front of the NEXT reader of the subject, who is otherwise the person most
  #     likely to act on a document that quietly stopped being true.
  #
  # Why this is not theatre: on the very task that motivated the verb, 26 of its 57 open findings
  # point at subjects that are still live -- design 2, tooling/kit-entry.sh, conformance, an ADR.
  # A verb guarded only by "did you type --by" would have cleared all 57. It has to be able to
  # refuse, and this is the thing it refuses.
  if [ "$supers" = 1 ]; then
    fpath=$(sqlite3 -noheader "$DB" "SELECT COALESCE(file_path,'') FROM finding WHERE id='$fesc';" 2>&1)
    case "$fpath" in
      *"no such column"*|*"Error"*|*"error"*)
        kit_warn "cannot read the file_path of '$finding' -- refusing rather than guessing"
        printf '%s\n' "$fpath" | sed 's/^/  /' >&2
        exit 2 ;;
    esac
    # A finding with no subject on record cannot have its subject checked. Refusing is the only
    # honest answer: allowing it would make "the row happens to be missing an anchor" the widest
    # route out of the gate, which is precisely backwards.
    if [ -z "$fpath" ]; then
      kit_warn "'$finding' records no file_path, so its subject cannot be identified"
      kit_warn "  --superseded is refused: the guard is a marker IN the subject, and there is no"
      kit_warn "  subject to read. If the finding cannot be judged at all, that is --unassessable."
      exit 2
    fi
    if [ ! -f "$ROOT/$fpath" ]; then
      kit_warn "'$fpath' is not a file in this repository, so no marker can be read from it"
      kit_warn "  a subject that was DELETED is a different case from one that was superseded,"
      kit_warn "  and this verb deliberately does not cover it -- deleting the evidence must not"
      kit_warn "  be the cheapest way out of the criticals gate."
      exit 2
    fi
    # The marker is trailer-shaped, matching the idiom this repository already enforces on
    # commits, and is allowed to sit inside a markdown blockquote so it can be written as the
    # callout a reader actually notices. Matched with grep -F on the value, never as a pattern:
    # `$by` is operator text and interpolating it into a regex is a defect this repository has an
    # open task about.
    # The leading class allows `*` and `_` as well as whitespace and `>`, because the marker this
    # command TELLS the operator to write is a bold line inside a blockquote. The first version
    # accepted only whitespace and `>`, so it refused the exact text of its own error message --
    # a guard whose remedy it rejects is worse than no guard, because the operator concludes the
    # withdrawal is unrecognisable and stops trying.
    marker=$(grep -aiE '^[[:space:]>*_]*Superseded-by:' "$ROOT/$fpath" 2>/dev/null | head -1)
    if [ -z "$marker" ]; then
      kit_warn "'$fpath' carries no 'Superseded-by:' line, so its subject still stands"
      kit_warn "  refusing --superseded. This verb records that a subject was WITHDRAWN; if that"
      kit_warn "  happened, say so in the subject where its next reader will see it:"
      kit_warn ""
      kit_warn "      > **Superseded-by: $by**"
      kit_warn ""
      kit_warn "  then re-run this. If the subject still stands, the finding is still open."
      exit 2
    fi
    # A marker naming something OTHER than --by means one of the two is wrong, and the tool cannot
    # tell which. Guessing would make the citation decorative.
    if ! printf '%s' "$marker" | grep -qF -- "$by"; then
      kit_warn "'$fpath' is marked superseded, but not by what --by names"
      kit_warn "  marker: $(printf '%s' "$marker" | sed 's/^[[:space:]>]*//')"
      kit_warn "  --by:   $by"
      kit_warn "  one of them is wrong and this cannot tell which, so it records neither."
      exit 2
    fi
    # Nothing supersedes itself. Without this, marking the subject with its own path satisfies
    # every check above and the guard becomes a formality any operator can perform on any file.
    if [ "$by" = "$fpath" ]; then
      kit_warn "--by names the subject itself ('$fpath')"
      kit_warn "  a document cannot be the thing that withdrew it; name what replaced it."
      exit 2
    fi
  fi
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
_actor=$(git -C "$ROOT" config user.email 2>/dev/null ||
         git -C "$ROOT" config user.name 2>/dev/null || true)
if [ "$unass" = 1 ]; then
  # The blank-reason refusal lives in the writer, not here, so it holds for every caller rather
  # than for this one path. A mark that removes a finding from the criticals gate without saying
  # why is the laundering the whole disposition exists to avoid.
  _out=$(python3 "$(dirname "$0")/kit_findings.py" --unassessable \
           --finding "$finding" --reason "$reason" \
           --task "${ftask:-}" --actor "$_actor") || {
    kit_warn "refusing to record: the event could not be serialised"; exit 1; }
elif [ "$supers" = 1 ]; then
  # The blank --by refusal lives in the writer, not here, so it holds for every caller rather
  # than for this one path -- the same split as --reason on an unassessable mark.
  _out=$(python3 "$(dirname "$0")/kit_findings.py" --superseded \
           --finding "$finding" --by "$by" \
           --task "${ftask:-}" --actor "$_actor") || {
    kit_warn "refusing to record: the event could not be serialised"; exit 1; }
else
  _out=$(python3 "$(dirname "$0")/kit_findings.py" --resolve \
           --finding "$finding" --fixed "$verdict" --commit "$commit" --note "$note" \
           --task "${ftask:-}" --actor "$_actor") || {
    kit_warn "refusing to record: the event could not be serialised"; exit 1; }
fi

# The append is CHECKED, and the value is built before it. Unchecked, a full or unwritable
# events.ndjson still exits 0 and the operator believes the mark landed -- the same false
# success kit-finding.sh had found in it by both round-4 reviewers.
if ! printf '%s\n' "$_out" >> "$ROOT/$STATE_DIR/events.ndjson"; then
  kit_warn "could not append to $STATE_DIR/events.ndjson -- NOTHING was recorded"
  exit 1
fi
if [ "$supers" = 1 ]; then
  printf 'kit: superseded recorded for %s\n' "$finding" >&2
  printf 'kit:   by: %s\n' "$by" >&2
  printf 'kit:   it leaves the criticals gate and STAYS in the record. A design that died\n' >&2
  printf 'kit:   because a review found problems with it is evidence the review worked, and\n' >&2
  printf 'kit:   kit-status.sh reports the count separately rather than folding it into zero.\n' >&2
elif [ "$unass" = 1 ]; then
  printf 'kit: unassessable recorded for %s\n' "$finding" >&2
  printf 'kit:   it leaves the criticals gate and STAYS in the record; kit-status.sh reports\n' >&2
  printf 'kit:   the count as a standing blind spot, never as zero.\n' >&2
else
  printf 'kit: %s recorded for %s\n' "$([ "$verdict" = 1 ] && echo fixed || echo reopened)" "$finding" >&2
fi
