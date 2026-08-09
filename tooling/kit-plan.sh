#!/usr/bin/env bash
# kit-plan.sh [--goal ID] [--next N] [--show]
#
# Groups tasks by dependency, orders them by completion priority, and persists the
# result. Two rules make this correct rather than merely plausible:
#
#   1. TOPOLOGY BEATS PRIORITY. A high-scoring task blocked by a low-scoring one
#      cannot go first. Priority orders *within* a layer, never across layers.
#   2. THE PLAN IS STATE, NOT CONTEXT. The ordering is computed once and written to
#      the index. A task session reads one row — not the plan, not the graph. This
#      is what stops a multi-task goal from growing an orchestrator window.
#
# Cycles are a data error, not something to order around: they are reported and the
# affected tasks are withheld from the plan rather than silently mis-sequenced.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 0; }
kit_active "$ROOT" || exit 0
PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")
DB="$ROOT/$STATE_DIR/index.db"
[ -f "$DB" ] || { kit_warn "no index; run kit-index.sh first"; exit 1; }

GOAL="default"; NEXT=5; SHOW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --goal) GOAL=${2:-default}; shift; shift ;;
    --next) NEXT=${2:-5}; shift; shift ;;
    --show) SHOW=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

# Scoring weights. Declared in the profile so priority policy is a project decision,
# not a constant buried in a script.
W_UNBLOCKS=$(kit_cfg "$PROFILE" priority.w_unblocks 3)
W_ESCAPES=$(kit_cfg  "$PROFILE" priority.w_escapes  2)
W_TIER=$(kit_cfg     "$PROFILE" priority.w_tier     1)

# A file touched by many open tasks is a hub -- a central config, a barrel export, main().
# Left in, it links every task to every other and clustering degenerates to one blob. Only
# files below this degree are treated as evidence that two tasks are about the same thing.
HUB_CAP=$(kit_cfg "$PROFILE" cluster.hub_cap 5)
case "$HUB_CAP" in ''|*[!0-9]*) kit_warn "cluster.hub_cap must be a whole number"; exit 2 ;; esac

# --next reaches a LIMIT clause and --goal a WHERE, so both are checked here rather than
# trusted where they are interpolated. The awk-generated SQL already escapes goal via q();
# these two are for the display queries at the bottom, which do not.
case "$NEXT" in ''|*[!0-9]*) kit_warn "--next must be a whole number"; exit 2 ;; esac
GOAL_SQL=$(printf '%s' "$GOAL" | sed "s/'/''/g")

# Temp files via mktemp, honouring TMPDIR, cleaned by trap. A fixed /tmp/name.$$ is
# predictable on a shared machine and leaks both files on any early exit.
SQL=$(mktemp); ERR=$(mktemp); trap 'rm -f "$SQL" "$ERR"' EXIT

# ---- inputs: open tasks, dependency edges, and the two risk signals -------------
# ORDER BY on the task select is not cosmetic: cluster numbers are assigned in the order
# tasks arrive, so without it the same backlog yields different cluster ids per run and
# the frozen context packs below stop being byte-identical.
sqlite3 -separator $'\t' "$DB" "
  SELECT 'N', t.id, COALESCE(t.tier,''),
         (SELECT COUNT(*) FROM edge e
           WHERE e.src=t.id AND e.rel='touches'),
         (SELECT COUNT(*) FROM event ev
           WHERE ev.kind='escaped' AND ev.task_id IN (
             SELECT e2.src FROM edge e2
              WHERE e2.rel='touches' AND e2.dst IN (
                SELECT e3.dst FROM edge e3 WHERE e3.src=t.id AND e3.rel='touches'))),
         COALESCE(t.epic,'')
    FROM task t WHERE t.state NOT IN ('done','abandoned') ORDER BY t.id;
  SELECT 'E', e.src, e.dst FROM edge e
   WHERE e.rel='depends_on'
     AND e.src IN (SELECT id FROM task WHERE state NOT IN ('done','abandoned'))
     AND e.dst IN (SELECT id FROM task WHERE state NOT IN ('done','abandoned'));
  -- A blocker that is DONE stops blocking, and the query above drops that edge on purpose.
  -- A blocker with no task row at all is a different thing entirely and must not leave by the
  -- same door: it is not satisfied, it is unknown. Emitted separately so the planner can
  -- withhold the dependent instead of scheduling it as though nothing were in its way.
  SELECT 'U', e.src, e.dst FROM edge e
   WHERE e.rel='depends_on'
     AND e.src IN (SELECT id FROM task WHERE state NOT IN ('done','abandoned'))
     AND NOT EXISTS (SELECT 1 FROM task t WHERE t.id = e.dst);
  -- Semantic adjacency: two open tasks that touch a file in common are about the same
  -- part of the codebase, whether or not anyone declared a dependency. Hub files are
  -- excluded, or one shared main() would fuse the whole backlog into a single cluster.
  WITH open AS (SELECT id FROM task WHERE state NOT IN ('done','abandoned')),
       tf   AS (SELECT e.src AS t, e.dst AS f FROM edge e JOIN open o ON o.id = e.src
                 WHERE e.rel='touches'),
       leaf AS (SELECT f FROM tf GROUP BY f HAVING COUNT(DISTINCT t) <= $HUB_CAP)
  SELECT 'S', a.t, b.t
    FROM tf a JOIN tf b ON a.f = b.f AND a.t < b.t
    JOIN leaf l ON l.f = a.f
   GROUP BY a.t, b.t ORDER BY a.t, b.t;
" 2>/dev/null | awk -F'\t' -v goal="$GOAL" \
    -v wu="$W_UNBLOCKS" -v we="$W_ESCAPES" -v wt="$W_TIER" '
function q(s){ gsub(/\047/,"\047\047",s); return s }
function find(x){ while (par[x] != x) { par[x] = par[par[x]]; x = par[x] } return x }
function union(a,b,  ra,rb){ ra=find(a); rb=find(b); if (ra!=rb) par[rb]=ra }
# Rank order inside one layer: strongest cluster first, each cluster kept contiguous so
# consecutive sessions share a context pack, then score, then id for determinism.
function before(x, y,   bx, by) {
  bx = cbest[layer[x] SUBSEP cluster[x]]; by = cbest[layer[y] SUBSEP cluster[y]]
  if (bx != by)                   return (bx > by)
  if (cluster[x] != cluster[y])   return (cluster[x] < cluster[y])
  if (score[x] != score[y])       return (score[x] > score[y])
  return (x < y)
}

$1=="N" {
  id=$2; n++; ids[n]=id; par[id]=id
  tier[id]=$3; touch[id]=$4+0; esc[id]=$5+0; epic[id]=$6
  indeg[id]=0
  next
}
$1=="S" {                             # shared non-hub file => same subject matter
  if (($2 in par) && ($3 in par)) union($2, $3)
  next
}
$1=="U" {                             # blocked by an id that has no task file at all
  if ($2 in par) unresdep[$2] = unresdep[$2] " " $3
  next
}
$1=="E" {
  src=$2; dst=$3                      # src depends on dst => dst must complete first
  if (!(src in par) || !(dst in par)) next
  if (seen[src SUBSEP dst]++) next
  indeg[src]++
  adj[dst] = adj[dst] " " src         # completing dst releases src
  # Deliberately NOT unioned into a cluster. A dependency says "after", not "about", and
  # layering already expresses it. Unioning it too made one chain of 40 tasks transitively
  # fuse every epic it passed through: 300 tasks, one cluster, no grouping left.
  next
}
END {
  # ---- clusters: what the tasks are ABOUT, not what blocks what ----------------
  # Two signals of subject matter: a declared epic (the human said so) and a shared
  # non-hub file (the code says so). Dependency is deliberately excluded -- it says
  # "after", not "about", and layering already carries it. The previous rule clustered
  # on dependency alone, which put two reworks of the same module in different clusters
  # whenever nobody had declared a dependency between them.
  for (i=1; i<=n; i++) {
    e = epic[ids[i]]
    if (e == "") continue
    if (e in epicrep) union(ids[i], epicrep[e]); else epicrep[e] = ids[i]
  }
  for (i=1; i<=n; i++) { r=find(ids[i]); if (!(r in cl)) cl[r]=++ncl; cluster[ids[i]]=cl[r] }

  # ---- Kahn: topological layering. Anything left over sits in a cycle. ---------
  head=0; tail=0
  for (i=1; i<=n; i++) if (indeg[ids[i]]==0) { queue[tail++]=ids[i]; layer[ids[i]]=0; placed[ids[i]]=1 }
  done_n=0
  while (head < tail) {
    u=queue[head++]; done_n++
    m=split(adj[u], out, " ")
    for (j=1; j<=m; j++) {
      v=out[j]; if (v=="") continue
      if (layer[v] < layer[u]+1) layer[v]=layer[u]+1   # longest path = true layer
      if (--indeg[v]==0) { queue[tail++]=v; placed[v]=1 }
    }
  }
  if (done_n < n) {
    stuck=""
    for (i=1; i<=n; i++) if (!placed[ids[i]]) stuck = stuck " " ids[i]
    printf "CYCLE%s\n", stuck > "/dev/stderr"
  }

  # ---- withhold what a missing blocker makes unsequenceable ---------------------
  # RULE 1 of this file is that topology beats priority, and an unfiled blocker is the one
  # way that guarantee can be lost silently: the edge exists in the graph, its target has no
  # task row, and a filter that reaches for `task` drops the constraint rather than the task.
  # Measured before this existed -- a task blocked by an unfiled id was planned at layer 0,
  # first, as though nothing were in its way.
  #
  # Withheld rather than reordered, on the same grounds as a cycle: this is a data error, and
  # a plan that sequences around it is confidently wrong. Propagated to dependents, because
  # anything waiting on a task that cannot be scheduled cannot be scheduled either -- and the
  # ROOTS are what gets reported, since naming the whole tail would bury the one file to fix.
  for (i=1; i<=n; i++) if (ids[i] in unresdep) withheld[ids[i]]=1
  changed=1
  while (changed) {
    changed=0
    for (i=1; i<=n; i++) {
      u=ids[i]; if (!(u in withheld)) continue
      m=split(adj[u], out, " ")
      for (j=1; j<=m; j++) {
        v=out[j]
        if (v!="" && !(v in withheld)) { withheld[v]=1; changed=1 }
      }
    }
  }
  nheld=0
  for (i=1; i<=n; i++) {
    id=ids[i]
    if (!(id in withheld)) continue
    placed[id]=0                        # the one gate the emission below already honours
    nheld++
    if (id in unresdep) printf "UNRESOLVED %s%s\n", id, unresdep[id] > "/dev/stderr"
  }
  # The MAGNITUDE, not just the trigger. Measured: 22 open tasks, one mistyped blocked_by, 20
  # tasks behind it -- one task planned, twenty-one gone, and the only thing said about it was
  # a single line naming the root. A plan that lost most of the backlog reads exactly like a
  # backlog that was mostly finished. Three sections of kit-status.sh set the standard this
  # missed: "Tier floors unverified for N of M open task(s)".
  if (nheld > 0) printf "WITHHELDCOUNT %d %d\n", nheld, n > "/dev/stderr"

  # ---- transitive dependents: how much finishing this releases ------------------
  # AFTER withholding, and that ordering is the point: `unblocks` feeds the priority score, and
  # counting descendants that cannot be scheduled inflates the score of a survivor with work
  # that finishing it would not release. Withheld nodes are skipped as roots and never entered.
  for (i=1; i<=n; i++) {
    root=ids[i]
    if (root in withheld) { unblocks[root]=0; continue }
    delete vis; qh=0; qt=0; q2[qt++]=root; cnt=-1
    while (qh<qt) {
      u=q2[qh++]; if (u in vis) continue; vis[u]=1; cnt++
      m=split(adj[u], out, " ")
      for (j=1;j<=m;j++) if (out[j]!="" && !(out[j] in vis) && !(out[j] in withheld)) q2[qt++]=out[j]
    }
    unblocks[root]=cnt
  }

  # ---- score, then rank strictly within layer ---------------------------------
  tierw["T3"]=3; tierw["T2"]=2; tierw["T1"]=1; tierw["T0"]=0
  print "BEGIN;"
  printf "INSERT OR IGNORE INTO goal(id,title,created_at) VALUES(\047%s\047,\047%s\047,strftime(\047%%Y-%%m-%%dT%%H:%%M:%%SZ\047,\047now\047));\n", q(goal), q(goal)
  printf "DELETE FROM plan_item WHERE goal_id=\047%s\047;\n", q(goal)
  for (i=1; i<=n; i++) {
    id=ids[i]; if (!placed[id]) continue
    s = wu*unblocks[id] + we*esc[id] + wt*(tier[id] in tierw ? tierw[tier[id]] : 0)
    score[id]=s; L=layer[id]
    bucket[L] = bucket[L] " " id
  }
  # Best score in each (layer, cluster) -- a cluster is visited when its strongest task
  # would have been, so grouping never demotes urgent work behind a quiet cluster.
  for (i=1; i<=n; i++) {
    id=ids[i]; if (!placed[id]) continue
    ck = layer[id] SUBSEP cluster[id]
    if (!(ck in cbest) || score[id] > cbest[ck]) cbest[ck] = score[id]
  }
  for (L=0; L<=n; L++) {
    if (!(L in bucket)) continue
    m=split(bucket[L], arr, " ")
    # LAYER dominates, then cluster, then score. Layer must stay outermost: clusters are
    # semantic now, so a dependency CAN cross one, and ordering cluster-first would run a
    # task ahead of something it depends on. Grouping happens inside a layer, never across.
    c=0; for (j=1;j<=m;j++) if (arr[j]!="") srt[++c]=arr[j]
    for (j=2;j<=c;j++) { k=srt[j]; p=j-1
      while (p>0 && before(k, srt[p])) { srt[p+1]=srt[p]; p-- }
      srt[p+1]=k }
    for (j=1;j<=c;j++) {
      id=srt[j]
      printf "INSERT INTO plan_item VALUES(\047%s\047,\047%s\047,%d,%d,%.3f,%d);\n", \
             q(goal), q(id), L, j, score[id], cluster[id]
    }
    delete srt
  }
  print "COMMIT;"
}' > "$SQL" 2>"$ERR"

if grep -q '^CYCLE' "$ERR" 2>/dev/null; then
  kit_warn "dependency cycle — these tasks are withheld from the plan, not reordered:"
  grep '^CYCLE' "$ERR" | sed 's/^CYCLE//' | tr ' ' '\n' | sed '/^$/d;s/^/  /' >&2
  kit_warn "fix blocked_by in the task files; a cycle cannot be sequenced."
fi

# Said out loud for the same reason as the cycle above: a task quietly missing from the plan
# is indistinguishable from a task the plan judged unimportant, and this one is neither.
#
# The count goes to the plan table as well as to stderr. stderr alone is not a record -- this
# repository's own fixtures invoke this script with stderr redirected away, which is exactly how
# an orchestrator would run it, and a plan that came back a fifth of its size would arrive with
# no explanation attached to it. `--show` reads it back from the index, where the plan is.
if grep -q '^UNRESOLVED' "$ERR" 2>/dev/null; then
  HELD=$(grep '^WITHHELDCOUNT' "$ERR" | head -1 | awk '{print $2"/"$3}')
  kit_warn "blocked by an id with no task file — ${HELD:-some} open task(s) withheld from the plan:"
  grep '^UNRESOLVED' "$ERR" | sed 's/^UNRESOLVED \([^ ]*\)  */  \1 blocked by /' >&2
  kit_warn "each root is named above; anything behind one is withheld with it."
  kit_warn "file the blocking task, or correct blocked_by; an unknown blocker is not a satisfied one."
fi

sqlite3 "$DB" < "$SQL" || { kit_warn "plan write failed"; exit 1; }

# Persisted beside the plan, not only shouted at a terminal that may not exist. DELETE first and
# write only when the condition holds: a stale count must not outlive its cause -- a warning that
# survives what caused it is worse than no warning -- but a `0 0` row on every clean run is index
# churn for nothing. Measured: writing it unconditionally moved the fixture index fingerprint,
# which is the signal this repository uses to detect drift. A control that costs a false drift
# signal on every run teaches people to ignore the signal.
HELDN=$(grep '^WITHHELDCOUNT' "$ERR" 2>/dev/null | head -1 | awk '{print $2" "$3}')
sqlite3 "$DB" "DELETE FROM meta WHERE key='plan_withheld:$GOAL_SQL';" 2>/dev/null
[ -n "$HELDN" ] &&
  sqlite3 "$DB" "INSERT INTO meta VALUES('plan_withheld:$GOAL_SQL','$HELDN');" 2>/dev/null

# ---- frozen context packs, one per cluster ------------------------------------------
# What every session in a cluster needs and none of them should re-derive: which tasks are
# in it, which files it touches, what has already gone wrong there. Written once per plan
# and byte-identical thereafter, so it belongs ABOVE the cache breakpoint and is served at
# 0.1x instead of being re-read at full price in each session.
#
# It is a snapshot on purpose. Regenerating per session would break byte-identity and put
# the 1.25x write premium back; findings that land mid-cluster are picked up at the next
# `kit-plan.sh` run. Derived, disposable, gitignored -- deleting the packs loses nothing.
# sqlite3 on Windows writes CRLF. Command substitution strips the trailing newline but not
# the CR, so `for C in $(sqlite3 ...)` yields "1<CR>" and the pack is written as
# "c1<CR>.md" -- a filename that lists correctly and cannot be opened by the name you type.
# gawk strips CR in text mode, which is why the clustering above is unaffected and only the
# shell-side captures need this.
sq() { sqlite3 "$@" | tr -d '\r'; }

# Window functions -- ROW_NUMBER() OVER (PARTITION BY ...), used below to cap the file
# list per cluster -- arrived in SQLite 3.25. An older build errors on the query rather
# than degrading, so name the unmet requirement instead of surfacing a bare SQL error.
# Only the packs need it; layering, scoring and the plan itself do not, so those still run.
SQLV=$(sqlite3 --version 2>/dev/null | awk '{print $1}')
PACKS_OK=$(printf '%s' "${SQLV:-0}" | awk -F. '{ print ($1 > 3 || ($1 == 3 && $2 >= 25)) ? 1 : 0 }')
if [ "$PACKS_OK" != 1 ]; then
  kit_warn "sqlite3 ${SQLV:-unknown} is older than 3.25 — cluster context packs need window"
  kit_warn "functions and are skipped. The plan and its ordering are unaffected."
fi

GOAL_SLUG=$(printf '%s' "$GOAL" | tr -c 'A-Za-z0-9._-' '-')
PACKS="$ROOT/$STATE_DIR/packs/$GOAL_SLUG"
if [ "$PACKS_OK" = 1 ]; then
rm -rf "$PACKS"; mkdir -p "$PACKS"
# One query and one awk for every pack, rather than three queries per cluster. At 300
# tasks / 20 clusters the per-cluster shape spawned 60 sqlite3 processes and took ~36s.
# The three SELECTs are tagged T/F/D and demultiplexed below.
npacks=$(sq -separator $'\t' "$DB" "
  SELECT p.cluster, 'T',
         p.task_id||'  ['||COALESCE(NULLIF(t.tier,''),'-')||']  '||COALESCE(n.title,'')
    FROM plan_item p JOIN task t ON t.id=p.task_id LEFT JOIN node n ON n.id=p.task_id
   WHERE p.goal_id='$GOAL_SQL' ORDER BY p.cluster, p.layer, p.rank;

  SELECT cluster, 'F', line FROM (
    SELECT p.cluster AS cluster,
           n.path||'  ('||COUNT(DISTINCT e.src)||' tasks)' AS line,
           ROW_NUMBER() OVER (PARTITION BY p.cluster
                              ORDER BY COUNT(DISTINCT e.src) DESC, n.path) AS rn
      FROM plan_item p
      JOIN edge e ON e.src=p.task_id AND e.rel='touches'
      JOIN node n ON n.id=e.dst
     WHERE p.goal_id='$GOAL_SQL'
     GROUP BY p.cluster, n.path)
   WHERE rn <= 40 ORDER BY cluster, rn;

  -- Confirmed defects anywhere in this cluster's files, including from tasks outside the
  -- cluster. Prior evidence about the code, not about the batch.
  SELECT p.cluster, 'D', f.class||'  '||COALESCE(NULLIF(f.lang,''),'-')||'  x'||COUNT(*)
    FROM plan_item p
    JOIN edge e1 ON e1.src=p.task_id AND e1.rel='touches'
    JOIN edge e2 ON e2.dst=e1.dst AND e2.rel='touches'
    JOIN finding f ON f.task_id=e2.src AND f.vindicated=1
   WHERE p.goal_id='$GOAL_SQL'
   GROUP BY p.cluster, f.class, f.lang ORDER BY p.cluster, COUNT(*) DESC;
" 2>/dev/null | KIT_PACKS="$PACKS" KIT_GOAL="$GOAL" awk -F'\t' '
  BEGIN { dir = ENVIRON["KIT_PACKS"]; goal = ENVIRON["KIT_GOAL"] }
  NF >= 3 {
    c = $1
    if (!(c in seen)) { seen[c] = 1; order[++nc] = c }
    if      ($2 == "T") tasks[c] = tasks[c] "- " $3 "\n"
    else if ($2 == "F") files[c] = files[c] "- " $3 "\n"
    else if ($2 == "D") prior[c] = prior[c] "- " $3 "\n"
  }
  END {
    for (i = 1; i <= nc; i++) {
      c = order[i]; f = dir "/c" c ".md"
      printf "<!-- GENERATED by kit-plan.sh (goal %s, cluster %s). Frozen for this plan and\n", goal, c > f
      printf "     byte-identical across every session in it. Do not edit; re-run kit-plan.sh. -->\n\n" > f
      printf "# Cluster %s\n\n## Tasks in this cluster\n\n", c > f
      printf "%s", (c in tasks ? tasks[c] : "_none_\n") > f
      printf "\n## Files this cluster touches\n\n" > f
      printf "%s", (c in files ? files[c] : "_none recorded yet — no commits touch these tasks_\n") > f
      printf "\n## Confirmed defect classes in these files\n\n" > f
      printf "%s", (c in prior ? prior[c] : "_none_\n") > f
      close(f)
    }
    print nc
  }')
[ "${npacks:-0}" -gt 0 ] && kit_warn "wrote $npacks cluster pack(s) to ${PACKS#$ROOT/}"
fi   # PACKS_OK — sqlite3 >= 3.25

if [ "$SHOW" = 1 ]; then
  sqlite3 -header -column "$DB" "
    SELECT p.layer, p.cluster, p.rank, p.task_id, ROUND(p.score,1) score,
           COALESCE(t.tier,'-') tier, COALESCE(n.title,'') title
      FROM plan_item p JOIN task t ON t.id=p.task_id
      LEFT JOIN node n ON n.id=p.task_id
     WHERE p.goal_id='$GOAL_SQL' ORDER BY p.layer, p.rank;"
else
  # The whole point: a session reads this, not the graph.
  sqlite3 -separator '  ' "$DB" "
    SELECT p.task_id, COALESCE(t.tier,'-'), COALESCE(n.title,'')
      FROM plan_item p JOIN task t ON t.id=p.task_id
      LEFT JOIN node n ON n.id=p.task_id
     WHERE p.goal_id='$GOAL_SQL' ORDER BY p.layer, p.rank LIMIT $NEXT;"
fi

# Read back from the index rather than from this run, so it reaches a caller that reruns --show
# later or that dropped stderr on the run that computed it. A short plan and the reason for it
# arrive together or the reason may as well not exist.
HELDBACK=$(sqlite3 "$DB" "SELECT value FROM meta WHERE key='plan_withheld:$GOAL_SQL';" 2>/dev/null | tr -d '\r')
case "${HELDBACK:-0 0}" in
  ''|'0 0') ;;
  *) kit_warn "$(printf '%s of %s open task(s) withheld: blocked by an id with no task file. Rerun to list the roots.' ${HELDBACK})" ;;
esac
