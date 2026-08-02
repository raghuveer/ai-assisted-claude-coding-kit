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

# task_known <id> -- does this id name a real task? A Task-Id matching nothing still
# creates a task row in the index, so a typo silently adds a titleless phantom to the
# backlog and to every count derived from it.
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

  if [ "$exempt" = 0 ]; then
    printf '%s' "$MSG" | grep -Eq '^Task-Id:[[:space:]]*\S' ||
      printf '  missing  Task-Id:      which task does this commit belong to?\n'
    printf '%s' "$MSG" | grep -Eq '^Tier:[[:space:]]*T[0-3][[:space:]]*$' ||
      printf '  missing/invalid  Tier:  one of T0 T1 T2 T3 — required for escape-rate measurement\n'
  else
    # Exempt: absence is fine, a wrong value is not.
    if printf '%s' "$MSG" | grep -Eq '^Tier:[[:space:]]*\S' &&
       ! printf '%s' "$MSG" | grep -Eq '^Tier:[[:space:]]*T[0-3][[:space:]]*$'; then
      printf '  invalid  Tier:  one of T0 T1 T2 T3 (a trivial commit need not carry one at all)\n'
    fi
  fi

  # Git reads trailers only from the LAST paragraph. A message with trailers followed by
  # any further prose -- most often the Co-authored-by: that squash-merge appends -- passes
  # a whole-message grep and is invisible to %(trailers:...), which is what the indexer
  # reads. Catch the divergence where moving three lines is free.
  PARSED=$(printf '%s\n' "$MSG" | git interpret-trailers --parse 2>/dev/null)
  for k in Task-Id Tier Task-Status Fixes-Escape-Of; do
    printf '%s' "$MSG" | grep -Eq "^$k:[[:space:]]*\S" || continue
    printf '%s' "$PARSED" | grep -Eq "^$k:[[:space:]]*\S" && continue
    printf '  stranded  %s:  present, but not in the final paragraph — git will not index it\n' "$k"
  done

  v=$(printf '%s' "$MSG" | sed -n 's/^Task-Status:[[:space:]]*//p' | head -1)
  if [ -n "$v" ]; then
    case "$v" in started|progress|blocked|unblocked|done|abandoned) ;;
      *) printf '  invalid  Task-Status: %s\n' "$v" ;;
    esac
  fi

  for k in Task-Id Fixes-Escape-Of; do
    v=$(printf '%s' "$MSG" | sed -n "s/^$k:[[:space:]]*//p" | head -1)
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
