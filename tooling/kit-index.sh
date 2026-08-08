#!/usr/bin/env bash
# kit-index.sh — full rebuild of the derived index from text sources.
# Idempotent: two consecutive runs produce identical output.
# Sources of truth: tasks/*.md frontmatter, git trailers, events.ndjson.
# The index is derived. Deleting it must never lose information.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 0; }
kit_active "$ROOT" || exit 0                    # inert in repos that never opted in
PROFILE=$(kit_profile "$ROOT")

TASKS_DIR=$(kit_cfg "$PROFILE" paths.tasks ".project/tasks")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state  ".project")
ADOPT=$(kit_cfg "$PROFILE" git.adopted_at "")   # commit-ish; history before it has no trailers
# Same key the commit-msg hook uses. Read here so the untagged counter and the hook
# agree on what "trivial" means -- they disagreed, so the discipline warning fired on
# repositories whose every non-trivial commit was correctly tagged.
EXEMPT=$(kit_cfg "$PROFILE" git.trivial_pattern '^(chore|docs|style)(\(.*\))?:')

DB="$ROOT/$STATE_DIR/index.db"
# A build that failed leaves this beside the index, and --if-stale refuses to call the index
# fresh while it exists. mtime alone is not enough: it only notices causes that are WATCHED
# below, and an ingest.extra adapter is not one -- so a build failing because of an adapter
# announced itself once and every later run went quiet over the same stale index. Outside the
# index on purpose; a marker inside it would be recorded in the file the failure corrupted.
FAILED_MARK="$DB.failed"
build_failed() { : > "$FAILED_MARK" 2>/dev/null; exit 1; }

# ---- the ingest seam ---------------------------------------------------------------
# Sections 1-3 below turn a SOURCE into SQL. Section 4 derives current state from that SQL
# and knows nothing about where it came from. That split is what makes an alternative
# backend -- GitHub issues, a REST API, a hosted database -- a matter of replacing one
# producer rather than rewriting the indexer, and it only holds because the index is
# derived: delete it, rebuild, and nothing is lost. See docs/ADAPTERS.md for the contract.
#
# Built-ins stay inline rather than being spawned through the same contract. A bare process
# spawn costs ~0.2s on Windows and this runs at the start of every session; paying three of
# them to make the default path symmetrical would undo the optimisation section 1 exists for.
# They honour the same contract, they just are not invoked across a process boundary.
SRC_TASKS=$(kit_cfg   "$PROFILE" ingest.tasks   files)    # files  | none | <executable>
SRC_EVENTS=$(kit_cfg  "$PROFILE" ingest.events  ndjson)   # ndjson | none | <executable>
SRC_COMMITS=$(kit_cfg "$PROFILE" ingest.commits git)      # git    | none

# ---- co-change ---------------------------------------------------------------------
# `touches` edges need a Task-Id, so a repository adopted brownfield has an empty edge
# table and blast radius is unknown for everything -- and unknown is floored at T2, so the
# whole backlog over-tiers. Co-change is derived from raw history and needs no trailers,
# which is the only signal available on day one.
#
# Parameters are the measured ones (docs/DESIGN-NOTES.md), not guesses:
#   commit_cap  barely moves recall but is what stops bulk commits connecting everything
#   hub_pct     15-25% measured best; 5-10% actively hurt. Same remedy as cluster.hub_cap
#   max_degree  the self-check. A monolith may still produce a hairball -- that case is
#               untested -- so the indexer measures its own graph and withholds it rather
#               than emitting one that would report "everything" with false confidence.
# A minimum edge weight is deliberately absent: it was measured and it HURT.
CC_ON=$(kit_cfg  "$PROFILE" cochange.enabled    true)
CC_CAP=$(kit_cfg "$PROFILE" cochange.commit_cap 50)
CC_HUB=$(kit_cfg "$PROFILE" cochange.hub_pct    20)
# 50 is calibrated, not round: a real 676-commit repository measured 20.8 average partners
# per file, and a synthetic sweeping-change repository measured 79.4. A false refusal costs
# nothing -- blast radius falls back to the honest "unknown" it reports today -- while a
# false accept produces a graph that answers "everything" with confidence. Err low.
CC_MAXD=$(kit_cfg "$PROFILE" cochange.max_degree 50)
case "$CC_ON" in true|1|yes) CC_ON=1 ;; *) CC_ON=0 ;; esac
# Name the profile key, not the shell variable. A message about CC_CAP tells the reader
# nothing they can act on; cochange.commit_cap is a line they can go and fix.
for _p in "CC_CAP cochange.commit_cap" "CC_HUB cochange.hub_pct" "CC_MAXD cochange.max_degree"; do
  eval "_x=\${${_p%% *}}"
  case "$_x" in ''|*[!0-9]*)
    kit_warn "${_p##* } must be a whole number, got '$_x' — co-change disabled"; CC_ON=0 ;;
  esac
done

# adapter_path <spec> -- absolute path to an external ingester, or empty for a built-in.
adapter_path() {
  case "$1" in
    files|ndjson|git|none|'') return 1 ;;
    /*|?:*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$ROOT" "$1" ;;
  esac
}

# run_adapter <spec> <verb> -- invoke an external ingester. `emit` writes SQL to stdout,
# `fingerprint` writes a short opaque string describing the current state of the source.
#
# The statement filter is a net, not a security boundary: an adapter is trusted code named
# in a committed, reviewed profile, and it necessarily emits SQL that gets executed. The
# filter catches an adapter that accidentally reshapes the database, not one that means to.
run_adapter() {
  _ap=$(adapter_path "$1") || return 1
  if [ ! -x "$_ap" ] && [ ! -f "$_ap" ]; then
    kit_warn "ingest adapter not found: $1"; return 2
  fi
  _out=$(KIT_ROOT="$ROOT" KIT_PROFILE="$PROFILE" KIT_STATE_DIR="$STATE_DIR" \
         KIT_TASKS_DIR="$TASKS_DIR" KIT_ADOPT="$ADOPT" KIT_DB="$DB" \
         bash "$_ap" "$2" 2>/dev/null) || {
    # Fail closed. A partial index is not a smaller truth, it is a wrong one -- an absent
    # task reads as a finished backlog, which is the failure derived status exists to avoid.
    kit_warn "ingest adapter failed: $1 $2"; return 2
  }
  if [ "$2" = emit ] && printf '%s' "$_out" |
     grep -qiE '(^|[[:space:];])(attach|detach|pragma|drop|alter|vacuum)[[:space:]]'; then
    kit_warn "ingest adapter $1 emitted a schema-altering statement; refusing"; return 2
  fi
  printf '%s\n' "$_out"
}

# --if-stale: skip the rebuild when nothing it derives from has changed. task-context runs
# this at the start of every session, and a full reindex there is pure latency on a backlog
# that has not moved.
#
# Local sources are compared by mtime. An external adapter cannot be: a GitHub issue changes
# with no local file touched, so mtime would report fresh forever. Those declare a
# fingerprint instead, which is stored in meta and compared on the next run.
if [ "${1:-}" = "--if-stale" ] && [ -f "$DB" ] && [ ! -e "$FAILED_MARK" ]; then
  STALE=0
  WATCH="$PROFILE"
  [ "$SRC_TASKS"  = files ]  && WATCH="$WATCH $ROOT/$TASKS_DIR"
  [ "$SRC_EVENTS" = ndjson ] && WATCH="$WATCH $ROOT/$STATE_DIR/events.ndjson"
  if [ "$SRC_COMMITS" = git ]; then
    HEADF=$(cd "$ROOT" && git rev-parse --git-path HEAD 2>/dev/null)
    case "$HEADF" in /*|?:*) ;; *) HEADF="$ROOT/$HEADF" ;; esac
    WATCH="$WATCH $HEADF"
  fi
  # shellcheck disable=SC2086
  [ -n "$(find $WATCH -newer "$DB" 2>/dev/null | head -1)" ] && STALE=1
  if [ "$STALE" = 0 ]; then
    for _s in "$SRC_TASKS" "$SRC_EVENTS"; do
      adapter_path "$_s" >/dev/null || continue
      _now=$(run_adapter "$_s" fingerprint) || { STALE=1; break; }
      _was=$(sqlite3 "$DB" "SELECT value FROM meta WHERE key='fingerprint:$_s';" 2>/dev/null | tr -d '\r')
      [ "$_now" = "$_was" ] || { STALE=1; break; }
    done
  fi
  if [ "$STALE" = 0 ]; then
    printf '%s\n' "${DB#$ROOT/}"
    exit 0
  fi
fi
SQL=$(mktemp); KIT_REFUSED=$(mktemp); export KIT_REFUSED
trap 'rm -f "$SQL" "$KIT_REFUSED" "$KIT_SEEN"' EXIT
mkdir -p "$ROOT/$STATE_DIR"
ADAPTER_FAILED=0
INGEST_FAILED=0; TASKS_EXPECTED=0; TASKS_EMPTY=""; KIT_SEEN=""; NEW=""

# The whole build is assembled before the existing index is touched. An ingest source can
# now fail -- an adapter for a remote backend fails whenever the network does -- and
# destroying the index first would turn a transient outage into an empty backlog.
{ echo "BEGIN;"

# ---- tier floors -------------------------------------------------------------
# tier.rule is `<path-glob> <tier>`, repeatable. A floor RAISES a tier and never lowers it,
# so a task recorded above its floor is correct and is not flagged.
#
# Matched from two sources, and both are needed. Files a task has already touched come from
# the edge table -- but 7 of 8 open tasks in a real backlog had no touches edges, because
# nothing is committed against a task until work begins. A floor that only sees touched files
# therefore passes silently on every task that has not started, which is exactly when the tier
# still matters: it gates the review that happens DURING the work.
#
# So a task may also declare `paths:` in its frontmatter -- the globs it expects to change.
# Optional, additive, ignored by older kits.
# Rejected here, at the single point both floor paths read from, rather than in either of
# them. A glob containing `[` or `]` cannot mean the same thing on both sides: SQLite GLOB
# honours `[ab]` as a character class (measured), while the awk path would have to translate
# it into an exactly equivalent regex class -- and until it does, one of the two floors would
# quietly differ from the other. An unbalanced `[` is worse than that: SQLite GLOB silently
# never matches, and the regex is uncompilable, which took the whole task pass down.
#
# So the rule is refused and SAID, rather than half-applied. A floor that means two things is
# worse than a floor that is missing and announced -- this is the control that decides how
# many reviewers a change gets.
#
# The refusal is RECORDED, not just printed. kit-status.sh runs the indexer with stderr
# discarded and its output is a file read later, so a warning that exists only on a terminal
# nobody was watching is not a refusal anyone hears -- and the artifact then says "no declared
# paths:" about a task that declares them, which is a false cause dressed as a benign one.
#
# ONE parse, here, emitting the already-split form. There used to be two: this validator read
# the LAST whitespace field as the tier, and a `sed` downstream cut at the FIRST whitespace
# run. They agree on a two-token rule and disagree on everything else -- so `src/** ',x T3`
# passed validation on its trailing `T3` while the consumers took the tier to be `',x T3`.
# That floor sorts below every real tier, so `tier < tier_floor` never fired and an
# under-tiered task simply stopped being reported. Measured: the below-floor section vanished
# from STATUS.generated.md entirely, exit 0, nothing refused.
#
# A validator that checks a different token than the consumers use is not a validator. Two
# fields, both checked, emitted tab-separated so there is nothing left to re-split.
TIER_RULES=$(kit_cfg_all "$PROFILE" tier.rule | awk '
    function refuse(why,   msg) {
      printf "kit: tier.rule ignored — %s: %s\n", why, $0 > "/dev/stderr"
      print $0 > ENVIRON["KIT_REFUSED"]
    }
    {
      line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
      if (line == "") next
      n = split(line, f, /[ \t]+/)
      # The documented grammar is `<path-glob> <tier>`. A third field means the line is not
      # what it looks like -- a glob containing a space, a paste artifact -- and guessing which
      # part is the glob is how the two parses came to differ in the first place.
      if (n != 2)                       { refuse("expected <path-glob> <tier>"); next }
      if (index(f[1], "[") || index(f[1], "]"))
                                        { refuse("[ and ] are not supported in a glob"); next }
      # `?` joins them, for the same reason and on the same evidence. globre maps it to a
      # regex `.`, which this awk matches as a BYTE, while the `?` in SQLite GLOB matches a
      # CHARACTER. Measured: `src/?.go` matches `src/é.go` on the SQL floor and not on the
      # declared-paths floor -- and the declared-paths floor is the one that matters before
      # work starts, when a task has no touches edges yet.
      #
      # Not fixed by making the regex byte-correct: a one-UTF-8-character matcher needs hex
      # escapes inside an awk program, and macOS ships an awk that does not interpret them.
      # The kit already paid for that lesson once (T-20260731-remove-hex-escapes-from-awk-...),
      # and it is not worth re-buying for a character no shipped example uses.
      if (index(f[1], "?"))             { refuse("? is not supported in a glob"); next }
      if (f[2] !~ /^T[0-3]$/)           { refuse(f[2] " is not a tier (T0-T3)"); next }
      printf "%s\t%s\n", f[1], f[2]
    }' | tr '\n' '\036')
# Plain assignment, not `grep ... || echo 0`: grep exits 1 on zero matches, so the `||` ran
# too and the variable held two lines. Every numeric test against it then errored.
REFUSED_N=0; [ -s "$KIT_REFUSED" ] && REFUSED_N=$(grep -c . "$KIT_REFUSED")
if [ "${REFUSED_N:-0}" -gt 0 ]; then
  REFUSED_T=$(tr '\n' ';' < "$KIT_REFUSED" | sed "s/;$//; s/'/''/g")
  printf "INSERT OR REPLACE INTO meta VALUES('tier_rules_refused','%s');\n" "$REFUSED_N"
  printf "INSERT OR REPLACE INTO meta VALUES('tier_rules_refused_text','%s');\n" "$REFUSED_T"
fi

# ---- 1. tasks: frontmatter is authoritative for identity ----------------------
# One awk over every task file, rather than one awk per key plus one sed per quoted value
# -- roughly twenty processes per task before. A bare process spawn costs ~0.5s on Windows,
# so a six-task backlog took ~50s to reindex, and task-context reindexes at the start of
# every session. Identical SQL, identical precedence (first occurrence of a key wins).
HAVE_TASKS=0
if [ "$SRC_TASKS" != files ]; then
  HAVE_TASKS=0
elif [ -d "$ROOT/$TASKS_DIR" ]; then
  for f in "$ROOT/$TASKS_DIR"/*.md; do
    if [ -e "$f" ]; then HAVE_TASKS=1; break; fi
  done
fi
if [ "$HAVE_TASKS" = 1 ]; then
  # Expanded ONCE, into the positional parameters, and used for both the awk arguments and the
  # expected list. Globbing twice put the whole ingest between the two expansions, so a task
  # file written or removed by a concurrent kit-task.sh -- or by an editor's atomic replace --
  # failed the build for a reason that had nothing to do with the build.
  #
  # A zero-byte REGULAR file is EXPECTED to be missing from the read list and is excluded here
  # rather than treated as a loss: awk fires no rule for a file with no records, so
  # `: > T-draft.md` -- create the file now, fill in the frontmatter next -- is
  # indistinguishable downstream from a file that could not be opened. Failing the build on it
  # denied the entire derived state layer, permanently, from an empty stub someone committed.
  # It is named below instead.
  #
  # `-f` as well as `-s`, and in that order. `-s` alone reports a DIRECTORY as empty on this
  # platform, which would have quietly excluded exactly the case the guard exists for -- so
  # anything that exists and is not a regular file is handed to awk on purpose, to be missed
  # and reported.
  set --
  for f in "$ROOT/$TASKS_DIR"/*.md; do
    if   [ -f "$f" ] && [ -s "$f" ]; then set -- "$@" "$f"          # a task file with content
    elif [ -f "$f" ];                then TASKS_EMPTY="$TASKS_EMPTY ${f#$ROOT/}"
    elif [ -e "$f" ];                then set -- "$@" "$f"          # exists, not a regular file
    fi
  done
  KIT_SEEN=$(mktemp); : > "$KIT_SEEN"
  # `if`, not `&&`: with every task file empty there is nothing to hand awk, and awk with no
  # file operands reads stdin and hangs -- a worse failure than the empty backlog it would be
  # reporting. Nor is that an ingest failure; expected and read are both zero, consistently.
  if [ "$#" -gt 0 ]; then
  KIT_PREFIX="$ROOT/" KIT_RULES="$TIER_RULES" KIT_SEEN="$KIT_SEEN" awk '
    function q(s){ gsub(/\047/,"\047\047",s); return s }
    # glob -> regex. * and ** both cross directory separators, which matches SQLite GLOB, so
    # the two floor sources agree with each other. That over-matches `a/*.ts` against
    # `a/b/c.ts` -- a direction that only ever RAISES a tier, which is the safe way to be
    # wrong about a floor.
    #
    # The backslash is escaped FIRST and is in the class for a reason: SQLite GLOB treats `\`
    # as an ordinary character (measured), so leaving it unescaped here both disagreed with
    # the SQL floor and let `\(` compile to an uncompilable regex. `[` and `]` cannot reach
    # this function -- rules carrying them are refused where TIER_RULES is built.
    #
    # `?` cannot reach this function either -- rules carrying it are refused for the same
    # reason, one level up. What remains is `*`, which both engines cross directory separators
    # with, and literal text. Differentially fuzzed against SQLite GLOB at 401,265 glob/subject
    # pairs with zero disagreements; the 96 that did disagree were all `?` on a multi-byte
    # subject, and `?` is now gone. The claim here is agreement, without the ASCII caveat it
    # used to carry.
    function globre(g,   r) {
      r = g
      gsub(/[\\.^$+(){}|]/, "\\\\&", r)
      gsub(/\052+/, ".*", r)
      gsub(/\077/, ".", r)
      return "^" r "$"
    }
    function floorof(paths,   n, i, parts2, j, m, rule, g, t, best, rules) {
      best = ""
      if (paths == "") return ""
      n = split(paths, parts2, /[ ,\t\r]+/)
      m = split(ENVIRON["KIT_RULES"], rules, "\036")
      for (j = 1; j <= m; j++) {
        if (rules[j] == "") continue
        split(rules[j], rule, "\t")
        g = rule[1]; t = rule[2]
        # \r in the class: these come from a profile line, and the readers upstream now strip
        # it -- but a rule whose tier is `T3<CR>` compares wrong rather than failing, and a
        # floor that silently does not apply is the direction under-tiering already fails in.
        gsub(/^[ \t\r]+|[ \t\r]+$/, "", g); gsub(/^[ \t\r]+|[ \t\r]+$/, "", t)
        if (g == "" || t == "") continue
        for (i = 1; i <= n; i++) {
          if (parts2[i] == "") continue
          if (parts2[i] ~ globre(g) && t > best) best = t
        }
      }
      return best
    }
    function emit(   id, ti, st, bb, parts, nd, j, fl) {
      id = v["id"]
      if (id == "") { printf "kit: no id in frontmatter, skipped: %s\n", rel > "/dev/stderr"; return }
      ti = (v["title"] != "" ? v["title"] : id)
      st = (v["state"] != "" ? v["state"] : "open")
      printf "INSERT OR REPLACE INTO node VALUES(\047%s\047,\047task\047,\047%s\047,\047%s\047);\n", q(id), q(rel), q(ti)
      fl = floorof(v["paths"])
      printf "INSERT OR REPLACE INTO task(id,epic,state,tier,lang,blocked_by,tier_floor) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,%s);\n", q(id), q(v["epic"]), q(st), q(v["tier"]), q(v["lang"]), q(v["blocked_by"]), (fl == "" ? "NULL" : "\047" q(fl) "\047")
      # blocked_by is a comma/space separated list of task ids. Frontmatter is where a
      # human declares dependency; edges are how the planner consumes it.
      bb = v["blocked_by"]; gsub(/,/, " ", bb)
      nd = split(bb, parts, /[ \t]+/)
      for (j = 1; j <= nd; j++) {
        if (parts[j] == "") continue
        printf "INSERT OR IGNORE INTO node VALUES(\047%s\047,\047task\047,NULL,\047%s\047);\n", q(parts[j]), q(parts[j])
        printf "INSERT OR IGNORE INTO edge VALUES(\047%s\047,\047%s\047,\047depends_on\047);\n", q(id), q(parts[j])
      }
    }
    # ENVIRON, not -v: awk applies escape processing to -v assignments.
    BEGIN { prefix = ENVIRON["KIT_PREFIX"] }
    FNR==1 {
      if (pending) emit()             # flush the previous file; rel is still its path
      # Which files this pass actually READ, recorded HERE and not in a rule of its own: line
      # one of a task file is its `---`, whose rule ends in `next`, so a later FNR==1 rule
      # never runs for the only line that matters.
      #
      # Names, not a count, and to a channel of their own rather than into the SQL stream. A
      # count says a file went missing without saying which, and a marker written into the SQL
      # shares that stream with every ingest adapter -- one of which emitting a line of the
      # same shape would overwrite the measurement of the thing being measured.
      print FILENAME > ENVIRON["KIT_SEEN"]
      delete v; fm = 0; pending = 1
      rel = FILENAME
      if (index(rel, prefix) == 1) rel = substr(rel, length(prefix) + 1)
    }
    # Task files are hand-authored markdown and arrive CRLF from a Windows checkout, where a
    # trailing CR would ride on every value: `tier: T2<CR>` fails the tier regex, and a `paths:`
    # value carries it into the glob. The trailer reader below already strips CR in its own
    # trim() -- that knowledge was one function away from here and did not travel, which is why
    # this is a per-line strip and not a fifth place to keep in sync.
    { sub(/\r$/, "") }
    /^---[[:space:]]*$/ { fm++; next }
    fm == 1 {
      i = index($0, ":")
      if (i > 1) {
        key = substr($0, 1, i-1); val = substr($0, i+1)
        gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (!(key in v)) v[key] = val
      }
    }
    END { if (pending) emit() }
  ' "$@" || INGEST_FAILED=1
  fi
  TASKS_EXPECTED=$#
fi

# ---- 2. git: trailers are the state transitions, diffs are the touches edges --
# %(trailers:...,valueonly) landed in git 2.32. On anything older the format expands to
# empty, so every commit indexes as untagged: no state transitions, and escape-rate-by-tier
# -- the headline metric -- has nothing to work from. That degradation is invisible in the
# output (it looks like an idle repo), so it has to be said out loud here.
if [ "$SRC_COMMITS" = git ]; then
if [ "$(git --version | awk '{ n=split($3,v,"."); print (v[1]>2 || (v[1]==2 && v[2]>=32)) ? 1 : 0 }')" != 1 ]; then
  kit_warn "git $(git --version | awk '{print $3}') is older than 2.32 — commit trailers"
  kit_warn "cannot be parsed; every commit will index as untagged. Upgrade git."
fi
RANGE=${ADOPT:+$ADOPT..HEAD}
# %B rides along so a commit whose trailers git declines to parse can still be recovered
# below. \002 opens the raw body, \003 closes it, and the --name-only file list follows.
# %ad in an explicit UTC format, not %aI. Two reasons, both found by running one fixture on
# Windows and Debian and diffing the resulting index:
#
#   1. %aI renders the same instant differently across git versions -- 2.47 emits
#      ...T00:00:00Z where 2.41 emits ...T00:00:00+00:00 -- so a mixed-platform team
#      derives different index content from identical history.
#   2. %aI carries the author LOCAL offset, and `at` is TEXT that ORDER BY compares as a
#      string. A commit at 05:30+05:30 then sorts after one at 02:00Z despite being
#      earlier, so state, owner and tier could be derived from the wrong commit.
#
# TZ=UTC0 with format-local renders every commit in one canonical zone, matching the
# `date -u` format kit-finding.sh already writes into events.ndjson. Both sources now
# produce strings whose lexical order is their chronological order.
# -c core.quotepath=false: by default git renders a path containing any byte above 0x7F as
# `"src/\303\251.go"` -- quoted, and octal-escaped. That name is what lands in the `touches`
# edge, so a non-ASCII path is recorded under a name matching no glob, no tier.rule and no
# other reader of the index. Measured, not assumed. The flag makes git emit the path as it is.
TZ=UTC0 git -C "$ROOT" -c core.quotepath=false log --reverse --name-only --no-merges \
    --date=format-local:%Y-%m-%dT%H:%M:%SZ \
    --format=$'\001%H\037%ad\037%an\037%(trailers:key=Task-Id,valueonly,separator=%x1e)\037%(trailers:key=Task-Status,valueonly,separator=%x1e)\037%(trailers:key=Tier,valueonly,separator=%x1e)\037%(trailers:key=Fixes-Escape-Of,valueonly,separator=%x1e)\002%B\003' \
    ${RANGE:+$RANGE} 2>/dev/null |
# -F$'\037', not -F'\037'. gawk and mawk interpret a \x escape in the -F argument; the
# one-true-awk that macOS ships does NOT -- it received the four literal characters
# backslash-x-1-f, split nothing, and every field but the first came back empty. Letting the
# shell expand it to the real byte first is understood by every awk. Escapes INSIDE the
# program text work everywhere; only -F differs.
#
# Note the comment sits ABOVE the assignments: a trailing \ continues onto the next line,
# so a comment placed between them and the awk call silently destroys the whole command.
KIT_SDIR="$STATE_DIR/" KIT_TDIR="$TASKS_DIR/" KIT_EXEMPT="$EXEMPT" \
KIT_CC="$CC_ON" KIT_CCCAP="$CC_CAP" KIT_CCHUB="$CC_HUB" KIT_CCMAXD="$CC_MAXD" \
awk -F$'\037' '
  # Via ENVIRON, not -v: awk applies escape processing to -v assignments, so any path
  # containing a backslash would arrive mangled and silently match nothing.
  BEGIN {
    sdir = ENVIRON["KIT_SDIR"]; tdir = ENVIRON["KIT_TDIR"]
    exempt_re = ENVIRON["KIT_EXEMPT"]
  }
  function q(s){ gsub(/\047/,"\047\047",s); return s }
  function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }

  # separator=%x1e rather than the empty separator used before: a squash-merge routinely
  # carries the same trailer twice, and concatenating the values yielded ids like T-9T-9
  # that match no task and tiers like T2T2 that fail the tier regex -- so the commit both
  # lost its task and counted as untiered. First value wins, the precedence already used
  # for task frontmatter.
  function first(s,  i){ i = index(s, "\036"); return trim(i ? substr(s,1,i-1) : s) }

  # Git recognises a trailer block only in the LAST paragraph. GitHub squash-merge appends
  # Co-authored-by:, which becomes that paragraph and strands Task-Id: in a middle one --
  # still visible to the commit-msg hook, which greps the whole message, and invisible to
  # %(trailers:). The commit passes the gate at author time and then disappears from
  # derived status, in exactly the collaborative flow this kit exists for. The scan is
  # deliberately narrow: only the four keys the kit defines, only at column 0, and only
  # when git found nothing -- it recovers a known shape, it does not add a second dialect.
  function scan(key,  n,a,i,v){
    n = split(body, a, "\n")
    for (i = 1; i <= n; i++)
      if (index(a[i], key ":") == 1) {
        v = trim(substr(a[i], length(key) + 2))
        if (v != "") return v
      }
    return ""
  }

  # subj is the first line of %B. git.trivial_pattern is what the commit-msg hook uses
  # to decide a commit need not carry Task-Id/Tier; this counter must apply the SAME
  # rule or the warning fires on repositories following it exactly -- and a warning
  # that is always on is one people stop reading. Exempt commits still have their
  # trailers indexed: a chore: that legitimately carries a Task-Id keeps its events.
  # Only the counters differ.
  function emit(   bl, n, subj, isexempt){
    total++
    n = split(body, bl, "\n"); subj = (n ? bl[1] : "")
    isexempt = (exempt_re != "" && subj ~ exempt_re)
    if (isexempt) exemptn++
    tid=first(tid); st=first(st); tier=first(tier); esc=first(esc)
    if (tid == "") {
      tid = scan("Task-Id")
      if (tid != "") {
        recovered++
        if (st   == "") st   = scan("Task-Status")
        if (tier == "") tier = scan("Tier")
        if (esc  == "") esc  = scan("Fixes-Escape-Of")
      }
    }
    if (tid=="") { if (!isexempt) untagged++; cur=""; return }
    cur=tid
    if (st!="")   printf "INSERT INTO event(task_id,kind,at,commit_sha,actor) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047);\n", q(tid), q(st), q(at), q(sha), q(who)
    if (tier!="") printf "INSERT INTO event(task_id,kind,at,commit_sha,payload) VALUES(\047%s\047,\047tiered\047,\047%s\047,\047%s\047,\047%s\047);\n", q(tid), q(at), q(sha), q(tier)
    if (esc!="") {
      printf "INSERT INTO event(task_id,kind,at,commit_sha) VALUES(\047%s\047,\047escaped\047,\047%s\047,\047%s\047);\n", q(esc), q(at), q(sha)
      printf "INSERT OR IGNORE INTO edge VALUES(\047%s\047,\047%s\047,\047regressed\047);\n", q(tid), q(esc)
    }
  }

  # Fold the file list of the previous commit into the co-change counts. Called at the next
  # commit header and at END, because a commit is only complete when the next one starts.
  function ccflush(   i, j, a, b, t) {
    if (!CC || nf == 0) return
    if (nf > CCCAP) { ccskipped++; nf = 0; return }   # a bulk commit connects everything
    cctotal++
    for (i = 1; i <= nf; i++) appear[cf[i]]++
    for (i = 1; i <= nf; i++)
      for (j = i + 1; j <= nf; j++) {
        a = cf[i]; b = cf[j]
        if (a > b) { t = a; a = b; b = t }
        if (!((a SUBSEP b) in pc)) npairs++
        pc[a SUBSEP b]++
      }
    nf = 0
    # Memory backstop. Pair count is quadratic in commit size, and a repository that blows
    # through this is one where the graph would be useless anyway.
    if (npairs > 2000000) { CC = 0; ccabort = 1 }
  }

  /^\001/ {
    ccflush()
    sub(/^\001/,"",$1); sha=$1; at=$2; who=$3; tid=$4; st=$5; tier=$6
    p = index($7, "\002")          # $7 is Fixes-Escape-Of, then \002, then body line 1
    esc  = p ? substr($7, 1, p-1) : $7
    body = p ? substr($7, p+1)    : ""
    inbody = 1
    next
  }
  inbody {
    if (index($0, "\003")) { sub(/\003.*$/, "", $0); inbody = 0 }
    body = body "\n" $0
    if (!inbody) emit()
    next
  }
  NF && cur!="" {
    p=$0
    # The kit'"'"'s own state is not project code. Every task edits its task file and appends to
    # the event log, so keeping these edges would make every pair of tasks look coupled --
    # inflating blast radius and collapsing semantic clustering into one blob.
    if (sdir != "" && index(p, sdir) == 1) next
    if (tdir != "" && index(p, tdir) == 1) next
    if (cur != "") {
      printf "INSERT OR IGNORE INTO node VALUES(\047f:%s\047,\047file\047,\047%s\047,NULL);\n", q(p), q(p)
      printf "INSERT OR IGNORE INTO edge VALUES(\047%s\047,\047f:%s\047,\047touches\047);\n", q(cur), q(p)
    }
  }
  END {
    printf "INSERT OR REPLACE INTO meta VALUES(\047commits_total\047,\047%d\047);\n", total
    printf "INSERT OR REPLACE INTO meta VALUES(\047commits_untagged\047,\047%d\047);\n", untagged
    printf "INSERT OR REPLACE INTO meta VALUES(\047commits_exempt\047,\047%d\047);\n", exemptn
    printf "INSERT OR REPLACE INTO meta VALUES(\047commits_trailers_recovered\047,\047%d\047);\n", recovered
  }'
fi   # end SRC_COMMITS = git

# ---- 2b. co-change: a SEPARATE pass, over the WHOLE history -------------------
# Deliberately not folded into the pass above, and deliberately not bounded by
# git.adopted_at. That key exists so pre-adoption commits, which carry no trailers, do not
# pollute task state -- but commits with no trailers are exactly what co-change reads. A
# repository that adopted the kit today has all of its structural signal behind that
# boundary, so scoping this to adopted_at would return nothing in the one case the feature
# was built for. Found by adopting the kit into its own repository, where it did.
#
# cochange.since bounds it only if a project genuinely wants that -- a vendored import, a
# history rewrite. Empty means everything.
if [ "$SRC_COMMITS" = git ] && [ "$CC_ON" = 1 ]; then
CC_SINCE=$(kit_cfg "$PROFILE" cochange.since "")
# %x01, not a shell-quoted $'\001'. A format consisting only of a literal control byte
# produces no output at all; git needs its own escape when there is nothing else in it.
# core.quotepath again, same reason: a mangled name here splits one file into two co-change
# nodes, and neither is the file anyone will look up.
git -C "$ROOT" -c core.quotepath=false log --reverse --no-merges --name-only --format='%x01' \
    ${CC_SINCE:+"$CC_SINCE..HEAD"} 2>/dev/null |
KIT_SDIR="$STATE_DIR/" KIT_TDIR="$TASKS_DIR/" \
KIT_CCCAP="$CC_CAP" KIT_CCHUB="$CC_HUB" KIT_CCMAXD="$CC_MAXD" awk '
  BEGIN {
    sdir = ENVIRON["KIT_SDIR"]; tdir = ENVIRON["KIT_TDIR"]
    CCCAP = ENVIRON["KIT_CCCAP"] + 0
    CCHUB = ENVIRON["KIT_CCHUB"] + 0; CCMAXD = ENVIRON["KIT_CCMAXD"] + 0
  }
  function q(s){ gsub(/\047/,"\047\047",s); return s }

  # A commit is only complete when the next one starts, so fold at the next header and END.
  function flush(   i, j, a, b, t) {
    if (nf == 0) return
    if (nf > CCCAP) { nf = 0; return }        # a bulk commit connects everything
    cctotal++
    for (i = 1; i <= nf; i++) appear[cf[i]]++
    for (i = 1; i <= nf; i++)
      for (j = i + 1; j <= nf; j++) {
        a = cf[i]; b = cf[j]
        if (a > b) { t = a; a = b; b = t }
        pc[a SUBSEP b]++
        if (pc[a SUBSEP b] == 1) npairs++
      }
    nf = 0
    # Pair count is quadratic in commit size. A repository that blows through this is one
    # where the graph would be useless anyway.
    if (npairs > 2000000) { aborted = 1; exit }
  }

  /^\001/ { flush(); next }
  NF {
    p = $0
    if (sdir != "" && index(p, sdir) == 1) next   # kit state is not project code
    if (tdir != "" && index(p, tdir) == 1) next
    cf[++nf] = p
  }

  END {
    flush()
    if (aborted) { print "kit: co-change exceeded the pair budget; graph withheld" > "/dev/stderr"; exit }
    if (cctotal == 0) exit
    hubthr = cctotal * CCHUB / 100
    for (k in pc) {
      sp = index(k, SUBSEP); a = substr(k, 1, sp-1); b = substr(k, sp+1)
      if (appear[a] > hubthr || appear[b] > hubthr) continue
      deg[a]++; deg[b]++; kept++
    }
    for (k in deg) { files++; tot += deg[k] }
    if (!files) exit
    avg = tot / files
    # The self-check. A monolith may still produce a hairball; rather than predict that,
    # measure it. Reporting "everything" with confidence is worse than the honest unknown
    # blast radius already reports without this.
    if (avg > CCMAXD) {
      printf "kit: co-change graph withheld — average file co-changes with %.0f others\n", avg > "/dev/stderr"
      print  "kit: (threshold cochange.max_degree). Blast radius stays unknown, which is honest." > "/dev/stderr"
      exit
    }
    for (k in pc) {
      sp = index(k, SUBSEP); a = substr(k, 1, sp-1); b = substr(k, sp+1)
      if (appear[a] > hubthr || appear[b] > hubthr) continue
      printf "INSERT OR IGNORE INTO node VALUES(\047f:%s\047,\047file\047,\047%s\047,NULL);\n", q(a), q(a)
      printf "INSERT OR IGNORE INTO node VALUES(\047f:%s\047,\047file\047,\047%s\047,NULL);\n", q(b), q(b)
      printf "INSERT OR REPLACE INTO cochange VALUES(\047f:%s\047,\047f:%s\047,%d);\n", q(a), q(b), pc[k]
      printf "INSERT OR REPLACE INTO cochange VALUES(\047f:%s\047,\047f:%s\047,%d);\n", q(b), q(a), pc[k]
    }
    printf "INSERT OR REPLACE INTO meta VALUES(\047cochange_pairs\047,\047%d\047);\n", kept
    printf "INSERT OR REPLACE INTO meta VALUES(\047cochange_files\047,\047%d\047);\n", files
    printf "INSERT OR REPLACE INTO meta VALUES(\047cochange_avg_degree\047,\047%.1f\047);\n", avg
    printf "INSERT OR REPLACE INTO meta VALUES(\047cochange_commits\047,\047%d\047);\n", cctotal
  }'
fi

# ---- 3. events.ndjson: transitions that never had a commit -------------------
EV="$ROOT/$STATE_DIR/events.ndjson"
if [ "$SRC_EVENTS" = ndjson ] && [ -f "$EV" ]; then
  # Sorted by timestamp, then by the whole line, so the index is a function of the SET of
  # events rather than of their order in the file. .gitattributes marks events.ndjson
  # merge=union, so two developers' appends interleave arbitrarily on merge; without this
  # their rebuilds disagree and "delete index.db, rebuild, byte-identical" is false across
  # a team. (sort joins tr/cut/sed/wc, already relied on elsewhere in tooling/.)
  #
  # The second sort key is the spend total. Spend rows are cumulative and REPLACE each
  # other, so the highest must land last; two recordings of one transcript inside the same
  # second would otherwise be ordered by string, where "tok_in":9 sorts after "tok_in":10
  # and the smaller total wins. Zero for every other kind, so their ordering is unchanged.
  awk 'function jn(s,k,  r){ r=0
         if (match(s, "\"" k "\"[ ]*:[ ]*-?[0-9]+")) {
           r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*/,"",r) }
         return r+0 }
       NF {
         a=""
         if (match($0, /"at"[ ]*:[ ]*"[^"]*"/)) {
           a=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[ ]*"/,"",a); sub(/"$/,"",a) }
         t = 0
         if (index($0, "\"spend\"") > 0)
           t = jn($0,"tok_in") + jn($0,"tok_out") + jn($0,"cache_read") + jn($0,"cache_write")
         printf "%s\t%020d\t%s\n", a, t, $0
       }' "$EV" | LC_ALL=C sort | cut -f3- |
  awk '
    function jf(s,k,  r){ r=""
      if (match(s, "\"" k "\"[ ]*:[ ]*\"[^\"]*\"")) {
        r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*"/,"",r); sub(/"$/,"",r) }
      return r }
    # jf reads a quoted string; token counts are bare numbers and need their own reader.
    function jn(s,k,  r){ r=0
      if (match(s, "\"" k "\"[ ]*:[ ]*-?[0-9]+")) {
        r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*/,"",r) }
      return r+0 }
    function q(s){ gsub(/\047/,"\047\047",s); return s }
    NF {
      t=jf($0,"task"); k=jf($0,"kind"); a=jf($0,"at")
      if (k=="") next
      printf "INSERT INTO event(task_id,kind,at,payload) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047);\n", q(t), q(k), q(a), q($0)
      if (k=="finding") {
        cls = jf($0,"class")
        # A classless finding cannot be grouped, counted or promoted -- it only adds a
        # phantom row to the query the accelerators are seeded from. The event itself is
        # still recorded above, so nothing is lost; only the unusable row is dropped.
        if (cls == "") { dropped++ }
        else {
          n++
          printf "INSERT OR REPLACE INTO finding(id,task_id,agent,model,tier,lang,domain,pattern,class,severity,at) VALUES(\047%s:%d\047,\047%s\047,\047%s\047,\047%s\047,NULL,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047);\n", q(a), n, q(t), q(jf($0,"agent")), q(jf($0,"model")), q(jf($0,"lang")), q(jf($0,"domain")), q(jf($0,"pattern")), q(cls), q(jf($0,"severity")), q(a)
        }
      }
      # Spend totals are CUMULATIVE for a transcript, so OR REPLACE keeps the last -- and
      # events arrive sorted by timestamp then by total, so the last is the highest. Summing
      # would count the same tokens once per hook firing.
      if (k=="spend") {
        tr = jf($0,"transcript")
        if (tr != "") {
          sc = jf($0,"scope"); ag = jf($0,"agent")
          # A row written before 0.8.0 carries no scope, and its agent label is the one the
          # defect was about: it names whichever subagent last stopped while the numbers came
          # from the session transcript. The cost is real and is kept; the label is dropped,
          # because a wrong label is believed and an absent one is not.
          if (sc == "") { sc = "legacy"; ag = "" }
          printf "INSERT OR REPLACE INTO spend(transcript,scope,agent,agent_id,session,model,at,turns,tok_in,tok_out,cache_read,cache_write,context) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,%d,%d,%d,%d,%d,%d);\n", q(tr), q(sc), q(ag), q(jf($0,"agent_id")), q(jf($0,"session")), q(jf($0,"model")), q(a), jn($0,"turns"), jn($0,"tok_in"), jn($0,"tok_out"), jn($0,"cache_read"), jn($0,"cache_write"), jn($0,"context")
        }
      }
      if (k=="vindication") {
        # Held back to END. A vindication can precede its finding in the file, and after a
        # union merge routinely does; applied inline it updates zero rows, and kit-accel.sh
        # then reads that finding as unrefuted and proposes it -- exactly the laundering
        # kit-vindicate.sh exists to prevent. Sorted input makes last-write-wins correct.
        nv++
        v[nv] = sprintf("UPDATE finding SET vindicated=%s WHERE task_id=\047%s\047 AND class=\047%s\047;", (index($0,"\"vindicated\":1")?"1":"0"), q(t), q(jf($0,"class")))
      }
    }
    END {
      for (i=1; i<=nv; i++) print v[i]
      if (dropped)
        printf "kit: %d finding event(s) carried no class and were not indexed\n", dropped > "/dev/stderr"
    }'
fi

# ---- 3b. external ingest adapters --------------------------------------------
# Same position in the pipeline as the built-ins: emit SQL, before any derivation runs. An
# adapter that fails aborts the build rather than producing a thinner index, because a
# missing task reads as a finished backlog rather than as an error.
for _spec in "$SRC_TASKS" "$SRC_EVENTS"; do
  adapter_path "$_spec" >/dev/null || continue
  run_adapter "$_spec" emit || { ADAPTER_FAILED=1; break; }
  _fp=$(run_adapter "$_spec" fingerprint 2>/dev/null || true)
  [ -n "$_fp" ] && printf "INSERT OR REPLACE INTO meta VALUES('fingerprint:%s','%s');\n" \
    "$(printf '%s' "$_spec" | sed "s/'/''/g")" "$(printf '%s' "$_fp" | sed "s/'/''/g")"
done
for _spec in $(kit_cfg_all "$PROFILE" ingest.extra); do
  [ -n "$_spec" ] || continue
  run_adapter "$_spec" emit || { ADAPTER_FAILED=1; break; }
done

# ---- 4. derive current state; text sources always win over stale columns -----
cat <<'DERIVE'
-- Order matters: a task may exist only in commits, with no task file. Its row must
-- exist before any derivation runs, or its state and tier are silently lost.
INSERT OR IGNORE INTO node
  SELECT DISTINCT task_id,'task',NULL,task_id FROM event WHERE task_id IS NOT NULL AND task_id<>'';
INSERT OR IGNORE INTO task(id) SELECT id FROM node WHERE type='task';

-- git records what tier was actually used; frontmatter only declares an intent.
UPDATE task SET tier = COALESCE((
  SELECT e.payload FROM event e
   WHERE e.task_id = task.id AND e.kind = 'tiered'
   ORDER BY e.at DESC, e.seq DESC LIMIT 1), tier);

UPDATE task SET state = COALESCE((
  SELECT e.kind FROM event e
   WHERE e.task_id = task.id
     AND e.kind IN ('started','progress','blocked','unblocked','done','abandoned')
   ORDER BY e.at DESC, e.seq DESC LIMIT 1), state, 'open');

-- finding.tier must be resolved AFTER task tiers are derived, or escape-rate-by-tier
-- silently reports every finding as untiered.
UPDATE finding SET tier = (SELECT t.tier FROM task t WHERE t.id = finding.task_id)
  WHERE tier IS NULL OR tier = '';

UPDATE task SET owner = (
  SELECT e.actor FROM event e
   WHERE e.task_id = task.id AND e.actor IS NOT NULL AND e.actor <> ''
     AND e.kind IN ('started','progress','blocked')
   ORDER BY e.at DESC, e.seq DESC LIMIT 1)
  WHERE state NOT IN ('done','abandoned');

UPDATE task SET closed_at = (
  SELECT MAX(e.at) FROM event e WHERE e.task_id = task.id AND e.kind IN ('done','abandoned'))
  WHERE state IN ('done','abandoned');

-- Attribute spend to a task. The hook that fires when an agent finishes does not know which
-- task it was serving, so the link is inferred: the next task-status transition at or after
-- the spend. Work is committed with a trailer when it completes, so the transition that
-- follows a burn of tokens is normally the task those tokens were spent on.
--
-- It is a heuristic and it fails in the obvious ways -- two tasks in flight at once, a
-- session that ends without a commit. That is why unattributed spend is REPORTED rather than
-- dropped: a cost table missing its expensive rows reads as cheap work, not as measurement
-- that did not happen.
UPDATE spend SET task_id = (
  SELECT e.task_id FROM event e
   WHERE e.task_id IS NOT NULL AND e.task_id <> ''
     AND e.kind IN ('started','progress','blocked','unblocked','done','abandoned')
     AND e.at >= spend.at
   ORDER BY e.at, e.seq LIMIT 1)
 WHERE task_id IS NULL OR task_id = '';
DERIVE

# Raise the floor from files the task has actually touched. This is the second of the two
# sources: it catches a task whose declared paths were wrong or absent, but only once work
# has begun -- which is why the declared-paths floor above exists as well.
#
# GLOB, not LIKE: SQLite GLOB treats * as matching any character including /, so `src/**`
# and `src/*` behave alike and agree with the awk conversion above. MAX() is scalar here and
# COALESCE to '' makes it a floor, since '' sorts below 'T0'. Floors only ever raise.
printf '%s' "$TIER_RULES" | tr '\036' '\n' | while IFS="$(printf '\t')" read -r _g _t; do
  [ -n "$_g" ] && [ -n "$_t" ] || continue
  _g=$(printf '%s' "$_g" | sed "s/'/''/g")
  _t=$(printf '%s' "$_t" | sed "s/'/''/g")
  printf "UPDATE task SET tier_floor = MAX(COALESCE(tier_floor,''),'%s') WHERE id IN (SELECT src FROM edge WHERE rel='touches' AND dst GLOB 'f:%s');\n" "$_t" "$_g"
done

echo "COMMIT;"
} > "$SQL"

if [ "$ADAPTER_FAILED" != 0 ]; then
  kit_warn "an ingest adapter failed; the existing index was left unchanged."
  kit_warn "Derived status is therefore stale, not wrong — rerun once the source is reachable."
  build_failed
fi

# An empty task file is a draft, not a defect: `kit-task.sh` writes a skeleton and a human
# fills it in, and a file caught between those two is legitimate. Named rather than counted,
# because a file that will never index while it stays empty is worth knowing about.
if [ -n "$TASKS_EMPTY" ]; then
  kit_warn "task file(s) with no content, not indexed:$TASKS_EMPTY"
fi

# Did the task pass read every task file it was given? Checked here, before the existing index
# is touched, for the same reason the adapter check is: a truncated backlog reads as a shorter
# backlog, never as an error. awk is no help on its own -- it exits 0 after skipping an
# argument it could not read, and non-zero on a fatal only AFTER emitting the tasks it had
# already parsed. Comparing the files it READ against the files it was HANDED catches both,
# and catches whatever the next edit to that pipeline breaks.
if [ "$HAVE_TASKS" = 1 ]; then
  TASKS_SEEN=0; [ -s "$KIT_SEEN" ] && TASKS_SEEN=$(grep -c . "$KIT_SEEN")
  if [ "${TASKS_SEEN:-0}" != "$TASKS_EXPECTED" ]; then
    # Named, not counted. "read 39 of 40" on a real backlog is not actionable.
    MISSING=$(for f in "$@"; do grep -qxF "$f" "$KIT_SEEN" 2>/dev/null || printf ' %s' "${f#$ROOT/}"; done)
    kit_warn "task ingest read $TASKS_SEEN of $TASKS_EXPECTED task file(s); not read:$MISSING"
    INGEST_FAILED=1
  fi
fi
if [ "$INGEST_FAILED" != 0 ]; then
  # Unconditional. Tying the message to the count made it depend on which awk you have: one
  # that treats an unreadable argument as fatal skips END and leaves the count empty, one that
  # warns and continues does not -- and on the second, this exited 1 saying nothing at all.
  kit_warn "the task ingest did not complete; the index at ${DB#$ROOT/} was NOT rebuilt."
  kit_warn "Derived status is stale, not wrong. Fix the cause above and rerun."
  build_failed
fi

# Built beside the index and moved into place, never written over it. The comment at the top
# of the assembly says the whole build is prepared before the existing index is touched --
# which was true of the ASSEMBLY and not of the execution: `rm -f "$DB"` first, then a
# statement fails mid-stream, and what is left is a plausible index with an empty tier column.
# Its mtime is then newer than every source, so the next --if-stale run declares it fresh and
# says nothing. One announcement, then silence, over a backlog with no tiers.
#
# A rename is atomic on both filesystems this runs on, so a failed build now leaves the
# previous index exactly as it was, with its previous mtime -- which is what makes the next
# run notice the sources are newer and try again, loudly, instead of trusting a corpse.
NEW="$DB.new"
trap 'rm -f "$SQL" "$KIT_REFUSED" "$KIT_SEEN" "$NEW"' EXIT
rm -f "$NEW"
sqlite3 "$NEW" < "$(dirname "$0")/schema.sql" ||
  { kit_warn "could not create the index schema; ${DB#$ROOT/} was left unchanged."; build_failed; }
sqlite3 "$NEW" < "$SQL" ||
  { kit_warn "index build failed; ${DB#$ROOT/} was left unchanged and is now stale."
    kit_warn "Nothing was half-written — fix the cause above and rerun."; build_failed; }
rm -f "$FAILED_MARK"
mv -f "$NEW" "$DB" ||
  { kit_warn "could not replace ${DB#$ROOT/}; it was left unchanged."; build_failed; }

# Recovering these commits keeps derived status correct, but doing it quietly would hide a
# merge flow that mangles trailers -- and the next thing that reads them (a CI gate, another
# tool, git itself) will not recover them. Say it once per rebuild, with the fix.
REC=$(sqlite3 "$DB" "SELECT value FROM meta WHERE key='commits_trailers_recovered';" 2>/dev/null | tr -d '\r')
case "${REC:-0}" in ''|0) ;; *)
  kit_warn "$REC commit(s) carry trailers git will not parse — recovered by full-message scan."
  kit_warn "Git reads trailers only from the LAST paragraph; a squash-merge that appends"
  kit_warn "Co-authored-by: strands them mid-message. Keep the kit's trailers last." ;;
esac
echo "${DB#$ROOT/}"
