#!/usr/bin/env bash
# kit-preflight.sh --isolated <copy>     the subject copy has no path back to the subject
# kit-preflight.sh --spend               spend capture is live in THIS repository
# kit-preflight.sh --criticals           no unfixed critical is outstanding in THIS repository
#
# The checks docs/TRIAL-PROTOCOL.md §0 gates on, as commands rather than as prose. A pre-flight
# box that a human evaluates by reading is a box that gets ticked while tired; two of this
# document's own boxes were wrong for a year in ways nobody noticed until someone ran them.
#
# Exit 0 = the property holds. Exit 1 = it does not, and the reason is printed. Exit 2 = the
# question could not be asked (bad usage, missing path) -- which is NOT a pass, and is why the
# caller must check the status rather than the output.
set -uo pipefail

usage() { printf 'usage: kit-preflight.sh --isolated <copy> | --spend\n' >&2; exit 2; }

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

  --criticals)
    . "$(dirname "$0")/kit-lib.sh"
    ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
    kit_active "$ROOT" || { kit_warn "the kit is not adopted here"; exit 2; }
    STATE_DIR=$(kit_cfg "$(kit_profile "$ROOT")" paths.state ".project")
    DB="$ROOT/$STATE_DIR/index.db"
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
    n=$(sqlite3 -noheader "$DB" "
      SELECT COUNT(*) FROM finding f
       WHERE f.severity='critical' AND f.fixed_at IS NULL
         AND NOT (COALESCE(f.vindicated,1) = 0 AND 1 = (
               SELECT COUNT(*) FROM finding g
                WHERE COALESCE(g.task_id,'') = COALESCE(f.task_id,'')
                  AND COALESCE(g.class,'')   = COALESCE(f.class,'')));" 2>&1)
    case "$n" in
      ''|*[!0-9]*)
        kit_warn "the criticals query FAILED -- this is not a report of zero"
        printf '%s\n' "$n" | sed 's/^/  /' >&2
        kit_warn "  an index built before finding.fixed_at existed fails here; rebuild it"
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
