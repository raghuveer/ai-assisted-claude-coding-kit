#!/usr/bin/env bash
# kit-preflight.sh --isolated <copy>     the subject copy has no path back to the subject
# kit-preflight.sh --spend               spend capture is live in THIS repository
# kit-preflight.sh --criticals           no unfixed critical is outstanding in THIS repository
# kit-preflight.sh --unassessable        the standing blind spot --criticals deliberately excludes
# kit-preflight.sh --superseded          the OTHER thing it excludes: findings whose subject died
#
# The checks docs/TRIAL-PROTOCOL.md §0 gates on, as commands rather than as prose. A pre-flight
# box that a human evaluates by reading is a box that gets ticked while tired; two of this
# document's own boxes were wrong for a year in ways nobody noticed until someone ran them.
#
# Exit 0 = the property holds. Exit 1 = it does not, and the reason is printed. Exit 2 = the
# question could not be asked (bad usage, missing path) -- which is NOT a pass, and is why the
# caller must check the status rather than the output.
set -uo pipefail

usage() { printf 'usage: kit-preflight.sh --isolated <copy> | --spend | --criticals | --unassessable | --superseded\n' >&2; exit 2; }

case "${1:-}" in
  --isolated)
    COPY=${2:-}
    [ -n "$COPY" ] || usage
    # Every failure here is loud. A trial that begins against a subject with a live remote is
    # the one outcome the operator explicitly forbade, and `git push` is a Bash call that
    # kit-guard.sh does not match -- so this check is the only thing standing between an agent
    # and the subject's branches.
    if [ ! -d "$COPY" ]; then
      printf 'kit: %s is not a directory -- the question cannot be asked, so this is not a pass\n' "$COPY" >&2
      exit 2
    fi
    if ! git -C "$COPY" rev-parse --git-dir >/dev/null 2>&1; then
      printf 'kit: %s is not a git repository\n' "$COPY" >&2
      printf '  A trial subject must be one: the protocol records a baseline SHA and reads history.\n' >&2
      exit 1
    fi
    fail=0
    remotes=$(git -C "$COPY" remote 2>/dev/null)
    if [ -n "$remotes" ]; then
      printf 'kit: STOP -- the copy still has a remote:\n' >&2
      git -C "$COPY" remote -v 2>/dev/null | sed 's/^/  /' >&2
      printf '  `git push` is a Bash call and the guard hook does not match Bash, so nothing\n' >&2
      printf '  else prevents a push to the subject. Remove it: git -C %s remote remove <name>\n' "$COPY" >&2
      fail=1
    fi
    # A `--shared` or `--reference` clone BORROWS the subject's object store through
    # `alternates` -- a path back that `git remote -v` does not show, and one that lets `git gc`
    # in either repository affect the other.
    #
    # WHAT THIS DOES NOT DETECT: a plain local `git clone` without `--no-hardlinks`. That
    # hardlinks object files rather than writing an alternates entry, so nothing here can see
    # it. Git objects are immutable, so a hardlinked clone cannot corrupt the subject by
    # writing -- but pruning can, which is why the protocol still says `--no-hardlinks`. Said
    # out loud because a check that silently covers less than its heading claims is the defect
    # this file is full of fixes for.
    gd=$(git -C "$COPY" rev-parse --git-dir 2>/dev/null)
    case "$gd" in /*) alt="$gd/objects/info/alternates" ;; *) alt="$COPY/$gd/objects/info/alternates" ;; esac
    if [ -s "$alt" ]; then
      printf 'kit: STOP -- the copy shares an object store with another repository:\n' >&2
      sed 's/^/  /' "$alt" >&2
      printf '  Re-clone with --no-hardlinks. An alternates entry is a path back that\n' >&2
      printf '  `git remote -v` does not show.\n' >&2
      fail=1
    fi
    [ "$fail" = 0 ] || exit 1
    printf 'kit: %s is isolated -- no remote, no shared object store\n' "$COPY"
    exit 0 ;;

  --unassessable)
    # THE THIRD STATE. `--criticals` excludes `unassessable_at IS NOT NULL` on purpose — those
    # findings cannot be judged from what survives, so leaving them in would make the gate
    # permanently unsatisfiable and no trial could ever run. The cost of that exclusion is that
    # a repository whose every remaining critical is unassessable reports **zero** and the §0
    # box passes, silently, with the blind spot intact. That is the shape TRIAL-PROTOCOL §0 now
    # names, and this is the command it calls.
    #
    # Exit 0 either way, deliberately: a standing blind spot is not a stop, it is something the
    # report must carry. Returning non-zero would make it a gate, and a gate nobody can ever
    # satisfy is the failure the unassessable route was built to remove. The stop conditions are
    # judgement and live in the protocol, not here — this command supplies the NUMBER they are
    # judged against, which is the part a human should not be counting by hand.
    . "$(dirname "$0")/kit-lib.sh"
    ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
    kit_active "$ROOT" || { kit_warn "the kit is not adopted here"; exit 2; }
    STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
    DB="$ROOT/$STATE_DIR/index.db"
    [ -f "$DB" ] || { kit_warn "no index at ${DB#$ROOT/}; run kit-index.sh"; exit 2; }
    n=$(sqlite3 -noheader "$DB" "SELECT COUNT(*) FROM finding
                                  WHERE severity='critical' AND fixed_at IS NULL
                                    AND unassessable_at IS NOT NULL;" 2>&1)
    case "$n" in
      ''|*[!0-9]*)
        kit_warn "the unassessable query FAILED -- this is not a report of zero"
        printf '%s\n' "$n" | sed 's/^/  /' >&2
        kit_warn "  the usual cause is an index older than a column this query reads; rebuild it"
        exit 2 ;;
    esac
    if [ "$n" = 0 ]; then
      printf 'no unassessable critical: --criticals is the whole picture\n'
      exit 0
    fi
    printf '%s unassessable critical(s) — EXCLUDED from --criticals, and still true:\n' "$n"
    sqlite3 -noheader -separator '  ' "$DB" \
      "SELECT id, COALESCE(task_id,'(no task)'), COALESCE(unassessable_reason,'(no reason recorded)')
         FROM finding WHERE severity='critical' AND fixed_at IS NULL
          AND unassessable_at IS NOT NULL ORDER BY task_id, id;" 2>/dev/null |
      tr -d '\r' | sed 's/^/  /'
    printf 'Record this number in the trial report. TRIAL-PROTOCOL section 0 says when it stops you.\n'
    exit 0 ;;

  --superseded)
    # THE FOURTH STATE, and it needs its own box for the same reason the third does: `--criticals`
    # excludes it, so a repository whose every remaining critical was superseded reports ZERO and
    # passes §0 with nothing said. Adding an exclusion to the gate without adding the report that
    # exposes it is how a gate quietly stops meaning what its reader thinks it means -- and this
    # repository was in exactly that state the moment the fourth verb landed: the gate went to
    # zero with thirteen criticals excluded behind it.
    #
    # It is NOT the same blind spot as --unassessable, and merging the two counts would lose the
    # distinction that matters. An unassessable critical is unreadable: nobody can say what it
    # was. A superseded one is perfectly readable, was REAL, and its subject was withdrawn --
    # frequently BECAUSE of it. One is missing evidence; the other is evidence that worked.
    #
    # Exit 0 either way, for the reason --unassessable does: this supplies the number, the
    # protocol supplies the judgement.
    . "$(dirname "$0")/kit-lib.sh"
    ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
    kit_active "$ROOT" || { kit_warn "the kit is not adopted here"; exit 2; }
    STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
    DB="$ROOT/$STATE_DIR/index.db"
    [ -f "$DB" ] || { kit_warn "no index at ${DB#$ROOT/}; run kit-index.sh"; exit 2; }
    n=$(sqlite3 -noheader "$DB" "SELECT COUNT(*) FROM finding
                                  WHERE severity='critical' AND fixed_at IS NULL
                                    AND unassessable_at IS NULL
                                    AND superseded_at IS NOT NULL;" 2>&1)
    case "$n" in
      ''|*[!0-9]*)
        kit_warn "the superseded query FAILED -- this is not a report of zero"
        printf '%s\n' "$n" | sed 's/^/  /' >&2
        kit_warn "  the usual cause is an index older than a column this query reads; rebuild it"
        exit 2 ;;
    esac
    if [ "$n" = 0 ]; then
      printf 'no superseded critical: --criticals is not hiding a withdrawn subject\n'
      exit 0
    fi
    printf '%s superseded critical(s) — EXCLUDED from --criticals, and each one was REAL:\n' "$n"
    sqlite3 -noheader -separator '  ' "$DB" \
      "SELECT id, COALESCE(task_id,'(no task)'), COALESCE(file_path,'(no subject)'),
              'superseded by '||COALESCE(superseded_by,'(not recorded)')
         FROM finding WHERE severity='critical' AND fixed_at IS NULL
          AND unassessable_at IS NULL
          AND superseded_at IS NOT NULL ORDER BY task_id, id;" 2>/dev/null |
      tr -d '\r' | sed 's/^/  /'
    printf 'Record this number in the trial report. These are not repairs; they are subjects that died.\n'
    exit 0 ;;

  --criticals)
    . "$(dirname "$0")/kit-lib.sh"
    ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
    kit_active "$ROOT" || { kit_warn "the kit is not adopted here"; exit 2; }
    STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
    DB="$ROOT/$STATE_DIR/index.db"
    # REFRESH BEFORE QUERYING. This opened the database and queried it, and `index.db` is
    # gitignored -- so the gate's answer was a function of WHEN SOMEONE LAST RAN THE INDEXER,
    # not of the repository. `kit-status.sh` rebuilds only when the file is absent, so a stale
    # index produced a confident number from an unknown point in history. `--spend` already
    # rebuilds first and says why; the same reasoning was never carried one box up.
    #
    # `--if-stale` rather than an unconditional rebuild, because a full build costs ~39s here
    # and this runs at every pre-flight. That is only safe now: until the staleness check
    # compared resolved commits it answered FRESH across a commit, so `--if-stale` here would
    # have inherited exactly the defect this is closing. The two changes are one fix.
    #
    # A build that FAILS refuses rather than falling through to the old file. Reporting a
    # number silently is the one option the acceptance criteria reject, and a gate that
    # answers from a database it could not refresh is that option wearing a rebuild.
    bash "$(dirname "$0")/kit-index.sh" --if-stale >/dev/null 2>&1 || {
      kit_warn "the index could not be refreshed, so the criticals gate cannot be trusted"
      kit_warn "  run kit-index.sh and read its error; this refuses rather than reporting a"
      kit_warn "  count derived from an unknown point in history."
      exit 2; }
    [ -f "$DB" ] || { kit_warn "no index at ${DB#$ROOT/}; run kit-index.sh"; exit 2; }
    # ONE HOME FOR THIS PREDICATE. It used to be inlined in docs/TRIAL-PROTOCOL.md §0 and again
    # in kit-status.sh, which is two copies of a rule that has already been wrong twice -- once
    # filtering by task state, once excluding refutations too eagerly. The document calls this.
    #
    # A refuted critical is excluded ONLY IF the refutation is unambiguous. `kit-vindicate.sh`
    # keys on (task, class) and marks every finding matching both, so on a task with two
    # `fail-open` findings a single `--false` about the harmless one also refutes the critical
    # -- and the critical would leave the gate having never been judged. Fail closed: a
    # class-scoped refutation retires a finding only when it is the sole finding of that class
    # on that task.
    # A finding the operator has explicitly marked unassessable leaves the gate, and ONLY one
    # marked individually does. The exclusion is deliberately not `summary IS NULL` -- that
    # would exempt every FUTURE critical whose summary is missing, turning a bounded historical
    # problem into an unbounded hole. Nine rows predate the summary column and cannot be judged
    # from what survives; each is named by its own `finding-unassessable` event carrying a
    # reason, and kit-status.sh reports the total as a standing blind spot rather than folding
    # it into zero. Excluded from the gate, never from the record.
    # A finding whose SUBJECT was withdrawn leaves the gate on the same terms and for the same
    # reason: it is excluded from the gate and never from the record. It is individually marked,
    # the mark names what withdrew the subject, and kit-resolve.sh refuses it unless the subject
    # file itself carries a matching `Superseded-by:` line -- so this exclusion is reachable only
    # by an operator who wrote the withdrawal into the tree where the next reader will see it.
    # Without the fourth verb, 31 findings reviewing a rejected design sat here permanently and
    # their task could never close no matter how much correct work was done on it.
    n=$(sqlite3 -noheader "$DB" "
      SELECT COUNT(*) FROM finding f
       WHERE f.severity='critical' AND f.fixed_at IS NULL
         AND f.unassessable_at IS NULL
         AND f.superseded_at IS NULL
         AND NOT (COALESCE(f.vindicated,1) = 0 AND 1 = (
               SELECT COUNT(*) FROM finding g
                WHERE COALESCE(g.task_id,'') = COALESCE(f.task_id,'')
                  AND COALESCE(g.class,'')   = COALESCE(f.class,'')));" 2>&1)
    case "$n" in
      ''|*[!0-9]*)
        kit_warn "the criticals query FAILED -- this is not a report of zero"
        printf '%s\n' "$n" | sed 's/^/  /' >&2
        # Name the SHAPE, not one instance of it. This said "an index built before
        # finding.fixed_at existed", which was the only cause when it was written and stopped
        # being so the moment `unassessable_at` was added -- so the message would have sent the
        # reader hunting for the wrong column. Same defect as
        # T-20260809-the-unverified-tier-floor-message-names-; the fix is to describe the class.
        kit_warn "  the usual cause is an index older than a column this query reads"
        kit_warn "  (fixed_at, unassessable_at and superseded_at are each newer than some"
        kit_warn "  indexes); rebuild it"
        exit 2 ;;
    esac
    if [ "$n" != 0 ]; then
      kit_warn "STOP -- $n unfixed critical(s) outstanding"
      kit_warn "  kit-status.sh lists them per task; kit-resolve.sh --list --severity critical"
      kit_warn "  --unfixed names them. Closing a task does not count as fixing its criticals."
      exit 1
    fi
    printf 'kit: no unfixed critical outstanding\n'
    exit 0 ;;

  --spend)
    . "$(dirname "$0")/kit-lib.sh"
    ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
    kit_active "$ROOT" || { kit_warn "the kit is not adopted here"; exit 2; }
    STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
    EV="$ROOT/$STATE_DIR/events.ndjson"
    # THE EVENT LOG IS ASKED FIRST, and this ordering is the whole point. Hooks append events;
    # `spend` rows exist only after kit-index.sh derives them. The protocol used to query the
    # index straight after running an agent, which reads whatever the last rebuild contained --
    # so a live recorder failed a check written to detect a dead one. Separating the two
    # questions also separates their causes: no events means the hook never fired, events
    # without rows means the derivation is broken.
    ev=0
    [ -f "$EV" ] && ev=$(grep -c '"kind":"spend"' "$EV" 2>/dev/null)
    ev=${ev:-0}
    bash "$(dirname "$0")/kit-index.sh" >/dev/null 2>&1 || {
      kit_warn "the index could not be rebuilt, so the spend table cannot be trusted"; exit 2; }
    rows=$(sqlite3 -noheader "$ROOT/$STATE_DIR/index.db" "SELECT COUNT(*) FROM spend;" 2>/dev/null)
    rows=${rows:-0}
    if [ "$ev" = 0 ]; then
      kit_warn "STOP -- no spend EVENT has ever been recorded here"
      kit_warn "  The hooks are not firing. They run from SubagentStop and Stop, so a session"
      kit_warn "  started without the plugin loaded records nothing: run the subject under"
      kit_warn "  \`claude --plugin-dir <kit>\`. The entire cost half of a trial would be empty."
      exit 1
    fi
    if [ "$rows" = 0 ]; then
      kit_warn "STOP -- $ev spend event(s) exist but no spend row was derived"
      kit_warn "  The hook fired and the indexer did not pick it up. That is a different fault"
      kit_warn "  from a dead hook and it is in kit-index.sh, not in the harness."
      exit 1
    fi
    printf 'kit: spend capture is live -- %s event(s), %s row(s)\n' "$ev" "$rows"
    exit 0 ;;

  *) usage ;;
esac
