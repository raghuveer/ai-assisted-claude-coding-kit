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
# The statement filter is a net, not a security boundary. It catches an adapter that
# accidentally reshapes the database, not one that means to.
#
# WHETHER AN ADAPTER IS TRUSTED IS AN OPEN QUESTION, and this comment used to answer it --
# "an adapter is trusted code named in a committed, reviewed profile". SECURITY.md section 1
# says the opposite, classing ingest adapter output as NOT trusted. Both cannot hold, and the
# disagreement is why nobody looked: the profile naming the executable is a file any agent
# with Write can author, inside the root the guard permits by design. Recorded as
# T-20260816-an-in-root-profile-write-gives-an-agent-; do not re-answer it here in a comment.
run_adapter() {
  _ap=$(adapter_path "$1") || return 1
  if [ ! -x "$_ap" ] && [ ! -f "$_ap" ]; then
    kit_warn "ingest adapter not found: $1"; return 2
  fi
  # ADR 0003, option C: the project chooses WHICH adapter; the kit constrains WHETHER something
  # nobody chose can run. Two refusals, both structural, both provable by a test.
  #
  # 1. REPO-RELATIVE ONLY. An absolute path -- or one climbing out with `..` -- names code the
  #    repository does not contain, so no review of this project can ever have seen it.
  # 2. TRACKED BY GIT. An adapter file that is not committed has been reviewed by nobody. This is
  #    the part that answers "does the kit mandate the documented choice": a declaration an agent
  #    invented mid-session names an untracked file and does not execute.
  #
  # WHAT THIS DOES NOT DO, stated here because the comment it replaced overclaimed in the other
  # direction: an agent holding `Bash` can `git add` and commit, and kit-guard.sh does not match
  # Bash. So this binds a CONFUSED agent, a profile copied between projects, and an ad-hoc path --
  # not a determined one. SECURITY.md section 4 keeps the sandbox gap; ADR 0003 keeps the bound.
  case "$1" in
    /*|?:*|*..*)
      kit_warn "ingest adapter '$1' is not repo-relative; refusing to run it"
      kit_warn "  ADR 0003: an adapter must live in this repository, where a review can see it"
      return 2 ;;
  esac
  if ! git -C "$ROOT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    kit_warn "ingest adapter '$1' is not tracked by git; refusing to run it"
    kit_warn "  an untracked adapter is in no diff and no review. \`git add\` it, or correct the"
    kit_warn "  ingest.* value in the profile. (ADR 0003)"
    return 2
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
  if [ "$2" = emit ]; then
    # INDENT EVERY EMITTED LINE BY ONE SPACE. sqlite3 reads a line whose FIRST character is `.`
    # as a dot-command -- .shell, .system, .import, .load, .output -- and this output reaches the
    # CLI through a file redirect (`sqlite3 "$NEW" < "$SQL"` further down), not through a driver.
    # An adapter emitting `.shell touch x` therefore ran a shell. Verified 2026-08-16.
    #
    # One leading space closes the whole channel without naming a single command: sqlite3 stops
    # treating the line as a dot-command and parses it as SQL, which fails loudly and non-zero,
    # and the `||` on that redirect already treats a non-zero sqlite3 as a failed build. Leading
    # whitespace is insignificant to SQL, so nothing legitimate is altered.
    #
    # This is deliberately NOT another entry in the filter above -- that filter is a blacklist
    # and could not see any of those five dot-commands. A blacklist that gained `.shell` would
    # be the same defect with a longer regex. `fingerprint` output is not SQL and is not
    # indented, or the comparison it feeds would never match.
    printf '%s\n' "$_out" | sed 's/^/ /'
  else
    printf '%s\n' "$_out"
  fi
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
  # The plan is a source now (ADR 0004), so a replan must make the index stale like any other
  # edit. Guarded on existence: `find` over a missing path is an error on every platform, and
  # this list is evaluated on a repository that may never have planned anything.
  [ -d "$ROOT/$STATE_DIR/plans" ] && WATCH="$WATCH $ROOT/$STATE_DIR/plans"
  # shellcheck disable=SC2086
  [ -n "$(find $WATCH -newer "$DB" 2>/dev/null | head -1)" ] && STALE=1
  # GIT IS COMPARED BY RESOLVED COMMIT, NOT BY THE MTIME OF ANY FILE.
  #
  # This watched `.git/HEAD`, which on a branch holds the text `ref: refs/heads/main` and is
  # NOT REWRITTEN BY A COMMIT -- the commit moves `refs/heads/<branch>`. Measured on this
  # repository: `.git/HEAD` was seventeen minutes older than the tip it pointed at, so
  # `--if-stale` reported FRESH with history moved past the last build, and every git-derived
  # input -- `touches`, and through it `tier_floor`, blast radius and co-change -- was
  # invisible to the check. It failed in the direction that fails open.
  #
  # Watching `refs/heads/<branch>` instead fixes the demonstration and keeps the class: that
  # file is absent on a DETACHED HEAD, wrong mid-REBASE, shared or absent in a WORKTREE where
  # `.git` may itself be a file, and after `git gc` the ref lives in `packed-refs` with no
  # file to stat at all. Every file-based proxy has one of those holes.
  #
  # The resolved SHA is what the derivation actually depends on, and `rev-parse` answers
  # correctly in all four states. One spawn, against a value recorded in `meta` by the last
  # build -- the same shape the ingest adapters already use for their fingerprints below.
  if [ "$STALE" = 0 ] && [ "$SRC_COMMITS" = git ]; then
    _head=$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || printf 'none')
    _was=$(sqlite3 "$DB" "SELECT value FROM meta WHERE key='head_commit';" 2>/dev/null | tr -d '\r')
    # An index built before this key existed carries no row. That is UNKNOWN, not equal: fall
    # stale once so the value gets recorded, rather than trusting a build whose commit nobody
    # wrote down. Reading a missing row as a match is how this defect stayed invisible.
    [ -n "$_was" ] && [ "$_head" = "$_was" ] || STALE=1
  fi
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
KIT_PLAN_REFUSED=$(mktemp); export KIT_PLAN_REFUSED
trap 'rm -f "$SQL" "$KIT_REFUSED" "$KIT_PLAN_REFUSED" "$KIT_SEEN"' EXIT
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
  KIT_PREFIX="$ROOT/" KIT_RULES="$TIER_RULES" KIT_SEEN="$KIT_SEEN" KIT_VIA="$(kit_via_vocab)" awk '
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
    # Returns "" for a glob it cannot translate faithfully, and the caller SKIPS such a rule.
    # `?` used to be mapped to a regex `.` here -- one byte, where SQLite GLOB reads one
    # character -- and the only thing preventing that divergence was a guard at the single
    # caller, seventy lines away. Add a second caller, or edit that guard, and the
    # disagreement came back silently. The guarantee now lives in the function that provides it.
    function globre(g,   r) {
      if (index(g, "?") || index(g, "[") || index(g, "]")) return ""
      r = g
      gsub(/[\\.^$+(){}|]/, "\\\\&", r)
      gsub(/\052+/, ".*", r)
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
        re = globre(g)
        if (re == "") continue          # untranslatable; refused upstream, skipped here too
        for (i = 1; i <= n; i++) {
          if (parts2[i] == "") continue
          if (parts2[i] ~ re && t > best) best = t
        }
      }
      return best
    }
    function emit(   id, ti, st, bb, parts, nd, j, fl) {
      id = v["id"]
      if (id == "") { printf "kit: no id in frontmatter, skipped: %s\n", rel > "/dev/stderr"; return }
      ti = (v["title"] != "" ? v["title"] : id)
      st = (v["state"] != "" ? v["state"] : "created")
      printf "INSERT OR REPLACE INTO node VALUES(\047%s\047,\047task\047,\047%s\047,\047%s\047);\n", q(id), q(rel), q(ti)
      fl = floorof(v["paths"])
      # `via` from frontmatter, and anything outside the vocabulary becomes `unknown` rather
      # than being stored. Unknown is the honest default: on a brownfield back-fill nobody
      # remembers how each item was done, and a wrong label is worse than an absent one
      # because only the wrong one gets counted into a comparison.
      vv = viaok(v["via"])
      printf "INSERT OR REPLACE INTO task(id,epic,state,tier,lang,blocked_by,tier_floor,via) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,%s,\047%s\047);\n", q(id), q(v["epic"]), q(st), q(v["tier"]), q(v["lang"]), q(v["blocked_by"]), (fl == "" ? "NULL" : "\047" q(fl) "\047"), q(vv)
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
    # EXACT membership, not a substring of the padded list. `index(VIAOK, " " x " ")` matched
    # any contiguous RUN of vocabulary words -- `kit agent`, `manual unknown` -- and stored
    # them verbatim, inventing populations the closed vocabulary exists to prevent.
    function viaok(x,   i, n, w) {
      n = split(ENVIRON["KIT_VIA"], w, /[ 	]+/)
      for (i = 1; i <= n; i++) if (x == w[i]) return x
      return "unknown"
    }
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
# other reader of the index. Measured, not assumed.
#
# The flag suppresses that escaping for bytes above 0x7F AND NOTHING ELSE. git quotes
# independently for a double quote, a backslash or any control byte, all of which are legal
# filenames on a POSIX checkout, and no flag turns that off. Measured: a path containing a
# backslash still arrives quoted with the flag on. Those are dropped and counted where the
# paths are read, because a floor that cannot be applied has to be announced.
TZ=UTC0 git -C "$ROOT" -c core.quotepath=false log --reverse --name-only --no-merges \
    --date=format-local:%Y-%m-%dT%H:%M:%SZ \
    --format=$'\001%H\037%ad\037%an\037%(trailers:key=Task-Id,valueonly,separator=%x1e)\037%(trailers:key=Task-Status,valueonly,separator=%x1e)\037%(trailers:key=Tier,valueonly,separator=%x1e)\037%(trailers:key=Via,valueonly,separator=%x1e)\037%(trailers:key=Fixes-Escape-Of,valueonly,separator=%x1e)\002%B\003' \
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
KIT_VIA="$(kit_via_vocab)" \
awk -F$'\037' '
  # Via ENVIRON, not -v: awk applies escape processing to -v assignments, so any path
  # containing a backslash would arrive mangled and silently match nothing.
  BEGIN {
    sdir = ENVIRON["KIT_SDIR"]; tdir = ENVIRON["KIT_TDIR"]
    exempt_re = ENVIRON["KIT_EXEMPT"]
  }
  # EXACT membership, not a substring of the padded list. `index(VIAOK, " " x " ")` matched
  # any contiguous RUN of vocabulary words -- `kit agent`, `manual unknown` -- and stored
  # them verbatim, inventing populations the closed vocabulary exists to prevent.
  function viaok(x,   i, n, w) {
    n = split(ENVIRON["KIT_VIA"], w, /[ 	]+/)
    for (i = 1; i <= n; i++) if (x == w[i]) return x
    return "unknown"
  }
  # MEMBERSHIP, which is a different question from "what should this default to". viaok maps an
  # invalid value onto `unknown`, which is right for frontmatter and wrong for a trailer: the
  # guard below used `viaok(via) != "unknown"` and so discarded the literal word `unknown` too,
  # because `unknown` IS in the vocabulary. The effect was that a human could never demote a
  # task whose frontmatter claimed `via: kit` -- the one value the design says nobody should
  # take on trust -- and movement into the measured population was one-way. Found in the T3
  # review of 2026-08-10.
  function viaknown(x,   i, n, w) {
    n = split(ENVIRON["KIT_VIA"], w, /[ 	]+/)
    for (i = 1; i <= n; i++) if (x == w[i]) return 1
    return 0
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
    tid=first(tid); st=first(st); tier=first(tier); via=first(via); esc=first(esc)
    if (tid == "") {
      tid = scan("Task-Id")
      if (tid != "") {
        recovered++
        if (st   == "") st   = scan("Task-Status")
        if (tier == "") tier = scan("Tier")
        if (via  == "") via  = scan("Via")
        if (esc  == "") esc  = scan("Fixes-Escape-Of")
      }
    }
    if (tid=="") { if (!isexempt) untagged++; cur=""; return }
    cur=tid
    if (st!="")   printf "INSERT INTO event(task_id,kind,at,commit_sha,actor) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047);\n", q(tid), q(st), q(at), q(sha), q(who)
    if (tier!="") printf "INSERT INTO event(task_id,kind,at,commit_sha,payload) VALUES(\047%s\047,\047tiered\047,\047%s\047,\047%s\047,\047%s\047);\n", q(tid), q(at), q(sha), q(tier)
    # HOW the work was done, recorded the way the tier is: an event carrying the trailer, so
    # git holds what actually happened while frontmatter only declares an intent. A value
    # outside the vocabulary is DROPPED rather than stored -- the commit-msg hook already
    # rejected it, so one arriving here came from a commit that skipped the hook, which is the
    # last input that should be believed.
    #
    # `unknown` is IN the vocabulary and is recorded like any other value. It has to be: it is
    # the only way a human can retract an earlier `Via: kit`, and the design forbids using
    # `manual` for that -- "one says nobody recorded it, the other is a claim about what
    # happened". Testing membership rather than `viaok(...) != "unknown"` is what makes the
    # retraction possible; the old test silently discarded exactly the value it needed.
    if (via != "" && viaknown(via))
      printf "INSERT INTO event(task_id,kind,at,commit_sha,payload) VALUES(\047%s\047,\047via\047,\047%s\047,\047%s\047,\047%s\047);\n", q(tid), q(at), q(sha), q(via)
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
    sub(/^\001/,"",$1); sha=$1; at=$2; who=$3; tid=$4; st=$5; tier=$6; via=$7
    p = index($8, "\002")          # $8 is Fixes-Escape-Of, then \002, then body line 1
    esc  = p ? substr($8, 1, p-1) : $8
    body = p ? substr($8, p+1)    : ""
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
    # A path git returned QUOTED is a path this reader cannot use. core.quotepath=false stops
    # the escaping of bytes above 0x7F and nothing else: git quotes independently for `"`,
    # backslash and any control byte, and those are legal filenames on a POSIX checkout.
    # Recording `"src/i\\j.go"` as a node was measured to match no glob and no tier.rule, so
    # the touched-files floor silently did not apply -- the under-tiering direction, on a name
    # the author chooses. Dropped and COUNTED rather than recorded wrong or dropped quietly:
    # the rule in this repository is that a floor which cannot be applied must be announced.
    if (substr(p, 1, 1) == "\042") { quoted++; next }
    if (cur != "") {
      printf "INSERT OR IGNORE INTO node VALUES(\047f:%s\047,\047file\047,\047%s\047,NULL);\n", q(p), q(p)
      printf "INSERT OR IGNORE INTO edge VALUES(\047%s\047,\047f:%s\047,\047touches\047);\n", q(cur), q(p)
    }
  }
  END {
    printf "INSERT OR REPLACE INTO meta VALUES(\047paths_unusable\047,\047%d\047);\n", quoted + 0
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
# core.quotepath again, same reason and the same limit: a mangled name splits one file into two
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
    # Same rule as the touches pass: a path git returned quoted is one this reader cannot use,
    # and a mangled name here splits one file into two co-change nodes. Counted over there,
    # not here -- one counter for one cause.
    if (substr(p, 1, 1) == "\042") next
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
         # The SORT KEY is normalised to fixed width; the payload is untouched. Timestamps are
         # compared as strings, and `.` (0x2E) sorts before `Z` (0x5A), so a whole-second
         # `...:00Z` landed AFTER every sub-second `...:00.123456Z` in the same second -- the
         # reverse of the truth, since a whole second denotes its start. It matters wherever
         # last-write-wins decides an outcome, which for finding-fixed marks is every time.
         sk = a
         if (a != "" && index(a, ".") == 0) sub(/Z$/, ".000000Z", sk)
         printf "%s\t%020d\t%s\n", sk, t, $0
       }' "$EV" | LC_ALL=C sort | cut -f3- |
  LC_ALL=C awk '
    # LC_ALL=C is not decoration. fnv1a() walks bytes, and in a UTF-8 locale gawk counts
    # CHARACTERS while mawk and BSD awk count bytes -- so a finding whose summary contains a
    # non-ASCII byte would hash differently on Linux and macOS, and its id would change when
    # the platform did. Sixteen lines of this repo`s own log contain such bytes.
    function jf(s,k,  r){ r=""
      if (match(s, "\"" k "\"[ ]*:[ ]*\"[^\"]*\"")) {
        r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*"/,"",r); sub(/"$/,"",r) }
      return r }
    # FNV-1a, 32-bit, over the raw event line. The multiply is split into 16-bit halves
    # because awk arithmetic is IEEE double: h * 16777619 needs 55 bits of mantissa and
    # silently loses precision above 2^53, which would make the hash machine-dependent.
    # Verified against the published vectors -- "a"=e40c292c, "hello"=4f9f2cab,
    # "foobar"=bf9cf968 -- and conformance re-checks them, so a rewrite that drifts is red.
    function fnv1a(s,   i,h,c,lo,hi){
      h = 2166136261
      for (i = 1; i <= length(s); i++) {
        c = ORD[substr(s,i,1)]; if (c == "") c = 255
        h = xor32(h, c)
        lo = (h % 65536) * 16777619
        hi = (int(h / 65536) * 16777619) % 65536
        h = (lo + hi * 65536) % 4294967296
      }
      return h }
    function xor32(a,b,   i,r,p,x,y){
      r = 0; p = 1
      for (i = 0; i < 32; i++) {
        x = a % 2; y = b % 2
        if (x != y) r = r + p
        a = int(a/2); b = int(b/2); p = p * 2 }
      return r }
    BEGIN { for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i }
    # jf reads a quoted string; token counts are bare numbers and need their own reader.
    function jn(s,k,  r){ r=0
      if (match(s, "\"" k "\"[ ]*:[ ]*-?[0-9]+")) {
        r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*/,"",r) }
      return r+0 }
    function q(s){ gsub(/\047/,"\047\047",s); return s }
    NF {
      t=jf($0,"task"); k=jf($0,"kind"); a=jf($0,"at")
      if (k=="") next
      # `actor` is carried through when the event has one. Events derived from commits get it
      # from the author; events from this log had no way to say who acted, which is what made
      # "the operator records the mark, the agent proposes it" an instruction with nothing
      # behind it -- `Via:` is auditable and a fix mark was not.
      printf "INSERT INTO event(task_id,kind,at,actor,payload) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047);\n", q(t), q(k), q(a), q(jf($0,"actor")), q($0)
      if (k=="finding") {
        cls = jf($0,"class")
        # A classless finding cannot be grouped, counted or promoted -- it only adds a
        # phantom row to the query the accelerators are seeded from. The event itself is
        # still recorded above, so nothing is lost; only the unusable row is dropped.
        if (cls == "") { dropped++ }
        else {
          n++
          # IDENTITY IS CONTENT-DERIVED, NOT POSITIONAL. It used to be `at:n`, n counting
          # indexed findings in sorted order -- so a single event merged in from a branch with
          # an earlier timestamp renumbered EVERY finding after it. Measured on this repository:
          # one inserted line shifted all 219 ids by one. A fix-mark keyed on such an id does
          # not merely fail to resolve, it silently reattaches to the NEIGHBOURING finding,
          # which is worse than no mark at all. `at` stays in front so the id sorts and reads
          # chronologically; the hash makes it a function of the line, and the line is
          # append-only, so the id is stable for as long as the event is.
          # Printed as two 16-bit halves, NOT as sprintf("%08x", h). An FNV-1a value above
          # 2^31 -- more than half of them -- goes through a signed int in mawk (ubuntu-latest)
          # and BSD awk (macos-latest), so `%x` does not survive it there while gawk prints it
          # correctly. That is how this first reached CI: green on the machine it was written
          # on, red on both platforms, with every id different. Each half is below 65536, which
          # every awk renders alike, and the digits are unchanged from the gawk output.
          _h = fnv1a($0)
          fid = a ":" sprintf("%04x%04x", int(_h / 65536), _h % 65536)
          # Two events can land on one id two ways, and they are not the same event.
          #
          # A DUPLICATE LINE is byte-identical -- this repository has one, two pre-contract
          # findings on the same task, class, severity and second, recorded before `summary`
          # existed to tell them apart. Collapsing them would silently drop a row, so the
          # second takes an occurrence suffix. It is the one positional component left, and it
          # is ordered only among lines that are identical anyway: appending an unrelated event
          # cannot move it, which is the property the old counter lacked.
          #
          # A TRUE COLLISION is two DIFFERENT lines hashing alike. The suffix keeps both rows,
          # so nothing is lost, but their ids then depend on each other and it is said out loud.
          base = fid
          dupn[base]++
          if (dupn[base] > 1) {
            # A TRUE COLLISION MAKES EVERY ID AT THIS BASE AMBIGUOUS, and marks on them are
            # refused in END rather than applied to whichever line happened to sort first.
            # The occurrence suffix is the one positional component left, so appending a
            # DIFFERENT line that hashes alike can take the first slot and push the original to
            # `:2` -- and the fix mark on that original, keyed on the unsuffixed id, would land
            # on the newcomer. Inheriting a mark is worse than losing one: it asserts that a
            # specific defect was fixed. Fail closed on the ambiguity instead.
            if (fpay[base] != $0) { coll++; collbase[base] = 1 }
            fid = base ":" dupn[base]
          } else fpay[base] = $0
          fseen[fid] = 1
          # summary/file/line are absent on every finding recorded before the structured
          # contract existed, and jf() returns "" for a key that is not there -- so old rows
          # keep working and simply carry no summary. line_no is written via jn(), which
          # returns 0 for a missing key; 0 is stored as NULL rather than as line zero, because
          # a line number nobody supplied must not read as a location somebody did.
          ln = jn($0,"line")
          printf "INSERT OR REPLACE INTO finding(id,task_id,agent,model,tier,lang,domain,pattern,class,severity,at,summary,file_path,line_no) VALUES(\047%s\047,\047%s\047,\047%s\047,\047%s\047,NULL,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,\047%s\047,%s);\n", fid, q(t), q(jf($0,"agent")), q(jf($0,"model")), q(jf($0,"lang")), q(jf($0,"domain")), q(jf($0,"pattern")), q(cls), q(jf($0,"severity")), q(a), q(jf($0,"summary")), q(jf($0,"file")), (ln>0 ? ln : "NULL")
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
      # Whether a finding was ADDRESSED -- a different question from whether it was real, and
      # the one nothing could answer before. Held to END for the reason vindication is: after a
      # union merge a mark can sort before the finding it names, and an inline UPDATE would
      # match zero rows and say nothing. Sorted input makes last-write-wins correct, so a
      # reopen recorded after a fix wins, and a fix recorded after a reopen wins.
      if (k=="finding-fixed") {
        nf++
        fref[nf] = jf($0,"finding")
        if (index($0,"\"fixed\":0") > 0)
          f[nf] = sprintf("UPDATE finding SET fixed_at=NULL, fixed_commit=NULL, fixed_note=NULL WHERE id=\047%s\047;", q(jf($0,"finding")))
        else
          f[nf] = sprintf("UPDATE finding SET fixed_at=\047%s\047, fixed_commit=\047%s\047, fixed_note=\047%s\047 WHERE id=\047%s\047;", q(a), q(jf($0,"commit")), q(jf($0,"note")), q(jf($0,"finding")))
      }
      # Whether a finding can be JUDGED AT ALL -- the third fact, and deliberately routed through
      # the SAME deferred array as a fix mark rather than applied inline. That is not tidiness:
      # it inherits the orphan naming and the collision refusal for free, so a mark naming an id
      # no finding has is REPORTED instead of running as an UPDATE that matches nothing and
      # exits 0. A disposition that silently fails to apply would leave the gate reading clean
      # for a reason nobody recorded, which is the exact failure this column exists to prevent.
      if (k=="finding-unassessable") {
        nf++
        fref[nf] = jf($0,"finding")
        f[nf] = sprintf("UPDATE finding SET unassessable_at=\047%s\047, unassessable_reason=\047%s\047 WHERE id=\047%s\047;", q(a), q(jf($0,"reason")), q(jf($0,"finding")))
      }
      # Whether the SUBJECT of a finding still stands -- the fourth fact. Same deferred array as the
      # other two marks, and for the same reason rather than for symmetry: it inherits the orphan
      # naming and the collision refusal, so a mark naming an id no finding has is REPORTED rather
      # than run as an UPDATE that matches nothing and exits 0. A disposition that silently fails
      # to apply leaves the gate reading clean for a reason nobody recorded.
      if (k=="finding-superseded") {
        nf++
        fref[nf] = jf($0,"finding")
        f[nf] = sprintf("UPDATE finding SET superseded_at=\047%s\047, superseded_by=\047%s\047 WHERE id=\047%s\047;", q(a), q(jf($0,"by")), q(jf($0,"finding")))
      }
    }
    END {
      for (i=1; i<=nv; i++) print v[i]
      # Flag every row at a collided base, so the refusal is visible to kit-resolve.sh at the
      # moment a mark is TYPED. Without it the tool says "recorded" and the indexer discards the
      # mark on every rebuild -- a success message for something that never takes effect.
      for (b in collbase) {
        printf "UPDATE finding SET id_ambiguous=1 WHERE id=\047%s\047 OR (id > \047%s:\047 AND id < \047%s;\047);\n", b, b, b
      }
      for (i=1; i<=nf; i++) {
        # A mark naming an id no finding has is the failure this whole change exists to make
        # impossible, so it is NAMED rather than run as an UPDATE that matches nothing and
        # exits 0. Silence here would restore exactly the state being fixed: a gate reading
        # clean because the evidence never landed.
        # Prefix-matched with substr, not a regex: `fref[i]` is untrusted text from the log and
        # this repository has an open task about exactly that shape -- a value interpolated
        # into a pattern, where one metacharacter changes what is matched.
        amb = 0
        for (b in collbase)
          if (fref[i] == b || substr(fref[i], 1, length(b) + 1) == b ":") amb = 1
        if (!(fref[i] in fseen)) orphan++
        else if (amb) ambigm++
        else print f[i]
      }
      # RECORDED, not just warned. These went to stderr only, and stderr from an indexer that
      # runs inside kit-status.sh, a hook, or CI is seen by nobody -- so STATUS.generated.md,
      # the one place anyone reads, could not show that marks had failed to apply. A measurement
      # failure that is announced where no one is looking is an unannounced measurement failure.
      printf "INSERT OR REPLACE INTO meta VALUES(\047finding_orphan_marks\047,\047%d\047);\n", orphan+0
      printf "INSERT OR REPLACE INTO meta VALUES(\047finding_id_collisions\047,\047%d\047);\n", coll+0
      printf "INSERT OR REPLACE INTO meta VALUES(\047finding_ambiguous_marks\047,\047%d\047);\n", ambigm+0
      if (ambigm)
        printf "kit: %d finding-fixed event(s) name an id made ambiguous by a collision and were NOT applied\n", ambigm > "/dev/stderr"
      if (dropped)
        printf "kit: %d finding event(s) carried no class and were not indexed\n", dropped > "/dev/stderr"
      if (orphan)
        printf "kit: %d finding-fixed event(s) name no known finding and were NOT applied\n", orphan > "/dev/stderr"
      if (coll)
        printf "kit: %d finding id collision(s) -- two distinct events hashed alike; marks on them are ambiguous\n", coll > "/dev/stderr"
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

# THE COMMIT THIS BUILD SAW. Read back by `--if-stale`, which compares resolved SHAs rather
# than the mtime of any file -- the block up there records why every file-based proxy
# (`.git/HEAD`, `refs/heads/<branch>`, `packed-refs`) has a hole. Written here, in the same
# stream and for the same reason as the adapter fingerprints above: it states what this index
# was derived FROM, so the next run can tell whether that has moved.
#
# `none` is recorded for a repository with no commits yet, so the comparison has a value to be
# equal to. Recording nothing would leave the key absent, which `--if-stale` treats as unknown
# and therefore stale -- correct once, but it would rebuild on every run forever.
if [ "$SRC_COMMITS" = git ]; then
  printf "INSERT OR REPLACE INTO meta VALUES('head_commit','%s');\n" \
    "$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || printf 'none')"
fi
for _spec in $(kit_cfg_all "$PROFILE" ingest.extra); do
  [ -n "$_spec" ] || continue
  run_adapter "$_spec" emit || { ADAPTER_FAILED=1; break; }
done

# ---- 3c. the plan: text is the source, this is the derivation ----------------
# ADR 0004. `goal` and `plan_item` are written by kit-plan.sh and nothing here could rebuild
# them, so this script used to DROP them on every run -- the build starts from a fresh schema.
# skills/task-context step 1 is `kit-index.sh --if-stale` and its step 4 reads `plan_item`, so
# the skill's first step deleted what its fourth step was looking for, on any session where a
# task file had changed. Measured: 77 plan rows and 1 goal to zero, with the packs left on disk
# looking current. docs/HANDOFF.md 4.6 promised the plan survives a crash; it did not survive
# the next session.
#
# Read here, with the other text sources and before derivation, because that is what the plan
# now is: an input. A malformed file is REFUSED and named rather than half-loaded -- a plan
# missing rows would reorder work silently, which is worse than no plan.
PLANS_DIR="$ROOT/$STATE_DIR/plans"
if [ -d "$PLANS_DIR" ]; then
  # TWO FILES MAY NOT CLAIM ONE GOAL. Each emits DELETE-then-INSERT for its `#goal`, so with a
  # duplicate the shell's glob order silently decides which ordering survives — an ordering no
  # planner computed and nobody chose. Every file claiming a contested goal is refused, not just
  # the later one: "last one wins" is a filename sort, not a decision.
  _dupes=$(for _p in "$PLANS_DIR"/*.tsv; do
             [ -f "$_p" ] && awk -F'\t' '$1=="#goal"{sub(/\r$/,"",$2); print $2; exit}' "$_p"
           done | sort | uniq -d)
  for _d in $_dupes; do
    printf '%s\tgoal %s is declared by more than one plan file\n' "$PLANS_DIR" "$_d" >> "$KIT_PLAN_REFUSED"
    kit_warn "goal '$_d' is declared by more than one plan file; none of them is loaded"
    kit_warn "  Glob order would decide which ordering survives. Remove or rename the duplicate."
  done
  for _pf in "$PLANS_DIR"/*.tsv; do
    [ -f "$_pf" ] || continue
    if [ -n "$_dupes" ]; then
      _g=$(awk -F'\t' '$1=="#goal"{sub(/\r$/,"",$2); print $2; exit}' "$_pf")
      printf '%s\n' "$_dupes" | grep -qxF "${_g:-}" && continue
    fi
    awk -F'\t' -v file="${_pf#$ROOT/}" '
      function q(s){ gsub(/\047/,"\047\047",s); return s }
      function refuse(why) { reason = why; bad = 1 }
      # A plan file is UNTRUSTED INPUT — SECURITY.md §1 classes anything anyone with commit
      # access may author that way, and this one is parsed into SQL at the start of every
      # session by task-context step 1. Arity alone was the whole of the old validation, and a
      # T3 security review showed what the other five columns then permit. Each check below
      # exists for a demonstrated failure, not for tidiness:
      #
      #   goal charset — `goal_id` becomes `.project/packs/<goal_id>/…`, which the skill tells
      #     an agent to load verbatim. Measured: a row carrying `../../docs` resolves outside
      #     the packs directory entirely.
      #   goal matches header — the DELETE is keyed on the header and the INSERT was keyed on
      #     column 1, so a file could plant rows for a goal no DELETE covers and no staleness
      #     check keys on: an ordering no planner ever computed, fresh forever.
      #   numerics — `+0` coerces rather than validates. Measured both directions: `abc` in
      #     `layer` silently became 0 and collapsed the topology that is kit-plan.sh rule 1,
      #     and a score of `1e999` emitted `+inf`, which sqlite3 refuses — taking the entire
      #     index build down and leaving a .failed mark that every later run re-trips.
      function badnum(v) { return (v !~ /^-?[0-9]+(\.[0-9]+)?$/) }
      # Same per-line strip, and for the same reason, as the task-file reader above. This
      # repository pins the plan to LF in .gitattributes, but kit-init.sh writes an ADOPTED
      # repo its own .gitattributes and the pin has to travel there too -- and a checkout that
      # predates it would carry a CR into the goal id and the digest, silently marking every
      # plan stale against itself. Cheaper to be robust here than to rely on every checkout.
      { sub(/\r$/, "") }
      $1=="#goal"        { goal=$2;     next }
      $1=="#created"     { created=$2;  next }
      $1=="#withheld"    { withheld=$2; next }
      # The plan travels between machines and kit versions through git, so these two are
      # CHECKED rather than skipped as comments. A file written by a kit that reordered
      # plan_item would otherwise be read positionally by an older one -- rank landing silently
      # in layer, with no symptom until the ordering is wrong. Absent means version 1, so plans
      # written before this header stay loadable.
      $1=="#version"     { version=$2;  next }
      $1=="#columns"     { cols_seen=1
                           if (NF!=7 || $2!="goal_id" || $3!="task_id" || $4!="layer" || \
                               $5!="rank" || $6!="score" || $7!="cluster") cols_bad=1
                           next }
      /^#/               { next }
      /^[ \t]*$/         { next }
      {
        if (bad) next
        # Six fields exactly. A short row is a truncated write or a bad merge, and guessing
        # which column is missing is how a plan quietly loses its layering.
        if (NF != 6)                  { refuse("a row does not have exactly 6 fields"); next }
        if ($1 != goal)               { refuse("a row names goal \047" $1 "\047, not the \043goal header"); next }
        if (badnum($3) || badnum($4)) { refuse("layer/rank are not plain numbers"); next }
        if (badnum($5))               { refuse("score is not a plain number"); next }
        if (badnum($6))               { refuse("cluster is not a plain number"); next }
        rows++
        g[rows]=$1; t[rows]=$2; l[rows]=$3+0; r[rows]=$4+0; s[rows]=$5; c[rows]=$6+0
      }
      END {
        # Refusals are RECORDED, not only printed. The identical argument is made at line 229
        # about tier.rule and was not carried here: kit-status.sh runs the indexer with stderr
        # discarded, so a refusal that exists only on a terminal nobody was watching is not a
        # refusal anyone hears — and the artifact then reported the refused plan as an ORPHANED
        # PACK, which is the wrong cause and the wrong remedy. Conflicted plan files are a
        # DESIGNED outcome here, because .gitattributes deliberately declines merge=union, so
        # this is the expected steady state after a merge rather than an edge case.
        if (goal == "")            refuse("no \043goal header")
        else if (goal ~ /[^A-Za-z0-9._-]/)
          refuse("\043goal is not a safe path segment: \047" goal "\047")
        else if (version != "" && version != "1")
          refuse("\043version " version " is newer than this kit reads (1)")
        else if (cols_seen && cols_bad)
          refuse("\043columns does not match this kit\047s column order")
        if (bad) {
          printf "%s\t%s\n", file, reason > ENVIRON["KIT_PLAN_REFUSED"]
          printf "kit: %s was NOT loaded — %s\n", file, reason > "/dev/stderr"
          exit 0
        }
        printf "INSERT OR REPLACE INTO goal(id,title,created_at) VALUES(\047%s\047,\047%s\047,\047%s\047);\n", \
               q(goal), q(goal), q(created)
        # Reads as a no-op and is kept deliberately: the build starts from a fresh schema, so on
        # the normal path this deletes nothing. It is the guard for a goal that appears twice
        # WITHIN one file — the duplicate-across-files case is refused before either loads, but
        # nothing stops a hand-edited file repeating its own goal, and without this the rows
        # would accumulate instead of replacing.
        printf "DELETE FROM plan_item WHERE goal_id=\047%s\047;\n", q(goal)
        for (i=1; i<=rows; i++)
          printf "INSERT OR REPLACE INTO plan_item VALUES(\047%s\047,\047%s\047,%d,%d,%s,%d);\n", \
                 q(g[i]), q(t[i]), l[i], r[i], s[i], c[i]
        if (withheld != "")
          printf "INSERT OR REPLACE INTO meta VALUES(\047plan_withheld:%s\047,\047%s\047);\n", q(goal), q(withheld)
      }' "$_pf" || {
        # awk's status was discarded here, and the task pass twenty lines up carries an entire
        # KIT_SEEN counter precisely because that knowledge is expensive: an unreadable file
        # (permissions, a Windows lock during `git checkout`) would have produced an empty plan
        # and a SUCCESSFUL build — the measured 77-rows-to-zero symptom this change exists to
        # abolish, restored through a different door and reported by nothing.
        printf '%s\tthe plan reader did not complete\n' "${_pf#$ROOT/}" >> "$KIT_PLAN_REFUSED"
        kit_warn "could not read ${_pf#$ROOT/}; the plan was NOT loaded"
        INGEST_FAILED=1
      }
  done
fi
# Same treatment, and the same reason, as tier_rules_refused above.
PLAN_REFUSED_N=0; [ -s "$KIT_PLAN_REFUSED" ] && PLAN_REFUSED_N=$(grep -c . "$KIT_PLAN_REFUSED")
if [ "$PLAN_REFUSED_N" -gt 0 ]; then
  PLAN_REFUSED_T=$(tr '\n' ';' < "$KIT_PLAN_REFUSED" | sed "s/;$//; s/'/''/g")
  printf "INSERT OR REPLACE INTO meta VALUES('plan_refused','%s');\n" "$PLAN_REFUSED_N"
  printf "INSERT OR REPLACE INTO meta VALUES('plan_refused_text','%s');\n" "$PLAN_REFUSED_T"
fi

# ---- 3d. project the state vocabulary into SQL ------------------------------
# Emitted HERE, in the shell-expanded part of the block, because everything from `cat <<'DERIVE'`
# down is a QUOTED heredoc where `$(...)` is literal text. The derivation below joins this table
# instead of repeating `'done','abandoned'`, which it did six times in this file alone.
# kit-lib.sh owns the values; this is their projection. See docs/adr/0008.
for _st in $(kit_state_vocab); do
  _cl=0; for _c in $(kit_state_closed);   do [ "$_st" = "$_c" ] && _cl=1; done
  _ac=0; for _a in $(kit_state_activity); do [ "$_st" = "$_a" ] && _ac=1; done
  _me=0; for _m in $(kit_state_measured); do [ "$_st" = "$_m" ] && _me=1; done
  printf "INSERT OR REPLACE INTO state_class VALUES('%s',%d,%d,%d);\n" "$_st" "$_cl" "$_ac" "$_me"
  # Identity row FIRST, so a canonical value always resolves through the alias table and every
  # reader can join it unconditionally rather than remembering to COALESCE.
  printf "INSERT OR REPLACE INTO state_alias VALUES('%s','%s');\n" "$_st" "$_st"
done
for _pair in $(kit_state_legacy); do
  printf "INSERT OR REPLACE INTO state_alias VALUES('%s','%s');\n" "${_pair%%:*}" "${_pair##*:}"
done

# ---- 4. derive current state; text sources always win over stale columns -----
cat <<'DERIVE'
-- A `Task-Id` in a trailer is a REFERENCE, not a task, and the difference is a file. Inventing
-- a task row for one was how a single-character typo in a pushed commit became a permanent open
-- task with no title and no epic -- in the Open list, in the backlog count, and in the
-- escape-rate denominator of a tier nobody ever assigned it. The controls that exist all act
-- earlier (kit-trailers.sh warns at commit time, pre-push blocks before sharing) and none of
-- them help for history already pushed, which is the only case that matters here.
--
-- So the node is created and the task row is not. The node keeps the graph whole for the edges
-- that point at the id -- `depends_on` from a blocked_by, `regressed` from a Fixes-Escape-Of --
-- and it is what kit-status.sh reads to name these ids at all. What used to be an
-- invented task is now named by kit-status.sh with the commit that introduced it, on the rule
-- this kit already applies to unattributed spend, refused tier.rules and unusable paths: what
-- could not be resolved is reported rather than silently discarded. Silently INVENTED is worse
-- than either, because it reads as work.
--
-- WHERE THE RULE ACTUALLY LIVES, since this is the third thing a reader looks at and the first
-- two were misleading: `task` rows come from section 2 and from nowhere else -- one INSERT per
-- parsed FILE. There is no statement here that admits a task, so a file is the only way in. An
-- earlier version of this change added a guarded INSERT here, `path IS NOT NULL`, which read
-- like the gate implementing all of it and was dead code: section 2 has already inserted a row
-- for every file, so it could never find one to add. Measured, then deleted -- indexing with and
-- without it produced identical task rows. What stops a phantom is the ABSENCE below, not a
-- guard, and an absence needs saying out loud or the next reader restores the invention.
--
-- An id that later gains a file therefore needs no reconciliation step: the file starts
-- producing the row, and nothing here has to notice. A task filed after the commit that
-- referenced it is a normal sequence, not an error.
INSERT OR IGNORE INTO node
  SELECT DISTINCT task_id,'task',NULL,task_id FROM event WHERE task_id IS NOT NULL AND task_id<>'';

-- git records what tier was actually used; frontmatter only declares an intent.
-- LAST WINS, ordered by `seq` and not by `at`, at every one of these derivations.
--
-- `at` is `%ad`, the AUTHOR date, which is whatever `GIT_AUTHOR_DATE` said -- so ordering by it
-- let a future-dated commit pin a value permanently: no later commit could ever be "after" it,
-- and a `Via: kit` so dated could never be retracted. Found against the via derivation in the
-- review of 2026-08-12 and swept to all four, because it is one shape in four places and
-- fixing only the instance that was reported is the mistake this repository keeps making
-- (docs/LESSONS.md S4).
--
-- `seq` is AUTOINCREMENT and the log is walked with `--reverse`, oldest commit first, so it is
-- the order the history actually happened in and nothing in a commit message can reorder it.
UPDATE task SET tier = COALESCE((
  SELECT e.payload FROM event e
   WHERE e.task_id = task.id AND e.kind = 'tiered'
   ORDER BY e.seq DESC LIMIT 1), tier);


-- NORMALISE THE AUTHORED VALUE FIRST. A task file may carry a legacy spelling forever -- 115 of
-- 130 say `open` today -- so the written value is resolved through state_alias before anything
-- reads it. A value in NO alias row is left exactly as written rather than guessed at: an
-- unrecognised state is a typo to report, and quietly rewriting it to something plausible is how
-- a typo becomes permanent.
UPDATE task SET state = (SELECT a.canonical FROM state_alias a WHERE a.written = task.state)
  WHERE EXISTS (SELECT 1 FROM state_alias a WHERE a.written = task.state);

-- Then the last transition wins, resolved through the same table. The join to state_alias is
-- what restricts this to state events -- `finding`, `spend` and the rest are not alias rows --
-- and it is also what keeps the 127 commits already carrying `started`/`progress`/`done`
-- readable, which is why they never had to be rewritten.
UPDATE task SET state = COALESCE((
  SELECT a.canonical FROM event e JOIN state_alias a ON a.written = e.kind
   WHERE e.task_id = task.id
   ORDER BY e.seq DESC LIMIT 1), state, 'created');

-- A finding harvested from a reviewer carries no task: the hook that harvests it fires when
-- the reviewer stops, and nothing in this kit tracks a current task. Bound the same way spend
-- is -- to the next task-status transition at or after it -- because it is the same question
-- with the same available evidence, and one attribution rule is one rule to get right.
--
-- The CASE sits INSIDE the selected row for the reason spend's does: as a WHERE clause it does
-- not stop the search, it skips to the next REAL transition however unrelated, and files the
-- finding against a task that had nothing to do with it. Measured on spend, fixed there, and
-- the identical shape would be identically wrong here.
-- state_alias, NOT state_class, and the difference is a regression this already caused.
-- state_class holds the CANONICAL seven; state_alias holds every spelling that has ever been
-- written, legacy included. Attribution binds a finding to the next task-status transition, and
-- those transitions are real events carrying whatever word was current when they were recorded --
-- 87 of them say `progress`. Matching against state_class silently attributed nothing, and two
-- conformance steps went red. Anything that reads an EVENT KIND must join state_alias.
UPDATE finding SET task_id = (
  SELECT CASE WHEN EXISTS (SELECT 1 FROM task t WHERE t.id = e.task_id) THEN e.task_id END
    FROM event e
   WHERE e.task_id IS NOT NULL AND e.task_id <> ''
     AND e.kind IN (SELECT written FROM state_alias)
     AND e.at >= finding.at
   ORDER BY e.at, e.seq LIMIT 1)
 WHERE task_id IS NULL OR task_id = '';

-- finding.tier must be resolved AFTER task tiers are derived, or escape-rate-by-tier
-- silently reports every finding as untiered.
UPDATE finding SET tier = (SELECT t.tier FROM task t WHERE t.id = finding.task_id)
  WHERE tier IS NULL OR tier = '';

UPDATE task SET owner = (
  SELECT e.actor FROM event e
   WHERE e.task_id = task.id AND e.actor IS NOT NULL AND e.actor <> ''
     AND e.kind IN (SELECT a.written FROM state_alias a JOIN state_class c ON c.state=a.canonical WHERE c.is_activity = 1)
   ORDER BY e.seq DESC LIMIT 1)
  WHERE state NOT IN (SELECT state FROM state_class WHERE is_closed = 1);

UPDATE task SET closed_at = (
  SELECT MAX(e.at) FROM event e WHERE e.task_id = task.id
                                  AND e.kind IN (SELECT a.written FROM state_alias a JOIN state_class c ON c.state=a.canonical WHERE c.is_closed = 1))
  WHERE state IN (SELECT state FROM state_class WHERE is_closed = 1);

-- Attribute spend to a task. The hook that fires when an agent finishes does not know which
-- task it was serving, so the link is inferred: the next task-status transition at or after
-- the spend. Work is committed with a trailer when it completes, so the transition that
-- follows a burn of tokens is normally the task those tokens were spent on.
--
-- It is a heuristic and it fails in the obvious ways -- two tasks in flight at once, a
-- session that ends without a commit. That is why unattributed spend is REPORTED rather than
-- dropped: a cost table missing its expensive rows reads as cheap work, not as measurement
-- that did not happen.
-- The existence test is INSIDE the selected row, not in the WHERE clause, and the difference
-- is the whole finding. Written as `AND EXISTS (...)` it does not stop the search -- it makes
-- LIMIT 1 skip the phantom's transition and bind to the next REAL one instead, however far in
-- the future and however unrelated. Measured: spend, then a T-ghost transition, then a later
-- unrelated T-real transition, and the cost landed on T-real, at T-real's tier, with zero
-- unattributed and no warning anywhere. That is not the third category this guard was added to
-- prevent; it is a fourth and worse one -- attributed to the WRONG thing and reading as right,
-- where the previous behaviour at least kept it on the id the trailer actually named.
--
-- So the nearest transition is chosen FIRST, on time alone, exactly as the heuristic describes;
-- only then is it required to be a real task. A CASE with no ELSE yields NULL, so a phantom
-- nearest neighbour leaves the row unattributed and the warning below says so. The heuristic
-- may still be wrong about WHICH task -- it is a heuristic -- but it can no longer be wrong
-- about which task it CHOSE.
UPDATE spend SET task_id = (
  SELECT CASE WHEN EXISTS (SELECT 1 FROM task t WHERE t.id = e.task_id) THEN e.task_id END
    FROM event e
   WHERE e.task_id IS NOT NULL AND e.task_id <> ''
     AND e.kind IN (SELECT written FROM state_alias)
     AND e.at >= spend.at
   ORDER BY e.at, e.seq LIMIT 1)
 WHERE task_id IS NULL OR task_id = '';
DERIVE

# Emitted here rather than inside the quoted heredoc, because the vocabulary has to be
# expanded from its ONE definition rather than retyped as a SQL literal.
#
# The filter is on the DERIVATION, which is the only place every route converges: a `via`
# event can arrive from a trailer, from events.ndjson -- where the generic reader stores the
# WHOLE JSON LINE as payload -- or from an ingest adapter emitting SQL by design. Guarding
# only the writers left `kit-event.sh <task> via` able to write a JSON blob into the column
# and silently drop a task carrying a recorded escape out of the headline metric. Measured,
# not theorised. Fail closed at the join, and every writer is covered at once.
VIA_SQL=$(for _w in $(kit_via_vocab); do printf "'%s'," "$_w"; done | sed 's/,$//')
printf "UPDATE task SET via = COALESCE((SELECT e.payload FROM event e WHERE e.task_id = task.id AND e.kind = 'via' AND e.payload IN (%s) ORDER BY e.seq DESC LIMIT 1), via);
" "$VIA_SQL"

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
# AN EMPTY state_class FAILS OPEN AND SILENTLY. Every partition is a join against this table, so
# with no rows `state NOT IN (SELECT ... WHERE is_closed=1)` matches everything: the whole backlog
# reads as open, closed_at is never set, and the numbers look plausible. That is the shape this
# repository keeps paying for -- a control whose failure produces a confident wrong answer rather
# than an error -- so it is checked rather than assumed. See docs/adr/0008.
_sc=$(sqlite3 "$NEW" "SELECT COUNT(*) FROM state_class;" 2>/dev/null | tr -d '\r')
if [ "${_sc:-0}" -lt 1 ]; then
  kit_warn "state_class is empty, so every state would classify as open; refusing this build"
  kit_warn "  it is projected from kit_state_vocab in kit-lib.sh — check that it is readable."
  build_failed
fi
rm -f "$FAILED_MARK"
mv -f "$NEW" "$DB" ||
  { kit_warn "could not replace ${DB#$ROOT/}; it was left unchanged."; build_failed; }

STALE_PLANS=0
if [ -d "$PLANS_DIR" ]; then
  PLAN_DIGEST_NOW=$(kit_plan_digest "$DB")
  for _pf in "$PLANS_DIR"/*.tsv; do
    [ -f "$_pf" ] || continue
    # A REFUSED PLAN IS NOT A STALE ONE, and reporting it as either fresh or stale is worse than
    # saying nothing: section 3c loaded ZERO rows from it, so "the ordering is current" and "the
    # ordering has moved" are both false. This block used to re-read the same file with only the
    # two headers it needed and no row validation at all, so a file 3c had rejected still got a
    # digest comparison — and on a match it actively DELETED the stale marker.
    #
    # It defers to the refusal list rather than duplicating 3c's checks. Duplicating them is how
    # the two readers drift, which is the defect ADR 0004 removed by deleting the second writer;
    # a second validator would reintroduce it on the read side.
    if [ -s "$KIT_PLAN_REFUSED" ] && grep -qF "${_pf#$ROOT/}" "$KIT_PLAN_REFUSED" 2>/dev/null; then
      continue
    fi
    _pg=$(awk -F'\t' '$1=="#goal"{print $2; exit}' "$_pf" | tr -d '\r')
    _pd=$(awk -F'\t' '$1=="#tasks_digest"{print $2; exit}' "$_pf" | tr -d '\r')
    [ -n "$_pg" ] || continue
    _pgq=$(printf '%s' "$_pg" | sed "s/'/''/g")

    # IS THIS PLAN ACTUALLY GOING TO SURVIVE A CLONE? ADR 0004's whole claim is that it will,
    # and that rests on the file being in git — which nothing checked. A `.gitignore` line
    # covering `.project/` returns the plan to exactly the machine-local state this task exists
    # to abolish, through configuration rather than code, and silently.
    #
    # ADR 0003 built a tracked-file check for ingest adapters and this deliberately does NOT
    # copy its shape, because the reasoning does not transfer. An untracked adapter is refused
    # outright: it is executable code that no review has seen, and refusing costs nothing. A
    # plan file is untracked for a perfectly ordinary reason — it was just written and not yet
    # committed — so refusing it would break the tool on its first use. Porting the refusal
    # would be the half-ported control the review chain flagged elsewhere in this change.
    #
    # So the two states are separated and reported differently:
    #   IGNORED  — cannot ever be committed without a config change. The plan is machine-local
    #              and the guarantee is false. Loud.
    #   UNTRACKED but not ignored — normal immediately after a replan. A reminder, not an alarm.
    if git -C "$ROOT" check-ignore -q -- "$_pf" 2>/dev/null; then
      sqlite3 "$DB" "INSERT OR REPLACE INTO meta VALUES('plan_ignored:$_pgq','1');" ||
        kit_warn "could not record that the plan for '$_pg' is gitignored"
      kit_warn "the plan for '$_pg' is covered by .gitignore, so it will NOT survive a clone"
      kit_warn "  That is the machine-local state ADR 0004 exists to prevent. Un-ignore it."
    else
      sqlite3 "$DB" "DELETE FROM meta WHERE key='plan_ignored:$_pgq';" 2>/dev/null
      git -C "$ROOT" ls-files --error-unmatch -- "$_pf" >/dev/null 2>&1 ||
        kit_warn "the plan for '$_pg' is not committed yet; \`git add\` it or it stays local to this machine"
      # THE LF PIN, CHECKED HERE RATHER THAN WRITTEN BY kit-init.sh. kit-init runs once, at
      # adoption, so a repository that adopted the kit before ADR 0004 never receives the pin
      # and nothing would ever say so. The indexer runs every session, which makes it the only
      # place the gap is observable. Checked, not written: silently editing a project's
      # .gitattributes from the indexer would be a write nobody asked for.
      if [ -f "$ROOT/.gitattributes" ] &&
         ! grep -qxF '.project/plans/*.tsv text eol=lf' "$ROOT/.gitattributes" 2>/dev/null; then
        kit_warn "the plan is committed but .gitattributes does not pin it to LF"
        kit_warn "  A CRLF checkout carries a CR into the goal id and the digest, which marks"
        kit_warn "  every plan stale against itself. Add: .project/plans/*.tsv text eol=lf"
      fi
    fi
    # No digest at all is an OLDER plan file, not a fresh one. Treated as stale and said so:
    # assuming it matches is the laundering this check exists to prevent.
    # BOTH WRITES ARE CHECKED, and this is not belt-and-braces. kit-plan.sh:316-320 already
    # argues the identical case for the withheld count — discarding the status "would let the
    # paragraph above be false in the one case it is about" — and that reasoning was ported here
    # as a shape without its substance. ADR 0004 rests on a carried-forward plan being able to
    # say it is stale; if this INSERT fails on a locked database (a live possibility: it runs
    # AFTER the atomic swap, against a database kit-status.sh or a second indexer may hold), the
    # plan loads with no marker and is served as current. That is the branch where it cannot say.
    #
    # An uncomputable digest is treated as STALE, never as fresh. `kit_plan_digest` returns
    # empty when its query fails; before, a failed query cksummed an empty stream to the same
    # value an empty backlog produces, so two uncomputable digests compared EQUAL and took the
    # branch that DELETES the warning.
    if [ -z "$PLAN_DIGEST_NOW" ] || [ -z "$_pd" ] || [ "$_pd" != "$PLAN_DIGEST_NOW" ]; then
      STALE_PLANS=$((STALE_PLANS + 1))
      sqlite3 "$DB" "INSERT OR REPLACE INTO meta VALUES('plan_stale:$_pgq','1');" ||
        kit_warn "could not record that the plan for '$_pg' is stale; it will be served as current"
    else
      sqlite3 "$DB" "DELETE FROM meta WHERE key='plan_stale:$_pgq';" ||
        kit_warn "could not clear the stale mark for '$_pg'; it may be reported stale when it is not"
    fi
  done
fi
if [ "$STALE_PLANS" -gt 0 ]; then
  kit_warn "$STALE_PLANS plan(s) were computed from a different backlog — re-run kit-plan.sh"
  kit_warn "  The ordering still loads; it may name tasks that have closed or changed tier."
fi

# A fix mark names a commit. Nothing checked that the commit is still in this history, so a
# branch that was rebased away, or a SHA that never existed, left the finding marked fixed
# forever with its evidence pointing at nothing. Checked here rather than in SQL because only
# git can answer it, and only for rows that carry a SHA -- a handful, not a walk of the log.
#
# WHAT THIS DOES NOT DETECT, said plainly: a REVERT. A reverted fix leaves its commit in
# history and adds another undoing it, so the mark still resolves and still reads as addressed.
# Deciding whether a later commit undoes an earlier one is not a lookup, and pretending this
# covers it would be the false-rationale this kit exists to refuse.
# Counts MARKS, not distinct commits, because that is what the report says it counts -- three
# marks citing one vanished SHA under-reported as one. And read with `while read`, not
# `for _c in $(...)`: an unquoted command substitution word-splits and globs, and a value stored
# before `--commit` was validated is arbitrary text. That is the interpolation shape LESSONS §4
# says to sweep for rather than fix one instance of, and it was introduced here while fixing
# something else.
# A plan survives a rebuild now (ADR 0004), so for the first time it can outlive the backlog
# it was computed from: tasks close, split, or change tier underneath it. That possibility is
# the COST of persisting it, and a carried-forward plan that could not say it was stale would
# be a worse defect than the one this fixed -- a plan that visibly vanished, replaced by one
# that is confidently wrong.
#
# Compared here rather than in the SQL stream because the digest is computed from the finished
# index, and by the one function kit-plan.sh also calls. Two copies of that query would report
# every plan permanently stale or permanently fresh, and both fail silently.
MISSING=0
while IFS= read -r _c; do
  [ -n "$_c" ] || continue
  git -C "$ROOT" cat-file -e "${_c}^{commit}" 2>/dev/null || MISSING=$((MISSING + 1))
done <<EOF
$(sqlite3 "$DB" "SELECT fixed_commit FROM finding
                  WHERE fixed_commit IS NOT NULL AND fixed_commit <> '';" 2>/dev/null | tr -d '\r')
EOF
sqlite3 "$DB" "INSERT OR REPLACE INTO meta VALUES('finding_fix_commit_missing','$MISSING');" 2>/dev/null
if [ "$MISSING" -gt 0 ]; then
  kit_warn "$MISSING fix mark(s) name a commit that is not in this history."
  kit_warn "  The finding still reads as addressed and its evidence resolves to nothing."
fi

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
