#!/usr/bin/env bash
# Cross-platform conformance run.
#
#   KIT=/path/to/kit WORK=/path/to/empty/scratch bash tests/conformance.sh
#
# Builds a deterministic fixture -- fixed author AND committer dates, so every commit SHA
# is identical on every machine -- then exercises the pipeline end to end and prints a
# fingerprint of the derived index. Two platforms running this must produce the same
# fingerprint; when they did not, it surfaced two real defects at once (see 0.5.2).
#
# The fixture is deliberately awkward: a squash-shaped commit whose trailers git will not
# parse, module pairs that co-change, and a file in every commit that must be dropped as a
# hub. A fixture that only exercises the happy path proves the happy path.
set -uo pipefail

KIT=${KIT:?set KIT to the kit checkout}
WORK=${WORK:?set WORK to an empty scratch dir}
ok=0; bad=0
step() { printf '\n=== %s\n' "$*"; }
check() { if [ "$1" = 0 ]; then ok=$((ok+1)); printf '  PASS  %s\n' "$2"
          else bad=$((bad+1)); printf '  FAIL  %s\n' "$2"; fi; }

step "environment"
uname -srm 2>/dev/null || echo "(no uname)"
bash --version | head -1; git --version; sqlite3 --version | awk '{print "sqlite3 "$1}'
(awk --version 2>/dev/null || awk -W version 2>&1) | head -1

step "scripts are executable in the git index"
# Not on disk: git on Windows cannot read the msys exec bit, so a chmod there never reaches
# the index and the file lands non-executable on Linux. The index is the shared truth.
nx=0
for f in $(git -C "$KIT" ls-files tooling templates | grep -E '\.sh$|commit-msg'); do
  m=$(git -C "$KIT" ls-files -s "$f" | awk '{print $1}')
  [ "$m" = 100755 ] || { echo "  $m $f"; nx=1; }
done
check $nx "every script is 100755"

step "finding vocabulary has not drifted"
# The reviewers have no Bash, so they cannot run `kit-finding.sh --vocab` and the lists are
# inlined in their instructions. That is the only form they can use, and it is exactly the
# duplication the script's own header warns about -- the vocabulary already diverged across
# four locations once, and the agents emitted classes the recorder rejected. Inlining is
# safe only while something checks it, so this checks it.
V=$(bash "$KIT/tooling/kit-finding.sh" --vocab)
VC=$(printf '%s' "$V" | sed -n 's/^class:[[:space:]]*//p')
VS=$(printf '%s' "$V" | sed -n 's/^severity:[[:space:]]*//p')
drift=0
# Name the word the match dies on. "class list differs" alone sends the reader to compare two
# lists by eye, and the difference that actually occurred was an invisible byte -- so the one
# thing the message must not do is leave the reader looking at two lists that appear equal.
first_divergence() {  # <expected list> <flattened agent text>
  _pre=""
  for _w in $1; do
    if [ -n "$_pre" ]; then _try="$_pre $_w"; else _try="$_w"; fi
    case "$2" in *"$_try"*) _pre="$_try" ;; *) printf '%s' "$_w"; return ;; esac
  done
}
for a in "$KIT"/agents/*.md; do
  grep -q 'kit-finding.sh' "$a" || continue
  # CR is deleted BEFORE the newlines become spaces. Without that, a list wrapped across a
  # line flattens to `...style<CR> unclassified` on a CRLF checkout and matches nothing --
  # which reported all three reviewers as drifted while every one of them was correct. A
  # guard that is red for a reason unrelated to what it guards stops being read.
  flat=$(tr -d '\r' < "$a" | tr '\n' ' ' | tr -s ' ')
  case "$flat" in *"$VC"*) ;; *)
    echo "  class list differs: $(basename "$a") — breaks at \"$(first_divergence "$VC" "$flat")\""
    echo "    kit-finding.sh --vocab: $VC"; drift=1 ;;
  esac
  case "$flat" in *"$VS"*) ;; *)
    echo "  severity list differs: $(basename "$a") — breaks at \"$(first_divergence "$VS" "$flat")\""
    echo "    kit-finding.sh --vocab: $VS"; drift=1 ;;
  esac
done
check $drift "every agent's inlined vocabulary matches kit-finding.sh --vocab"

step "no agent is told to run a tool it does not have"
# implementation-reviewer was told to run kit-finding.sh --vocab with tools: Read, Grep,
# Glob. It guessed the classes instead, and 3 of its 4 would have been rejected.
ungranted=0
for a in "$KIT"/agents/*.md; do
  # `tr -d '\r'` here and in every other reader of a checked-out file below. .gitattributes
  # pins *.md to LF, and a test that only passes while it does is a test of the reader's git
  # configuration. This one survived a CRLF checkout by luck -- the tool name it looks for is
  # never last on the line -- and the vocabulary check three steps down did not.
  tools=$(tr -d '\r' < "$a" | sed -n 's/^tools:[[:space:]]*//p' | head -1)
  case "$tools" in *Bash*) continue ;; esac
  if grep -qE 'Run `kit-[a-z-]+\.sh' "$a"; then
    echo "  $(basename "$a") has no Bash but is told to run a script"; ungranted=1
  fi
done
check $ungranted "no Bash-less agent is instructed to execute a script"

step "a domain outside the declared industries is dropped, not stored"
# An unknown class is rejected loudly. A wrong domain was accepted SILENTLY and polluted the
# industry accelerator it feeds -- reviewers put the finding's subject there (`caching`,
# `cache-adapter-design`) because nothing said what a domain was. The `pattern` axis is where
# that belongs now, and a domain the project never declared must not survive.
step_dir="$WORK.dom"; rm -rf "$step_dir"; mkdir -p "$step_dir/.claude" "$step_dir/.project"
( cd "$step_dir" && git init -q -b main 2>/dev/null
  printf -- '---
paths.state: .project
accelerator.industry: .claude/bfsi.md
---
' > .claude/project-profile.md
  : > .claude/bfsi.md
  bash "$KIT/tooling/kit-finding.sh" --task T --agent a --batch >/dev/null 2>&1 <<'BATCH'
fail-open|major|go|cache-port|not-an-industry
BATCH
  grep -q '"domain":""' .project/events.ndjson && grep -q '"pattern":"cache-port"' .project/events.ndjson )
check $? "undeclared domain dropped, pattern retained"
rm -rf "$step_dir"

step "a trivial commit still has its trailers checked"
# git.trivial_pattern means trailers are not REQUIRED, not that they are not CHECKED. The
# early return let a `docs:` commit carry a typo'd Task-Id, which then indexed as a titleless
# phantom task -- and a pushed commit message cannot be corrected.
tx="$WORK.exempt"; rm -rf "$tx"; mkdir -p "$tx"
( cd "$tx" && git init -q -b main 2>/dev/null
  mkdir -p .claude .project/tasks
  printf -- '---
paths.tasks:  .project/tasks
paths.state:  .project
---
' > .claude/project-profile.md
  printf -- '---
id: T-real
title: r
tier: T1
---
b
' > .project/tasks/T-real.md
  printf 'docs: x

Task-Id: T-nope
Tier: T9
' > bad.txt
  printf 'docs: x
' > ok.txt
  bash "$KIT/tooling/kit-trailers.sh" message bad.txt 2>&1 | grep -q "matches no task" || exit 1
  bash "$KIT/tooling/kit-trailers.sh" message bad.txt 2>&1 | grep -q "invalid  Tier" || exit 1
  [ -z "$(bash "$KIT/tooling/kit-trailers.sh" message ok.txt 2>&1)" ] || exit 1 )
check $? "exempt commit: absence allowed, wrong values still reported"
rm -rf "$tx"

step "pre-push blocks a wrong trailer while it can still be amended"
# commit-msg is skippable and absent for anyone who never ran kit-init; CI catches correctly
# but only after the push, when a commit message can no longer be changed. This repository
# carries a permanent phantom task from exactly that gap.
pp="$WORK.push"; rm -rf "$pp"; mkdir -p "$pp/remote" "$pp/work"
( cd "$pp/remote" && git init -q --bare -b main 2>/dev/null
  cd "$pp/work" && git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  git remote add origin "$pp/remote"
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  [ -x .git/hooks/pre-push ] || exit 1
  mkdir -p .project/tasks
  printf -- '---
id: T-real
title: r
tier: T2
---
b
' > .project/tasks/T-real.md
  sed -i.bak 's|^git.trailer_enforcement:.*|git.trailer_enforcement:  enforce|' .claude/project-profile.md
  rm -f .claude/project-profile.md.bak
  git add -A && git commit -q --no-verify -m "chore: seed"
  echo x > a.txt && git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-typo
Tier: T2"
  git push origin main >/dev/null 2>&1 && exit 1          # must be REFUSED
  git commit -q --amend --no-verify -m "feat: w

Task-Id: T-real
Tier: T2"
  git push origin main >/dev/null 2>&1 || exit 1 )        # must now succeed
check $? "refuses a typo'd Task-Id, accepts it once amended"
rm -rf "$pp"

step "spend is measured per agent, from that agent's own transcript"
# The defect this replaced: every SubagentStop received the SESSION transcript, which holds
# no subagent records at all, so each row was main-loop cost wearing an agent's name. The
# fixture therefore puts DIFFERENT numbers in the two transcripts -- a reader that fell back
# to the session file would produce the main loop's figures under the agent's label, and pass
# a test that only counted rows.
#
# Totals are cumulative per transcript, so recording twice must not double the cost, and
# Stop's sweep must not re-record what SubagentStop already wrote.
sx="$WORK.spend"; rm -rf "$sx"; mkdir -p "$sx/src" "$sx/sess/subagents"
( cd "$sx" && git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---
id: T-s
title: s
tier: T2
---
b
' > .project/tasks/T-s.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  printf '{"type":"assistant","message":{"model":"m-main","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000,"output_tokens":500}}}
' > sess.jsonl
  printf '{"type":"assistant","message":{"model":"m-sub","usage":{"input_tokens":5,"cache_creation_input_tokens":400,"cache_read_input_tokens":0,"output_tokens":200}}}
' > sess/subagents/agent-A1.jsonl
  printf '{"agentType":"implementation-reviewer","spawnDepth":1}' > sess/subagents/agent-A1.meta.json
  # SubagentStop, then Stop, then both again: four firings, and only two things happened.
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id A1 --agent security-reviewer
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl"
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id A1 --agent security-reviewer
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl"
  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-s
Tier: T2
Task-Status: done"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }
  rows=$(Q "SELECT COUNT(*) FROM spend;")
  sub=$(Q "SELECT agent||'/'||agent_id||'/'||model||'/'||tok_out||'/'||context FROM spend WHERE scope='subagent';")
  main=$(Q "SELECT '['||agent||']/'||model||'/'||tok_out FROM spend WHERE scope='main';")
  att=$(Q "SELECT COUNT(*) FROM spend WHERE task_id='T-s';")
  # 10 + 0x1.25 + 1000x0.1 + 500x5 = 2610, and 5 + 400x1.25 + 0 + 200x5 = 1505. The raw sum
  # of the same counters is 2115 -- pricing a cache read like fresh input and output like
  # neither. If this ever equals 2115 the weighting has been dropped.
  w=$(Q "SELECT SUM(tok_in*100 + cache_write*125 + cache_read*10 + tok_out*500)/100 FROM spend;")
  [ "$rows" = 2 ] && [ "$att" = 2 ] && [ "$w" = 4115 ] &&
  [ "$sub" = "security-reviewer/A1/m-sub/200/405" ] && [ "$main" = "[]/m-main/500" ] )
check $? "one row per transcript, agent rows from agent files, main loop unlabelled"

step "a subagent whose transcript cannot be found is reported, not costed"
# The alternative -- writing the row anyway from whatever transcript is at hand -- is the
# defect. Nothing is recorded, and the fact that nothing was recorded is.
( cd "$sx"
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id GHOST --agent coder
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id GHOST --agent coder
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  rows=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM spend;" | tr -d '\015')
  gaps=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE kind='spend-gap';" | tr -d '\015')
  [ "$rows" = 2 ] && [ "$gaps" = 1 ] )
check $? "no spend row, one spend-gap, and not one gap per firing"
rm -rf "$sx"

step "a CRLF profile and CRLF task files parse identically to LF"
# A Windows checkout of a repo without `*.md text eol=lf` puts CR on the end of every line of
# the profile and of every task file. The readers trimmed space and tab, so `paths.tasks`
# became `.project/tasks<CR>` -- naming no directory, finding no tasks, and reporting an empty
# backlog rather than an error.
#
# THIS STEP CANNOT FAIL UNDER A LENIENT AWK. The gawk in git-bash strips CR on input, so the
# defect is invisible there; a POSIX awk keeps it. Running the assertion anyway would be a
# green that means "not exercised", which is the failure mode this suite exists to refuse. So
# the awk is probed first, and if it strips CR the step re-runs the kit under `gawk
# -v BINMODE=3` -- which is what every other awk does by default -- and says which mode it
# used. If neither is available it reports NOT EXERCISED rather than passing.
cr_len=$(printf 'x\r\n' | awk 'NR==1{print length($0)}')
cx="$WORK.crlf"; rm -rf "$cx"; mkdir -p "$cx/.claude" "$cx/.project/tasks" "$cx/shim"
awkmode=native
if [ "$cr_len" = 1 ]; then
  printf 'x\r\n' > "$cx/probe"
  if command -v gawk >/dev/null 2>&1 && [ "$(gawk -v BINMODE=3 'NR==1{print length($0)}' "$cx/probe")" = 2 ]; then
    printf '#!/usr/bin/env bash\nexec gawk -v BINMODE=3 "$@"\n' > "$cx/shim/awk"
    chmod +x "$cx/shim/awk"; awkmode="BINMODE=3 shim"
  else
    awkmode="NOT EXERCISED"
  fi
fi
printf '  awk keeps CR: %s\n' "$awkmode"
if [ "$awkmode" = "NOT EXERCISED" ]; then
  echo "  SKIP  this awk strips CR on input and cannot be made to keep it"
else
  ( cd "$cx"
    [ -x shim/awk ] && PATH="$PWD/shim:$PATH" && export PATH
    git init -q -b main 2>/dev/null
    # TWO tier.rules on purpose. kit_cfg_all returns them as lines of one command
    # substitution, and `$(...)` drops only the LAST trailing CR -- so a single rule is
    # accidentally clean and the first of two is not. A fixture that cannot reach the
    # interior line tests the accident rather than the reader.
    printf -- '---\r\npaths.tasks:  .project/tasks\r\npaths.state:  .project\r\ntier.default: T1\r\ntier.rule: src/** T3\r\ntier.rule: lib/** T2\r\n---\r\n' > .claude/project-profile.md
    printf -- '---\r\nid: T-crlf\r\ntitle: c\r\ntier: T1\r\nepic: e1\r\npaths: src/a.go\r\n---\r\n\r\nbody\r\n' > .project/tasks/T-crlf.md
    bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
    # Every value below rides on a different reader: the profile through kit_cfg, the task
    # frontmatter through the indexer's own parser, and the floor through the tier.rule trim.
    n=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM task;" | tr -d '\015')
    r=$(sqlite3 .project/index.db "SELECT tier||'/'||epic||'/'||COALESCE(tier_floor,'-') FROM task WHERE id='T-crlf';" | tr -d '\015')
    [ "$n" = 1 ] && [ "$r" = "T1/e1/T3" ] )
  check $? "CRLF input yields the same tier, epic and floor as LF"
fi
rm -rf "$cx"

step "a tier below its floor is reported"
# Under-tiering is silent and it is the dangerous direction. Two of three recorded tiers in a
# real backlog were below their floor -- and a floor computed only from touched files would
# have caught NONE of them, because 7 of 8 open tasks had no commits yet. Hence the declared
# paths source, which is what this exercises.
#
# Its own directory: an earlier version of this check mutated the shared fixture and broke
# the losslessness comparison three steps later.
tf="$WORK.floor"; rm -rf "$tf"; mkdir -p "$tf"
( cd "$tf" && git init -q -b main 2>/dev/null
  mkdir -p .claude .project/tasks
  { echo "---"
    echo "paths.tasks:  .project/tasks"
    echo "paths.state:  .project"
    echo "tier.default: T1"
    echo "tier.rule: src/adapters/** T3"
    echo "tier.rule: src/core/** T2"
    echo "---"; } > .claude/project-profile.md
  printf -- '---
id: T-under
title: u
tier: T1
paths: src/adapters/Q.ts
---
b
' > .project/tasks/T-under.md
  printf -- '---
id: T-above
title: a
tier: T3
paths: src/core/X.ts
---
b
' > .project/tasks/T-above.md
  printf -- '---
id: T-none
title: n
tier: T0
---
b
' > .project/tasks/T-none.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  u=$(sqlite3 .project/index.db "SELECT tier_floor FROM task WHERE id='T-under';" | tr -d '\015')
  a=$(sqlite3 .project/index.db "SELECT tier_floor FROM task WHERE id='T-above';" | tr -d '\015')
  n=$(sqlite3 .project/index.db "SELECT COALESCE(tier_floor,'null') FROM task WHERE id='T-none';" | tr -d '\015')
  b=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM task WHERE tier_floor IS NOT NULL AND tier < tier_floor;" | tr -d '\015')
  [ "$u" = T3 ] && [ "$a" = T2 ] && [ "$n" = null ] && [ "$b" = 1 ] )
check $? "floor from declared paths; below flagged, above not, no-basis distinguished"
rm -rf "$tf"

step "validate.py"
(cd "$KIT" && { python3 validate.py >/dev/null 2>&1 || python validate.py >/dev/null 2>&1; })
check $? "validate.py exits 0"

step "deterministic fixture"
rm -rf "$WORK"; mkdir -p "$WORK/src" "$WORK/lib"; cd "$WORK" || exit 1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+00:00" GIT_COMMITTER_DATE="2026-01-01T00:00:00+00:00"
git init -q -b main; git config core.autocrlf false; git config commit.gpgsign false
bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
printf -- '---\nid: T-a\ntitle: bound retry\ntier: T2\nlang: go\nepic: e1\n---\n\nbody\n' > .project/tasks/T-a.md
printf -- '---\nid: T-b\ntitle: add jitter\ntier: T1\nlang: go\nepic: e1\nblocked_by: T-a\n---\n\nbody\n' > .project/tasks/T-b.md
printf 'seed\n' > README.md
git add -A && git commit -q --no-verify -m "chore: seed"
# Kept for the FINGERPRINT report. The seed commit is the only one whose content comes from
# OUTSIDE this script -- kit-init.sh copies the profile template in -- so it is where an
# environmental difference enters, and every commit after it is printf output. Reporting it
# separates "the kit's files differ" from "this script changed".
SEED=$(git rev-parse HEAD)

# 24 paired commits: each module's two files always change together, README changes in
# every one and must be dropped as a hub, and 24 gives hub_pct a real denominator.
for m in 1 2 3 4 5 6 7 8; do
  for r in 1 2 3; do
    printf '%s%s\n' "$m" "$r" > "src/m${m}.go"
    printf '%s%s\n' "$m" "$r" > "lib/m${m}_util.go"
    printf '%s%s\n' "$m" "$r" > README.md
    git add -A && git commit -q --no-verify -m "chore: module $m rev $r"
  done
done

printf 'x\n' > src/a.go; git add -A
git commit -q --no-verify -m "feat: one

Task-Id: T-a
Tier: T2
Task-Status: started"
# Trailers stranded before a later paragraph: what GitHub squash-merge produces.
printf 'y\n' > src/b.go; git add -A
git commit -q --no-verify -m "feat: squashed with co-author

* work

Task-Id: T-b
Tier: T1
Task-Status: done

Co-authored-by: X <x@example.com>"
echo "  commits: $(git rev-list --count HEAD)"
# Moves whenever templates/project-profile.md changes, because kit-init.sh copies it into
# the fixture's first commit. That is the cost of also using this as a drift detector:
# it forces a template edit to be noticed rather than silently changing what two
# platforms are comparing. Update it deliberately, never to make a red run go green.
EXPECT_HEAD=53000060db14454d607a4db4bacef4e758ed0382
# The seed alone, so a mismatch says WHICH half moved. Unchanged since the pin above was set,
# which is how the CRLF diagnosis was confirmed: the fixture had not drifted at all.
EXPECT_SEED=ef380ef1265d36244ebd24940adb2ca0e32125f5

step "trailer hook"
sed -i.bak 's|^git.trailer_enforcement:.*|git.trailer_enforcement:  enforce|' .claude/project-profile.md
rm -f .claude/project-profile.md.bak
printf 'z\n' > src/c.go; git add -A
git commit -q -m "feat: untrailered" >/dev/null 2>&1
[ $? -ne 0 ]; check $? "rejects an untrailered commit"
git commit -q -m "feat: stranded

Task-Id: T-a
Tier: T2

Co-authored-by: Y <y@example.com>" >/dev/null 2>&1
[ $? -ne 0 ]; check $? "rejects trailers stranded before a later paragraph"
git commit -q -m "feat: trailered

Task-Id: T-a
Tier: T2" >/dev/null 2>&1
check $? "accepts a well-formed one"

step "pipeline"
bash "$KIT/tooling/kit-index.sh" > idx.log 2>&1
rc=$?; check $rc "kit-index.sh"
# Show why. Swallowing this cost a full CI round trip to diagnose a one-character fix.
[ $rc = 0 ] || { echo "  --- kit-index.sh output ---"; sed 's/^/  /' idx.log | head -20; }
grep -q "recovered by full-message scan" idx.log; check $? "recovers the squash-stranded trailers"
bash "$KIT/tooling/kit-plan.sh" --next 5 >/dev/null 2>&1; check $? "kit-plan.sh"
bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1; check $? "kit-status.sh"

step "derived state"
sqlite3 -header .project/index.db "SELECT id,state,tier,lang,epic FROM task ORDER BY id;" | tr -d '\r'
sqlite3 .project/index.db "SELECT key,value FROM meta ORDER BY key;" | tr -d '\r'

step "timestamps are canonical UTC"
# %aI would carry the author local offset and render differently across git versions, so
# the same history produced different indexes on different machines and ORDER BY compared
# offsets lexically. Everything must be ...Z.
n=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE at NOT LIKE '%Z';" | tr -d '\r')
[ "${n:-1}" = 0 ]; check $? "every event.at ends in Z"

step "co-change"
CC=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM cochange;" | tr -d '\r')
[ "${CC:-0}" -gt 0 ]; check $? "co-change graph was built ($CC rows)"
sqlite3 .project/index.db "SELECT COUNT(*) FROM cochange WHERE src LIKE '%README%';" | tr -d '\r' | grep -qx 0
check $? "README excluded as a hub"

step "delete and rebuild is lossless"
sqlite3 .project/index.db ".dump" | grep -v "INSERT INTO goal" | tr -d '\r' | LC_ALL=C sort > b.dump
rm -f .project/index.db
bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
bash "$KIT/tooling/kit-plan.sh" --next 5 >/dev/null 2>&1
sqlite3 .project/index.db ".dump" | grep -v "INSERT INTO goal" | tr -d '\r' | LC_ALL=C sort > a.dump
cmp -s b.dump a.dump; check $? "rebuild is byte-identical"

step "CI gate"
bash "$KIT/tooling/kit-trailers.sh" range "HEAD~1..HEAD" --enforce >/dev/null 2>&1
check $? "passes on a well-formed commit"

step "FINGERPRINT"
H=$(git rev-parse HEAD)
printf '  head    %s\n' "$H"
# sqlite .dump emits sqlite_sequence and PRAGMA writable_schema differently by version, so
# they are excluded: they are dump formatting, not kit state.
printf '  index   %s\n' \
  "$(grep -v 'sqlite_sequence\|writable_schema' a.dump | { sha256sum 2>/dev/null || shasum -a 256; } | awk '{print $1}')"
# The fixture is fully determined -- fixed author and committer dates, fixed content -- so
# HEAD must be the same commit on every machine. A mismatch has two causes and they are not
# the same problem: the fixture drifted, or the FILES IT COMMITS differ between checkouts.
# Say which. Reading only the HEAD mismatch, the obvious conclusion is drift, and once that
# was assumed a CRLF profile template took a template diff, a kit-init diff and a two-version
# fixture rebuild to find. The seed commit is where anything from outside this script enters.
if [ "$H" != "$EXPECT_HEAD" ]; then
  printf '  seed    %s  (expected %s)\n' "$SEED" "$EXPECT_SEED"
  [ "$SEED" = "$EXPECT_SEED" ] &&
    printf '  ^ seed matches, so the divergence is in this script, not in the kit files it commits\n' ||
    printf '  ^ seed differs: a file kit-init.sh commits is not byte-identical here. Compare\n    `git ls-tree -r %s` against a known-good checkout before touching EXPECT_HEAD.\n' "$SEED"
fi
[ "$H" = "$EXPECT_HEAD" ]
check $? "fixture is reproducible (HEAD == $EXPECT_HEAD)"

printf '\n=== %d passed, %d failed\n' "$ok" "$bad"
exit $bad
