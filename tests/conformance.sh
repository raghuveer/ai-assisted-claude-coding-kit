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
for a in "$KIT"/agents/*.md; do
  grep -q 'kit-finding.sh' "$a" || continue
  flat=$(tr '\n' ' ' < "$a" | tr -s ' ')
  case "$flat" in *"$VC"*) ;; *) echo "  class list differs: $(basename "$a")"; drift=1 ;; esac
  case "$flat" in *"$VS"*) ;; *) echo "  severity list differs: $(basename "$a")"; drift=1 ;; esac
done
check $drift "every agent's inlined vocabulary matches kit-finding.sh --vocab"

step "no agent is told to run a tool it does not have"
# implementation-reviewer was told to run kit-finding.sh --vocab with tools: Read, Grep,
# Glob. It guessed the classes instead, and 3 of its 4 would have been rejected.
ungranted=0
for a in "$KIT"/agents/*.md; do
  tools=$(sed -n 's/^tools:[[:space:]]*//p' "$a" | head -1)
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
# HEAD must be the same commit on every machine. If this fails the fixture drifted, and the
# fingerprint above is comparing two different things rather than two platforms.
[ "$H" = "$EXPECT_HEAD" ]
check $? "fixture is reproducible (HEAD == $EXPECT_HEAD)"

printf '\n=== %d passed, %d failed\n' "$ok" "$bad"
exit $bad
