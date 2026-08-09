#!/usr/bin/env bash
# kit-trailers.sh — the one trailer validator.
#
#   kit-trailers.sh message <file>       validate a prepared commit message   (commit-msg)
#   kit-trailers.sh range <rev-range>    validate every commit in a range     (CI gate)
#
# The hook and the CI gate both call this; neither reimplements it. 0.2.1 fixed a bug that
# existed for exactly that reason -- the hook grepped the whole message while the indexer
# read git's trailer block, so commits passed the gate and then vanished from derived
# status. Two validators of the same thing drift apart silently. One cannot.
#
# Exit 0 when clean, or when enforcement is `warn`. Exit 1 when enforcement is `enforce`
# and something failed. --enforce overrides the profile, which is what CI wants: a gate
# that only warns is not a gate.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 0; }
kit_active "$ROOT" || exit 0            # inert in repos that never opted in
PROFILE=$(kit_profile "$ROOT")
TASKS_DIR=$(kit_cfg "$PROFILE" paths.tasks ".project/tasks")

CMD=${1:-}; shift 2>/dev/null || true
FORCE=""; ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --enforce) FORCE=enforce; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) ARG=$1; shift ;;
  esac
done

MODE=$(kit_cfg "$PROFILE" git.trailer_enforcement warn)
# An unrecognised value must not degrade to warn in silence. The only reason to touch this
# key is to make it stricter, so a plausible guess -- block, strict, on, true -- would
# otherwise leave the repo looking enforced while every commit sailed through.
case "$MODE" in
  warn|enforce) ;;
  *) kit_warn "git.trailer_enforcement is '$MODE' — valid values are warn|enforce."
     kit_warn "treating as enforce; correct it in .claude/project-profile.md."
     MODE=enforce ;;
esac
[ -n "$FORCE" ] && MODE=$FORCE

EXEMPT=$(kit_cfg "$PROFILE" git.trivial_pattern '^(chore|docs|style)(\(.*\))?:')

# task_known <id> -- does this id name a real task? The indexer no longer invents a task row
# for an id no file backs, so a typo that gets through no longer joins the backlog silently:
# it lands in `Unresolved task ids` in the status report instead. This check is still the
# cheaper gate by far, and the only one that acts while the commit can still be amended --
# afterwards the id is in pushed history and only the report can help.
task_known() {
  [ -d "$ROOT/$TASKS_DIR" ] || return 0          # no backlog yet: nothing to contradict
  grep -rlq -E "^id:[[:space:]]*$1[[:space:]]*$" "$ROOT/$TASKS_DIR" 2>/dev/null
}

# check_msg <message> -- prints one indented line per problem, nothing when clean.
check_msg() {
  MSG=$1
  case "$MSG" in Merge*|Revert*|fixup!*|squash!*) return 0 ;; esac

  # git.trivial_pattern means trailers are not REQUIRED. It does not mean trailers are not
  # CHECKED. Returning early here let a `docs:` commit carry `Task-Id: <typo>` and `Tier: T9`
  # with no complaint -- and the typo still indexed, creating a titleless phantom task that
  # no file backs and that every count then includes.
  #
  # That happened in this repository, and the trailer is now permanent: a commit message
  # cannot be corrected after it is pushed without rewriting history. Which is the argument
  # for checking at commit time rather than at index time.
  exempt=0
  printf '%s' "$MSG" | head -1 | grep -Eq "$EXEMPT" && exempt=1

  # git is the authority on what IS a trailer, and the whole message is only used to find
  # what git will not see. Getting this backwards produces one of two mirror-image bugs:
  #
  #   grep only  -> prose at column 0 reads as a trailer. A commit message explaining a
  #                 typo'd `Task-Id:` was rejected for containing the typo it described.
  #   parse only -> a trailer stranded before a later paragraph is silently absent, which
  #                 is the 0.2.1 defect where squash-merged commits vanished from the index.
  #
  # So: validate what git parses, and separately report anything present that git will not.
  PARSED=$(printf '%s\n' "$MSG" | git interpret-trailers --parse 2>/dev/null)
  tv() { printf '%s' "$PARSED" | sed -n "s/^$1:[[:space:]]*//p" | head -1; }

  stranded=""
  for k in Task-Id Tier Task-Status Via Fixes-Escape-Of; do
    printf '%s' "$MSG" | grep -Eq "^$k:[[:space:]]*\S" || continue
    printf '%s' "$PARSED" | grep -Eq "^$k:[[:space:]]*\S" && continue
    stranded="$stranded $k"
    printf '  stranded  %s:  present, but not in the final paragraph — git will not index it\n' "$k"
  done
  is_stranded() { case " $stranded " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

  TID=$(tv Task-Id); TIER=$(tv Tier)

  if [ "$exempt" = 0 ]; then
    # Do not also say "missing" for a key already reported as stranded: it is present, and
    # the stranded line already says why it will not count.
    [ -n "$TID" ] || is_stranded Task-Id ||
      printf '  missing  Task-Id:      which task does this commit belong to?\n'
    if [ -z "$TIER" ]; then
      is_stranded Tier ||
        printf '  missing  Tier:  one of T0 T1 T2 T3 — required for escape-rate measurement\n'
    fi
  fi

  # A value that IS parsed must be valid, exempt or not. Absence is what the exemption
  # forgives; a wrong value is never forgiven.
  case "${TIER:-}" in ''|T0|T1|T2|T3) ;;
    *) printf '  invalid  Tier: %s  — one of T0 T1 T2 T3\n' "$TIER" ;;
  esac

  v=$(tv Task-Status)
  if [ -n "$v" ]; then
    case "$v" in started|progress|blocked|unblocked|done|abandoned) ;;
      *) printf '  invalid  Task-Status: %s\n' "$v" ;;
    esac
  fi

  # How the work was done. Optional -- absence means unknown, which is a real reported value
  # and not a synonym for any of the others. A wrong value is still never forgiven: a rejected
  # trailer is fixable while you are writing it, a believed-but-wrong one never is.
  v=$(tv Via)
  if [ -n "$v" ]; then
    _ok=0
    for _w in $(kit_via_vocab); do [ "$v" = "$_w" ] && _ok=1; done
    [ "$_ok" = 1 ] || printf '  invalid  Via: %s  — one of %s\n' "$v" "$(kit_via_vocab)"
  fi

  for k in Task-Id Fixes-Escape-Of; do
    v=$(tv "$k")
    [ -n "$v" ] || continue
    task_known "$v" || printf '  unknown  %s: %s — matches no task in %s\n' "$k" "$v" "$TASKS_DIR"
  done
}

report() {   # report <label> <failures>
  [ -n "$2" ] || return 0
  printf 'kit: %s\n%s\n' "$1" "$2" >&2
  return 1
}

RC=0
case "$CMD" in
  message)
    [ -f "$ARG" ] || { kit_warn "usage: kit-trailers.sh message <file>"; exit 2; }
    OUT=$(check_msg "$(cat "$ARG")")
    report "commit trailers" "$OUT" || RC=1
    ;;
  range)
    [ -n "$ARG" ] || { kit_warn "usage: kit-trailers.sh range <rev-range>"; exit 2; }
    # Exclude everything reachable from git.adopted_at. A repository that adopted the kit
    # part-way through its life has history that predates the convention, and failing a
    # pull request for commits written before the rule existed is how a gate gets removed.
    ADOPT=$(kit_cfg "$PROFILE" git.adopted_at "")
    if [ -n "$ADOPT" ] && git -C "$ROOT" rev-parse -q --verify "$ADOPT^{commit}" >/dev/null 2>&1; then
      SET=$(git -C "$ROOT" rev-list --no-merges "$ARG" "^$ADOPT" 2>/dev/null | tr -d '\r')
    else
      [ -n "$ADOPT" ] && kit_warn "git.adopted_at '$ADOPT' is not a commit in this repository"
      SET=$(git -C "$ROOT" rev-list --no-merges "$ARG" 2>/dev/null | tr -d '\r')
    fi
    N=0; BAD=0
    for SHA in $SET; do
      N=$((N + 1))
      OUT=$(check_msg "$(git -C "$ROOT" show -s --format=%B "$SHA")")
      if [ -n "$OUT" ]; then
        BAD=$((BAD + 1))
        report "$(git -C "$ROOT" show -s --format='%h %s' "$SHA")" "$OUT" || true
      fi
    done
    [ "$N" -gt 0 ] || kit_warn "no commits in range '$ARG' — nothing to check"
    if [ "$BAD" -gt 0 ]; then
      kit_warn "$BAD of $N commit(s) failed trailer validation"
      RC=1
    else
      printf 'kit: %d commit(s) checked, all trailers valid\n' "$N"
    fi
    ;;
  *)
    kit_warn "usage: kit-trailers.sh message <file> | range <rev-range> [--enforce]"
    exit 2 ;;
esac

[ "$RC" = 0 ] && exit 0
if [ "$MODE" = enforce ]; then
  printf '\nSet git.trailer_enforcement: warn in project-profile.md to downgrade this.\n' >&2
  exit 1
fi
exit 0
