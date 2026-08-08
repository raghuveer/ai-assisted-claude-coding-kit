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
ok=0; bad=0; skipped=0
step() { printf '\n=== %s\n' "$*"; }
check() { if [ "$1" = 0 ]; then ok=$((ok+1)); printf '  PASS  %s\n' "$2"
          else bad=$((bad+1)); printf '  FAIL  %s\n' "$2"; fi; }
# A control that could not run is not a control that passed. It does not fail the suite --
# an unrunnable check is not a defect -- but it is counted and named in the tally, because
# the tally and the exit code are what CI reads and "N passed, 0 failed" over a check that
# never executed is the same green-that-means-nothing this suite exists to refuse.
skip()  { skipped=$((skipped+1)); printf '  SKIP  %s — %s\n' "$2" "$1"; }

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

step "a script broken by an apostrophe names the apostrophe"
# Every awk program here is a multi-line single-quoted shell string, so an apostrophe typed
# inside one -- almost always an English possessive in a comment -- closes it and everything
# after is reinterpreted as shell. It happened twice on 2026-08-08 in the same file.
#
# `bash -n` DETECTS it and is already commands.lint. What it does not do is locate it: both
# times it reported the line where parsing finally broke, tens of lines below the cause,
# naming an unrelated token. So this step does not re-detect; it DIAGNOSES, by reporting the
# nearest comment-with-an-apostrophe at or above the line bash names.
#
# A standalone scanner was tried first and rejected on measurement, not taste: tracking
# single-quote parity to decide whether a line sits inside a program flags 21 lines of this
# tree, because an apostrophe inside a DOUBLE-quoted string -- `sed "s/'/''/g"` -- flips the
# same counter. Separating those needs a shell tokeniser, which is more machinery than the
# defect is worth. Anchoring to the line bash already found needs none.
#
# NOT COVERED, and worth saying: two stray apostrophes re-balance the quoting, so the script
# parses, runs, and hands awk a silently altered program. `bash -n` cannot see that and
# neither can this. Nothing has hit it yet.
apos_suspect() {   # <file> <line bash blamed> -- nearest comment carrying a bare apostrophe
  awk -v lim="$2" '
    FNR > lim { exit }
    /^[ \t]*#/ {
      line = $0; gsub(/\047"\047"\047/, "@", line)     # the escaped idiom is the correct form
      if (index(line, "\047")) { n = FNR; t = substr(line, 1, 70) }
    }
    END { if (n) printf "    likely cause %s:%d: %s\n", FILENAME, n, t }' "$1"
}
brk=0
for f in "$KIT"/tooling/*.sh "$KIT"/tooling/commit-msg "$KIT"/tests/conformance.sh; do
  [ -f "$f" ] || continue
  err=$(bash -n "$f" 2>&1) && continue
  brk=1
  printf '  %s\n' "$err"
  apos_suspect "$f" "$(printf '%s' "$err" | sed -n 's/.*line \([0-9]*\).*/\1/p' | head -1)"
done
check $brk "every script parses"

# And the diagnosis itself is exercised on a fixture that carries the defect, so the guard is
# not merely green because the tree is clean today.
ap="$WORK.apos"; rm -rf "$ap"; mkdir -p "$ap"
{ printf '#!/usr/bin/env bash\n'
  printf 'echo start\n'
  printf "awk '\n"
  printf '  BEGIN { x = 1 }\n'
  printf "  # the operator's own note -- this apostrophe closes the program\n"
  printf '  { print x }\n'
  printf "' /dev/null\n"
  printf 'echo end\n'; } > "$ap/broken.sh"
( err=$(bash -n "$ap/broken.sh" 2>&1) && exit 1          # must NOT parse
  ln=$(printf '%s' "$err" | sed -n 's/.*line \([0-9]*\).*/\1/p' | head -1)
  apos_suspect "$ap/broken.sh" "$ln" | grep -q ':5:' )   # and line 5 is the apostrophe
check $? "the diagnosis points at the apostrophe, not at where parsing broke"
rm -rf "$ap"

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
# Which legs this platform can actually discriminate on, probed rather than assumed. The
# first version of this step asserted three readers and could only detect one; the other two
# were being cleaned upstream by the platform before the reader under test ever ran, so
# reverting either fix left the step green. Naming what is masked is the difference between a
# test and a claim.
#
#   $(...)  msys2 bash drops a trailing CR in command substitution, and kit_cfg returns its
#           single value through one -- so kit_cfg's own strip is unobservable there. kit_cfg_all
#           writes straight to stdout and is testable everywhere the awk keeps CR.
#   sed     msys2 GNU sed strips CR in text mode, and TIER_RULES is piped through one. So the
#           \r in floorof's trim classes is unreachable from a fixture on this platform: it is
#           defence behind kit_cfg_all's strip, not a separately covered path. Do not assert it.
# `tr -d ' '` on every wc capture. BSD wc pads its count to a column width and GNU wc does
# not, so a bare comparison against a number is true on Linux and false on macOS. Two of
# these shipped today and took the macOS conformance run red while Linux stayed green — the
# first platform-specific defect this suite has caught in its own test code rather than in
# the kit.
subst_cr=$(v=$(printf 'x\r\n'); printf '%s' "$v" | wc -c | tr -d ' ')
[ "$subst_cr" = 2 ] && substleg="exercised" || substleg="masked by \$(...) on this shell"
printf '  kit_cfg leg:  %s\n' "$substleg"
if [ "$awkmode" = "NOT EXERCISED" ]; then
  skip "this awk strips CR on input and cannot be made to keep it" \
       "CRLF input yields the same values as LF"
else
  ( cd "$cx"
    [ -x shim/awk ] && PATH="$PWD/shim:$PATH" && export PATH
    git init -q -b main 2>/dev/null
    printf -- '---\r\npaths.tasks:  .project/tasks\r\npaths.state:  .project\r\ntier.default: T1\r\ntier.rule: src/** T3\r\ntier.rule: lib/** T2\r\n---\r\n' > .claude/project-profile.md
    printf -- '---\r\nid: T-crlf\r\ntitle: c\r\ntier: T1\r\nepic: e1\r\npaths: src/a.go\r\n---\r\n\r\nbody\r\n' > .project/tasks/T-crlf.md

    # LEG 1 -- kit_cfg_all, asserted on its own bytes. It writes to stdout with no command
    # substitution anywhere in the path, so this is the one reader in kit-lib.sh whose strip
    # can be proven on any platform whose awk keeps CR. Two rules so the assertion does not
    # rest on the last line, which a caller's $(...) would clean anyway.
    . "$KIT/tooling/kit-lib.sh"
    kit_cfg_all .claude/project-profile.md tier.rule > rules.out
    [ "$(tr -cd '\r' < rules.out | wc -c | tr -d ' ')" = 0 ] || exit 1

    # LEG 2 -- the indexer's frontmatter parser, end to end. stderr is captured rather than
    # discarded: an awk fatal in this pass leaves kit-index.sh exiting 0 with tasks missing,
    # so a step that throws the diagnostics away cannot see its own fixture half-indexed.
    bash "$KIT/tooling/kit-index.sh" >/dev/null 2>index.err
    [ -s index.err ] && exit 1

    # `sed $'s/\r$//'`, NOT `tr -d '\015'`. The $'...' form is not cosmetic:
    # BSD sed reads a bare \r as a literal `r`, so the shell must expand the byte first. sqlite3 terminates lines with CRLF here, which is
    # why the rest of this file strips CR -- but the artifact under test IS a CR, and deleting
    # every one of them makes `T1<CR>/e1<CR>/T3` compare equal to `T1/e1/T3`. Strip the line
    # terminator only. This was the defect that left four of five one-part reverts green.
    n=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM task;" | sed $'s/\r$//')
    r=$(sqlite3 .project/index.db "SELECT tier||'/'||epic||'/'||COALESCE(tier_floor,'-') FROM task WHERE id='T-crlf';" | sed $'s/\r$//')
    [ "$n" = 1 ] && [ "$r" = "T1/e1/T3" ] )
  check $? "CRLF input yields the same values as LF (kit_cfg_all + frontmatter)"
fi
rm -rf "$cx"

step "a broken tier.rule cannot empty the index, and a lost task file fails closed"
# `globre` left `[`, `]` and `\` unescaped, so `tier.rule: src/[ab T3` compiled to an invalid
# regex and awk took a FATAL mid-pass: three of four tasks vanished, the survivor lost its
# tier and its floor, and kit-index.sh exited 0 having printed the DB path. A typo in a
# documented config field, silently shortening the backlog, in the control that decides how
# many reviewers a change gets.
#
# Two halves, because the fix has two: the rule is refused where TIER_RULES is built (one
# place, so the SQL floor path cannot receive it either), and the task pass now counts the
# files it READ. The count is what catches the general case -- awk exits 0 after skipping an
# argument it could not read, so status alone never notices a task going missing.
gx="$WORK.glob"; rm -rf "$gx"; mkdir -p "$gx/.claude" "$gx/.project/tasks"
( cd "$gx" && git init -q -b main 2>/dev/null
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "tier.default: T1"; echo "tier.rule: src/[ab T3"; echo "tier.rule: src/** T2"
    echo "---"; } > .claude/project-profile.md
  for i in 1 2 3 4; do
    printf -- '---\nid: T-%s\ntitle: t%s\ntier: T3\npaths: src/a.go\n---\nb\n' "$i" "$i" > ".project/tasks/T-$i.md"
  done

  # HALF 1 -- the uncompilable rule is refused by name and the build still completes. The
  # surviving rule must still apply: refusing one rule is not licence to drop the floor.
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>a.err || exit 1
  grep -q 'tier.rule ignored' a.err || exit 1
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM task;' | tr -d '\015')" = 4 ] || exit 1
  [ "$(sqlite3 .project/index.db "SELECT COUNT(*) FROM task WHERE tier_floor='T2';" | tr -d '\015')" = 4 ] || exit 1

  # HALF 1b -- the refusal must survive to the artifact. kit-status.sh runs the indexer with
  # stderr discarded, so a warning that lives only on a terminal reaches nobody, and the file
  # then blames "no declared paths:" for a floor that is missing because a rule was thrown
  # away. Those are different causes and the benign one must not stand in for the other.
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'refused as unusable' STATUS.generated.md || exit 1

  # HALF 2 -- a task file the reader cannot read. A directory named *.md is the portable way
  # to make awk skip an argument while still exiting 0, which is precisely the case a status
  # check misses. The run must fail, NAME the file, and leave the GOOD index alone --
  # yesterday's correct backlog beats today's truncated one.
  mkdir -p .project/tasks/T-lost.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>b.err && exit 1
  grep -q 'not read: .*T-lost.md' b.err || exit 1
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM task;' | tr -d '\015')" = 4 ] || exit 1
  rm -rf .project/tasks/T-lost.md

  # HALF 2b -- and an EMPTY task file is not that. `kit-task.sh` writes a skeleton for a human
  # to fill in, so a zero-byte task file is an ordinary intermediate state; awk fires no rule
  # for it, which is indistinguishable from unreadable to anything counting records. Failing
  # the build on it took the whole derived-state layer down, permanently, from a committed
  # stub. It must be named and skipped, and the build must still succeed.
  : > .project/tasks/T-draft.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>c.err || exit 1
  grep -q 'no content' c.err || exit 1
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM task;' | tr -d '\015')" = 4 ] || exit 1
  rm -f .project/tasks/T-draft.md

  # HALF 3 -- and it recovers. A guard that stays latched after the cause is gone is a guard
  # people work around.
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>/dev/null || exit 1
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM task;' | tr -d '\015')" = 4 ] )
check $? "bad rule refused and recorded, lost file fails closed, empty file does not"
rm -rf "$gx"

step "a failed build leaves the previous index alone and keeps saying so"
# Two halves of one defect. `fl` was the only value on the task INSERT not passed through
# q(), so `tier.rule: src/** T3','x` ended the SQL literal early: the statement failed, the
# surrounding transaction still committed, and every task landed with tier NULL. Then the
# half-written DB was newer than every source, so the next --if-stale run -- the one that
# fires at session start -- declared it fresh and said nothing. One announcement, then silence,
# over a backlog with no tiers.
ax="$WORK.apos"; rm -rf "$ax"; mkdir -p "$ax/.claude" "$ax/.project/tasks"
( cd "$ax" && git init -q -b main 2>/dev/null
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
    echo "tier.rule: src/** T3','x"; echo "---"; } > .claude/project-profile.md
  # After the profile, so kit-init leaves it alone — it is here for the .gitignore entries the
  # last assertions check, which is the same writer a real adopting repository gets.
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---\nid: T-1\ntitle: t\ntier: T1\npaths: src/a.go\n---\nb\n' > .project/tasks/T-1.md

  # HALF 1 -- an apostrophe in a profile value cannot reach the SQL. It is refused as a
  # non-tier before it gets there, and the build completes with the tier column intact.
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>a.err || exit 1
  grep -q 'is not a tier' a.err || exit 1
  [ "$(sqlite3 .project/index.db "SELECT tier FROM task WHERE id='T-1';" | tr -d '\015')" = T1 ] || exit 1

  # HALF 1b -- the bypass that made the first version of that refusal worthless. It read the
  # LAST whitespace field as the tier while the splitter downstream cut at the FIRST, so a
  # three-field rule passed validation on its trailing `T3` and handed `',x T3` to the
  # consumers as a floor. That sorts below every real tier, so `tier < tier_floor` never fired
  # and the under-tiered task simply stopped being reported -- exit 0, nothing refused, the
  # whole below-floor section gone from the status file. The load-bearing assertion is the
  # LAST one: refusing the rule is only worth anything if a genuine floor still reports.
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
    echo "tier.rule: src/** ',x T3"; echo "---"; } > .claude/project-profile.md
  printf -- '---\nid: T-under\ntitle: u\ntier: T0\npaths: src/a.go\n---\nb\n' > .project/tasks/T-under.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>d.err || exit 1
  grep -q 'expected <path-glob> <tier>' d.err || exit 1
  [ -z "$(sqlite3 .project/index.db "SELECT tier_floor FROM task WHERE id='T-under';" | tr -d '\015')" ] || exit 1
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
    echo "tier.rule: src/** T3"; echo "---"; } > .claude/project-profile.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>/dev/null || exit 1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'Below their tier floor' STATUS.generated.md || exit 1
  rm -f .project/tasks/T-under.md

  # HALF 2 -- a statement that fails MID-EXECUTION must not leave a corpse. An extra ingest
  # adapter emitting invalid SQL is the reachable way to produce one. The good index must
  # survive untouched, and -- the part that made this dangerous -- the NEXT run must still
  # fail rather than mistaking a newer mtime for a fresh index.
  # The adapter is declared FIRST and the index rebuilt while it is still harmless, so that
  # when it turns bad no watched file is touched. Otherwise --if-stale sees a newer profile
  # and rebuilds for that reason, and the assertion below passes on the fixture rather than on
  # the fix: an ingest.extra adapter is in neither the mtime WATCH list nor the fingerprint
  # loop, so its failure is exactly the one that used to go quiet after announcing itself once.
  printf '#!/usr/bin/env bash\nexit 0\n' > .claude/bad.sh
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
    echo "ingest.extra: .claude/bad.sh"; echo "---"; } > .claude/project-profile.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>/dev/null || exit 1
  printf '#!/usr/bin/env bash\n[ "$1" = emit ] && echo "INSERT INTO nosuchtable VALUES(1);"\nexit 0\n' > .claude/bad.sh
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>b.err && exit 1
  grep -q 'left unchanged' b.err || exit 1
  [ "$(sqlite3 .project/index.db "SELECT tier FROM task WHERE id='T-1';" | tr -d '\015')" = T1 ] || exit 1
  [ -e .project/index.db.new ] && exit 1                      # no half-built file left behind
  bash "$KIT/tooling/kit-index.sh" --if-stale >/dev/null 2>c.err && exit 1
  grep -q 'index build failed' c.err || exit 1
  # And the temp file and the failure marker are both ignored, so a kill that outruns the
  # trap cannot leave a derived database staged by the next `git add -A`.
  git check-ignore -q .project/index.db.new || exit 1
  git check-ignore -q .project/index.db.failed || exit 1

  # HALF 3 -- and it recovers, with the index rebuilt rather than merely left alone.
  rm -f .claude/bad.sh
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "tier.default: T1"; echo "---"; } > .claude/project-profile.md
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>/dev/null || exit 1
  [ "$(sqlite3 .project/index.db "SELECT tier FROM task WHERE id='T-1';" | tr -d '\015')" = T1 ] )
check $? "apostrophe refused before the SQL, failed build preserves the index and stays loud"
rm -rf "$ax"

step "the two floor sources agree on a non-ASCII path, and ? is refused"
# A tier floor is derived twice and the two derivations must agree. `globre` turns the glob
# into an awk regex for the DECLARED-paths source; the same glob goes to SQLite GLOB for the
# TOUCHED-files source. Two ways they diverged on a non-ASCII name, both measured:
#
#   `?` -> regex `.`, one BYTE here, where GLOB's `?` is one CHARACTER. src/?.go matched
#         src/é.go on the SQL side and not on the awk side. Refused now rather than fixed:
#         a byte-correct one-character matcher needs hex escapes inside an awk program, and
#         macOS ships an awk that does not interpret them.
#   git   renders any path above 0x7F as `"src/\303\251.go"` by default, so the touches edge
#         was recorded under a name matching no glob at all -- the touched-files floor simply
#         never applied. Fixed with core.quotepath=false, which is the load-bearing half.
#
# The test name uses a character with NO canonical decomposition, so macOS NFD/NFC cannot
# fail this for an unrelated reason.
nx="$WORK.nonascii"; rm -rf "$nx"; mkdir -p "$nx/.claude" "$nx/.project/tasks" "$nx/src"
if ( cd "$nx" && printf 'x\n' > "src/ß.go" && [ -f "src/ß.go" ] ) 2>/dev/null; then
  ( cd "$nx" && git init -q -b main 2>/dev/null
    git config user.email a@b.c; git config user.name T
    # hub_pct 100 so nothing is filtered as a hub: with the default 20 and a two-commit
    # fixture the threshold is 0.4, every file is a hub, and the cochange table comes out
    # EMPTY -- which would make the co-change assertion below pass against anything.
    { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
      echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
      echo "cochange.hub_pct: 100"; echo "tier.rule: src/** T3"; echo "---"; } > .claude/project-profile.md
    printf -- '---\nid: T-decl\ntitle: d\ntier: T1\npaths: src/ß.go\n---\nb\n' > .project/tasks/T-decl.md
    printf -- '---\nid: T-touch\ntitle: t\ntier: T1\n---\nb\n' > .project/tasks/T-touch.md
    git add -A && git commit -q --no-verify -m "chore: seed"
    # Two files in ONE commit, so the pair produces a co-change row. The flag was added to
    # BOTH git invocations and only the touches one was covered; a mangled name here splits
    # one file into two nodes and nothing noticed.
    printf 'y\n' > "src/ß.go"; printf 'y\n' > src/plain.go; git add -A
    git commit -q --no-verify -m "feat: w

Task-Id: T-touch
Tier: T1"
    bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
    # The co-change pass, asserted on the real name. Reverting core.quotepath on that
    # invocation alone leaves the touches assertions below green, which is how it shipped
    # untested the first time.
    [ "$(sqlite3 .project/index.db "SELECT COUNT(*) FROM cochange WHERE src='f:src/ß.go' OR dst='f:src/ß.go';" | sed $'s/\r$//')" -ge 1 ] || exit 1

    # The assertion with teeth: the SAME file, reached by the two different sources, must
    # produce the same floor. Before core.quotepath=false the declared side said T3 and the
    # touched side said nothing at all.
    d=$(sqlite3 .project/index.db "SELECT COALESCE(tier_floor,'-') FROM task WHERE id='T-decl';" | sed $'s/\r$//')
    t=$(sqlite3 .project/index.db "SELECT COALESCE(tier_floor,'-') FROM task WHERE id='T-touch';" | sed $'s/\r$//')
    [ "$d" = T3 ] && [ "$t" = T3 ] || exit 1
    # And the file is recorded under its own name, not an octal-escaped one.
    sqlite3 .project/index.db "SELECT id FROM node WHERE type='file';" | sed $'s/\r$//' | grep -qxF 'f:src/ß.go' || exit 1

    # A path git will ONLY report escaped -- one containing a backslash, a quote or a control
    # byte -- is not healed by core.quotepath=false, which covers bytes above 0x7F and nothing
    # else. Measured: `src/i\j.go` still arrives as `"src/i\\j.go"`, and recording that as a
    # node gave a file matching no rule and a floor that silently did not apply. It must be
    # DROPPED and COUNTED, and the count must reach the status file.
    #
    # Built through nested tree objects because git refuses such a name in a worktree on
    # Windows; the object database takes it, which is also how it would arrive from a POSIX
    # checkout where the name is perfectly legal.
    bl=$(printf 'z\n' | git hash-object -w --stdin)
    st=$(printf '100644 blob %s\ti\\j.go\n' "$bl" | git mktree)
    rt=$( { git ls-tree HEAD^{tree}; printf '040000 tree %s\tsrcq\n' "$st"; } | git mktree )
    cq=$(git commit-tree "$rt" -p HEAD -m "feat: q

Task-Id: T-touch
Tier: T1")
    git update-ref refs/heads/main "$cq"
    bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
    [ "$(sqlite3 .project/index.db "SELECT COUNT(*) FROM node WHERE id LIKE '%j.go%';" | sed $'s/\r$//')" = 0 ] || exit 1
    [ "$(sqlite3 .project/index.db "SELECT value FROM meta WHERE key='paths_unusable';" | sed $'s/\r$//')" = 1 ] || exit 1
    bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
    grep -q 'could not be indexed' STATUS.generated.md || exit 1

    # `?` is refused by name, and refusing it does not take the build down.
    { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
      echo "tier.default: T1"; echo "tier.rule: src/?.go T3"; echo "---"; } > .claude/project-profile.md
    bash "$KIT/tooling/kit-index.sh" >/dev/null 2>q.err || exit 1
    grep -q '? is not supported in a glob' q.err || exit 1 )
  check $? "same floor from both sources on a non-ASCII path; ? refused by name"
else
  skip "this filesystem would not take a non-ASCII filename" \
       "same floor from both sources on a non-ASCII path"
fi
rm -rf "$nx"

step "provenance is recorded, defaulted and split out of the rate it would dilute"
# Escape rate was computed over EVERY task regardless of whether this pipeline had ever run on
# one. On a brownfield adoption most of the backlog is pre-existing or hand-done, so the
# denominator filled with work the kit never reviewed and the headline metric was diluted from
# the first day -- in the direction that makes tiering look ineffective.
#
# Four things have to hold together, and the last is the one with teeth: a bogus value must
# not be stored, an unrecorded task must be `unknown` rather than quietly counted, the trailer
# must beat the frontmatter the way tier already does, and the rate must report the kit-run
# population SEPARATELY while NAMING the rest by value.
vx="$WORK.via"; rm -rf "$vx"; mkdir -p "$vx/.claude" "$vx/.project/tasks" "$vx/src"
( cd "$vx" && git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"; echo "---"; } > .claude/project-profile.md
  printf -- '---\nid: T-kit\ntitle: k\ntier: T2\nvia: kit\n---\nb\n'   > .project/tasks/T-kit.md
  printf -- '---\nid: T-man\ntitle: m\ntier: T2\nvia: manual\n---\nb\n' > .project/tasks/T-man.md
  printf -- '---\nid: T-none\ntitle: n\ntier: T2\n---\nb\n'             > .project/tasks/T-none.md
  printf -- '---\nid: T-bad\ntitle: b\ntier: T2\nvia: made-up\n---\nb\n' > .project/tasks/T-bad.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-man
Tier: T2
Via: agent"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  # frontmatter honoured; a value outside the vocabulary becomes unknown rather than stored;
  # absence becomes unknown; and the TRAILER beats the frontmatter, as tier does -- T-man
  # declares `manual` in its file and the commit says `agent`.
  got=$(sqlite3 .project/index.db "SELECT group_concat(id||'='||via,' ') FROM (SELECT id,via FROM task ORDER BY id);" | sed $'s/\r$//')
  [ "$got" = "T-bad=unknown T-kit=kit T-man=agent T-none=unknown" ] || exit 1

  # The rate reports the kit-run population beside the whole one, and names the rest by value
  # WITH its escape count. `unknown` must appear as itself -- folding it into `manual` would
  # turn "nobody recorded this" into a claim. One of the four tasks is `kit`; all four are T2.
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -qE '^- T2 +0 / 1 via:kit +0 / 4 all$' STATUS.generated.md || exit 1
  grep -q 'Other provenance' STATUS.generated.md || exit 1
  grep -qE '^- unknown +2 task\(s\), 0 escape\(s\)$' STATUS.generated.md || exit 1
  grep -qE '^- agent +1 task\(s\), 0 escape\(s\)$' STATUS.generated.md || exit 1

  # The trailer validator rejects a value outside the vocabulary and accepts one inside it.
  printf 'feat: x\n\nTask-Id: T-kit\nTier: T2\nVia: made-up\n' > m.txt
  bash "$KIT/tooling/kit-trailers.sh" message m.txt 2>&1 | grep -q 'invalid  Via' || exit 1
  printf 'feat: x\n\nTask-Id: T-kit\nTier: T2\nVia: kit\n' > m2.txt
  [ -z "$(bash "$KIT/tooling/kit-trailers.sh" message m2.txt 2>&1)" ] || exit 1 )
check $? "via: vocabulary honoured, unknown by default, trailer wins, rate splits and names"
rm -rf "$vx"

step "a recorded escape cannot be filtered out of the report"
# The failure this exists to make impossible: an escape is recorded, the task is then moved out
# of `via='kit'`, and the metric reads clean while the database says otherwise. It is not
# hypothetical -- one documented command wrote the column and dropped a task carrying a
# recorded escape out of the report entirely, and a later `chore:` commit carrying
# `Via: manual` can still relabel a task with nothing warning that the population changed.
#
# So the relabel is performed here on purpose and the escape must survive it. The `via:kit`
# column is ALLOWED to drop the task -- that is the column's job. The `all` column and the
# provenance breakdown are not.
ex="$WORK.esc"; rm -rf "$ex"; mkdir -p "$ex/.claude" "$ex/.project/tasks" "$ex/src"
( cd "$ex" && git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"; echo "---"; } > .claude/project-profile.md
  printf -- '---\nid: T-esc\ntitle: e\ntier: T2\n---\nb\n' > .project/tasks/T-esc.md
  printf -- '---\nid: T-fix\ntitle: f\ntier: T2\n---\nb\n' > .project/tasks/T-fix.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-esc
Tier: T2
Via: kit"
  echo y > src/b; git add -A
  git commit -q --no-verify -m "fix: repair

Task-Id: T-fix
Tier: T2
Via: kit
Fixes-Escape-Of: T-esc"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  # While both tasks are kit-run the two columns agree, which is the uninteresting case.
  grep -qE '^- T2 +1 / 2 via:kit +1 / 2 all$' STATUS.generated.md || exit 1

  # Relabel the ESCAPED task out of the measured population. Nothing else changes.
  git commit -q --allow-empty --no-verify -m "chore: retag

Task-Id: T-esc
Tier: T2
Via: manual"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  sqlite3 .project/index.db "SELECT via FROM task WHERE id='T-esc';" | sed $'s/\r$//' | grep -qx manual || exit 1

  # The escape left the kit column and stayed in the report.
  grep -qE '^- T2 +0 / 1 via:kit +1 / 2 all$' STATUS.generated.md || exit 1
  grep -qE '^- manual +1 task\(s\), 1 escape\(s\)$' STATUS.generated.md || exit 1

  # And the general claim, executed rather than argued: the escapes the report shows sum to the
  # escapes the database holds. A report that can read zero while the database cannot is the
  # thing being ruled out, so it is asserted as an identity and not as a spot check.
  dbesc=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE kind='escaped';" | sed $'s/\r$//' | tr -d ' ')
  shown=$(grep -oE '[0-9]+ / [0-9]+ all' STATUS.generated.md | awk '{s+=$1} END{print s+0}')
  [ "$dbesc" = 1 ] || exit 1
  [ "$shown" = "$dbesc" ] || exit 1

  # The residue, covered directly because it cannot be reached through the front door. Every id
  # in a trailer -- `Fixes-Escape-Of:` included -- currently gets a task row invented for it, so
  # an escape belonging to no task is unreachable while that phantom behaviour stands. It is a
  # filed defect and removing it makes this the only thing standing between a real escape and
  # silence, so the row is seeded straight into the index and the report is made to say it.
  #
  # The index is derived and disposable, which is what makes writing to it legitimate here: the
  # unit under test is kit-status.sh reading a state kit-index.sh does not yet produce.
  sqlite3 .project/index.db "INSERT INTO event(task_id,kind,at) VALUES('T-vanished','escaped','2026-01-01T00:00:00Z');"
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'belong to no task in this index' STATUS.generated.md || exit 1

  # The identity that actually holds, and the one the two columns plus the residue are built to
  # satisfy: everything stored is somewhere in the report. Asserting `shown = stored` instead
  # would have been true only by the accident of there being no residue.
  dbesc=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE kind='escaped';" | sed $'s/\r$//' | tr -d ' ')
  shown=$(grep -oE '[0-9]+ / [0-9]+ all' STATUS.generated.md | awk '{s+=$1} END{print s+0}')
  orph=$(grep -oE '\*\*[0-9]+ recorded escape' STATUS.generated.md | tr -dc '0-9')
  [ "$dbesc" = 2 ] || exit 1
  [ $((shown + ${orph:-0})) = "$dbesc" ] || exit 1 )
check $? "escape survives a relabel out of via:kit; nothing stored is missing from the report"
rm -rf "$ex"

step "the via vocabulary is defined in exactly one place"
# The finding vocabulary was restated in four locations once, and the agents then emitted
# values the recorder threw away. This one has a single definition in kit-lib.sh and every
# consumer reads it from there; a literal copy anywhere else is the drift starting again.
#
# The pattern comes from the definition rather than being typed here. Spelling it out would
# have made this file the second copy -- which it was, on the first run, and the check caught
# itself. A test that cannot be written without violating the rule it enforces is telling you
# something about the rule; here it just meant: ask the source.
( . "$KIT/tooling/kit-lib.sh"
  VOCAB=$(kit_via_vocab)
  copies=$(grep -rlF "$VOCAB" "$KIT/tooling" "$KIT/tests" 2>/dev/null | wc -l | tr -d ' ')
  [ "$copies" = 1 ] || { echo "  '$VOCAB' appears in $copies file(s), expected 1:"
                         grep -rlF "$VOCAB" "$KIT/tooling" "$KIT/tests" 2>/dev/null | sed 's/^/    /'; }
  [ "$copies" = 1 ] )
check $? "one definition of the via vocabulary, read by every consumer"

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
# Moved TWICE on 2026-08-08, each time deliberately and each time with the cause
# established BEFORE re-pinning -- exactly one blob differing between the old and new seed
# trees, and that difference being exactly the intended edit. That is the work this check
# exists to force, and both times it forced it.
#   1. kit-init.sh writes `.project/index.db*` rather than `.project/index.db`, because the
#      indexer builds into `index.db.new` and marks a failed build with `index.db.failed`.
#   2. templates/project-profile.md now documents which tier.rule globs are refused, and
#      kit-init.sh copies that template into the fixture's first commit.
EXPECT_HEAD=ff40e675370db48da64177309438fdae84eca5ec
# The seed alone, so a mismatch says WHICH half moved: seed intact means this script changed,
# seed moved means a file kit-init.sh commits did.
EXPECT_SEED=df86de1fe6afabc9ae1b501764f9341bd55c1dd0

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

printf '\n=== %d passed, %d failed' "$ok" "$bad"
[ "$skipped" -gt 0 ] && printf ', %d NOT EXERCISED on this platform' "$skipped"
printf '\n'
exit $bad
