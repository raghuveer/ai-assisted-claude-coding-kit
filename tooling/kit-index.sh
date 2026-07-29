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

DB="$ROOT/$STATE_DIR/index.db"

# --if-stale: skip the rebuild when nothing it derives from has changed. task-context runs
# this at the start of every session, and a full reindex there is pure latency on a backlog
# that has not moved. The inputs are exactly the three text sources plus the profile, so
# "none of them is newer than the index" is a sound reason to keep the current one.
if [ "${1:-}" = "--if-stale" ] && [ -f "$DB" ]; then
  HEADF=$(cd "$ROOT" && git rev-parse --git-path HEAD 2>/dev/null)
  case "$HEADF" in /*|?:*) ;; *) HEADF="$ROOT/$HEADF" ;; esac
  if [ -z "$(find "$ROOT/$TASKS_DIR" "$ROOT/$STATE_DIR/events.ndjson" "$PROFILE" "$HEADF" \
                  -newer "$DB" 2>/dev/null | head -1)" ]; then
    printf '%s\n' "${DB#$ROOT/}"
    exit 0
  fi
fi
SQL=$(mktemp); trap 'rm -f "$SQL"' EXIT
mkdir -p "$ROOT/$STATE_DIR"
rm -f "$DB"
sqlite3 "$DB" < "$(dirname "$0")/schema.sql"

{ echo "BEGIN;"

# ---- 1. tasks: frontmatter is authoritative for identity ----------------------
# One awk over every task file, rather than one awk per key plus one sed per quoted value
# -- roughly twenty processes per task before. A bare process spawn costs ~0.5s on Windows,
# so a six-task backlog took ~50s to reindex, and task-context reindexes at the start of
# every session. Identical SQL, identical precedence (first occurrence of a key wins).
HAVE_TASKS=0
if [ -d "$ROOT/$TASKS_DIR" ]; then
  for f in "$ROOT/$TASKS_DIR"/*.md; do
    if [ -e "$f" ]; then HAVE_TASKS=1; break; fi
  done
fi
if [ "$HAVE_TASKS" = 1 ]; then
  KIT_PREFIX="$ROOT/" awk '
    function q(s){ gsub(/\x27/,"\x27\x27",s); return s }
    function emit(   id, ti, st, bb, parts, nd, j) {
      id = v["id"]
      if (id == "") { printf "kit: no id in frontmatter, skipped: %s\n", rel > "/dev/stderr"; return }
      ti = (v["title"] != "" ? v["title"] : id)
      st = (v["state"] != "" ? v["state"] : "open")
      printf "INSERT OR REPLACE INTO node VALUES(\x27%s\x27,\x27task\x27,\x27%s\x27,\x27%s\x27);\n", q(id), q(rel), q(ti)
      printf "INSERT OR REPLACE INTO task(id,epic,state,tier,lang,blocked_by) VALUES(\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", q(id), q(v["epic"]), q(st), q(v["tier"]), q(v["lang"]), q(v["blocked_by"])
      # blocked_by is a comma/space separated list of task ids. Frontmatter is where a
      # human declares dependency; edges are how the planner consumes it.
      bb = v["blocked_by"]; gsub(/,/, " ", bb)
      nd = split(bb, parts, /[ \t]+/)
      for (j = 1; j <= nd; j++) {
        if (parts[j] == "") continue
        printf "INSERT OR IGNORE INTO node VALUES(\x27%s\x27,\x27task\x27,NULL,\x27%s\x27);\n", q(parts[j]), q(parts[j])
        printf "INSERT OR IGNORE INTO edge VALUES(\x27%s\x27,\x27%s\x27,\x27depends_on\x27);\n", q(id), q(parts[j])
      }
    }
    # ENVIRON, not -v: awk applies escape processing to -v assignments.
    BEGIN { prefix = ENVIRON["KIT_PREFIX"] }
    FNR==1 {
      if (pending) emit()             # flush the previous file; rel is still its path
      delete v; fm = 0; pending = 1
      rel = FILENAME
      if (index(rel, prefix) == 1) rel = substr(rel, length(prefix) + 1)
    }
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
  ' "$ROOT/$TASKS_DIR"/*.md
fi

# ---- 2. git: trailers are the state transitions, diffs are the touches edges --
# %(trailers:...,valueonly) landed in git 2.32. On anything older the format expands to
# empty, so every commit indexes as untagged: no state transitions, and escape-rate-by-tier
# -- the headline metric -- has nothing to work from. That degradation is invisible in the
# output (it looks like an idle repo), so it has to be said out loud here.
if [ "$(git --version | awk '{ n=split($3,v,"."); print (v[1]>2 || (v[1]==2 && v[2]>=32)) ? 1 : 0 }')" != 1 ]; then
  kit_warn "git $(git --version | awk '{print $3}') is older than 2.32 — commit trailers"
  kit_warn "cannot be parsed; every commit will index as untagged. Upgrade git."
fi
RANGE=${ADOPT:+$ADOPT..HEAD}
git -C "$ROOT" log --reverse --name-only --no-merges \
    --format=$'\x01%H\x1f%aI\x1f%an\x1f%(trailers:key=Task-Id,valueonly,separator=)\x1f%(trailers:key=Task-Status,valueonly,separator=)\x1f%(trailers:key=Tier,valueonly,separator=)\x1f%(trailers:key=Fixes-Escape-Of,valueonly,separator=)' \
    ${RANGE:+$RANGE} 2>/dev/null |
KIT_SDIR="$STATE_DIR/" KIT_TDIR="$TASKS_DIR/" awk -F'\x1f' '
  # Via ENVIRON, not -v: awk applies escape processing to -v assignments, so any path
  # containing a backslash would arrive mangled and silently match nothing.
  BEGIN { sdir = ENVIRON["KIT_SDIR"]; tdir = ENVIRON["KIT_TDIR"] }
  function q(s){ gsub(/\x27/,"\x27\x27",s); return s }
  /^\x01/ {
    sub(/^\x01/,"",$1); sha=$1; at=$2; who=$3; tid=$4; st=$5; tier=$6; esc=$7
    gsub(/[ \t\r]+$/,"",tid); gsub(/[ \t\r]+$/,"",st); gsub(/[ \t\r]+$/,"",tier); gsub(/[ \t\r]+$/,"",esc)
    total++
    if (tid=="") { untagged++; cur=""; next }
    cur=tid
    if (st!="")   printf "INSERT INTO event(task_id,kind,at,commit_sha,actor) VALUES(\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", q(tid), q(st), q(at), q(sha), q(who)
    if (tier!="") printf "INSERT INTO event(task_id,kind,at,commit_sha,payload) VALUES(\x27%s\x27,\x27tiered\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", q(tid), q(at), q(sha), q(tier)
    if (esc!="") {
      printf "INSERT INTO event(task_id,kind,at,commit_sha) VALUES(\x27%s\x27,\x27escaped\x27,\x27%s\x27,\x27%s\x27);\n", q(esc), q(at), q(sha)
      printf "INSERT OR IGNORE INTO edge VALUES(\x27%s\x27,\x27%s\x27,\x27regressed\x27);\n", q(tid), q(esc)
    }
    next
  }
  NF && cur!="" {
    p=$0
    # The kit'"'"'s own state is not project code. Every task edits its task file and appends to
    # the event log, so keeping these edges would make every pair of tasks look coupled --
    # inflating blast radius and collapsing semantic clustering into one blob.
    if (sdir != "" && index(p, sdir) == 1) next
    if (tdir != "" && index(p, tdir) == 1) next
    printf "INSERT OR IGNORE INTO node VALUES(\x27f:%s\x27,\x27file\x27,\x27%s\x27,NULL);\n", q(p), q(p)
    printf "INSERT OR IGNORE INTO edge VALUES(\x27%s\x27,\x27f:%s\x27,\x27touches\x27);\n", q(cur), q(p)
  }
  END {
    printf "INSERT OR REPLACE INTO meta VALUES(\x27commits_total\x27,\x27%d\x27);\n", total
    printf "INSERT OR REPLACE INTO meta VALUES(\x27commits_untagged\x27,\x27%d\x27);\n", untagged
  }'

# ---- 3. events.ndjson: transitions that never had a commit -------------------
EV="$ROOT/$STATE_DIR/events.ndjson"
if [ -f "$EV" ]; then
  # Sorted by timestamp, then by the whole line, so the index is a function of the SET of
  # events rather than of their order in the file. .gitattributes marks events.ndjson
  # merge=union, so two developers' appends interleave arbitrarily on merge; without this
  # their rebuilds disagree and "delete index.db, rebuild, byte-identical" is false across
  # a team. (sort joins tr/cut/sed/wc, already relied on elsewhere in tooling/.)
  awk 'NF {
         a=""
         if (match($0, /"at"[ ]*:[ ]*"[^"]*"/)) {
           a=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[ ]*"/,"",a); sub(/"$/,"",a) }
         printf "%s\t%s\n", a, $0
       }' "$EV" | LC_ALL=C sort | cut -f2- |
  awk '
    function jf(s,k,  r){ r=""
      if (match(s, "\"" k "\"[ ]*:[ ]*\"[^\"]*\"")) {
        r=substr(s,RSTART,RLENGTH); sub(/^[^:]*:[ ]*"/,"",r); sub(/"$/,"",r) }
      return r }
    function q(s){ gsub(/\x27/,"\x27\x27",s); return s }
    NF {
      t=jf($0,"task"); k=jf($0,"kind"); a=jf($0,"at")
      if (k=="") next
      printf "INSERT INTO event(task_id,kind,at,payload) VALUES(\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", q(t), q(k), q(a), q($0)
      if (k=="finding") {
        cls = jf($0,"class")
        # A classless finding cannot be grouped, counted or promoted -- it only adds a
        # phantom row to the query the accelerators are seeded from. The event itself is
        # still recorded above, so nothing is lost; only the unusable row is dropped.
        if (cls == "") { dropped++ }
        else {
          n++
          printf "INSERT OR REPLACE INTO finding(id,task_id,agent,model,tier,lang,domain,class,severity,at) VALUES(\x27%s:%d\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27,NULL,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", q(a), n, q(t), q(jf($0,"agent")), q(jf($0,"model")), q(jf($0,"lang")), q(jf($0,"domain")), q(cls), q(jf($0,"severity")), q(a)
        }
      }
      if (k=="vindication") {
        # Held back to END. A vindication can precede its finding in the file, and after a
        # union merge routinely does; applied inline it updates zero rows, and kit-accel.sh
        # then reads that finding as unrefuted and proposes it -- exactly the laundering
        # kit-vindicate.sh exists to prevent. Sorted input makes last-write-wins correct.
        nv++
        v[nv] = sprintf("UPDATE finding SET vindicated=%s WHERE task_id=\x27%s\x27 AND class=\x27%s\x27;", (index($0,"\"vindicated\":1")?"1":"0"), q(t), q(jf($0,"class")))
      }
    }
    END {
      for (i=1; i<=nv; i++) print v[i]
      if (dropped)
        printf "kit: %d finding event(s) carried no class and were not indexed\n", dropped > "/dev/stderr"
    }'
fi

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
DERIVE
echo "COMMIT;"
} > "$SQL"

sqlite3 "$DB" < "$SQL" || { kit_warn "index build failed; index.db may be incomplete"; exit 1; }
echo "${DB#$ROOT/}"
