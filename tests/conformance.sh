#!/usr/bin/env bash
# Cross-platform conformance run.
#
#   KIT=/path/to/kit WORK=/path/to/empty/scratch bash tests/conformance.sh
#   ... bash tests/conformance.sh --only 'escape'      one step, in seconds
#   ... bash tests/conformance.sh --list               the step names to match on
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

# --- step selection --------------------------------------------------------
# `--only PATTERN` (repeatable, case-insensitive ERE, OR-ed) runs just the steps
# whose names match. It exists to make ONE mutation proof cheap: proving a single
# control can fail is the discipline this suite is for, and paying a whole run for
# it got that discipline batched into overnight runs instead of used.
#
# The full run is the only thing that proves conformance, and it is what CI runs.
# A filtered run is therefore built to be impossible to mistake for a whole one:
# the tally says PARTIAL and names how many steps did not run, the fingerprint is
# labelled as covering the chain rather than the suite, and a pattern matching no
# step exits 2 instead of reporting a clean zero-step pass. "Nothing ran" reading
# as green is the exact defect shape this repository keeps shipping -- see
# docs/LESSONS.md S1.
#
# Steps are not all independent. Most build and destroy their own fixture, but two
# groups share one, and those carry a chain name as `step`'s second argument.
# Selecting a chain member runs that chain from its start through the selected
# step, and says so. No step ever runs without the fixture it reads.
# Absolute, because a step below re-invokes this file to check the filter's own
# guarantees, and by then the fixture steps may have changed directory.
SELF=${BASH_SOURCE[0]:-$0}
SELF=$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")
ONLY=''; LIST=0
add_only() { if [ -z "$ONLY" ]; then ONLY=$1; else ONLY="$ONLY|$1"; fi; }
while [ $# -gt 0 ]; do
  case $1 in
    --only)   [ $# -ge 2 ] || { printf 'conformance: --only needs a pattern\n' >&2; exit 2; }
              add_only "$2"; shift 2 ;;
    --only=*) add_only "${1#--only=}"; shift ;;
    --list)   LIST=1; shift ;;
    -h|--help)
      printf 'usage: KIT=<kit> WORK=<scratch> bash %s [--only PATTERN]... [--list]\n' "$SELF"
      exit 0 ;;
    *) printf 'conformance: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

# The step list is read back out of this file rather than kept in a table beside it.
# A second copy is a copy that drifts, and this repository has already paid for that
# once with the finding vocabulary.
STEP_TABLE=$(
  sed -n 's/^if step "\([^"]*\)"\(.*\); then$/\1|\2/p' "$SELF" |
  { n=0; while IFS='|' read -r _nm _ch; do
      n=$((n+1))
      printf '%s|%s|%s\n' "$n" "$_nm" "$(printf '%s' "$_ch" | tr -d '[:space:]')"
    done; }
)
STEP_COUNT=$(printf '%s\n' "$STEP_TABLE" | grep -c '^[0-9]')
# The parser is checked against a looser count of the same lines. A step written in a
# shape the strict pattern misses would otherwise vanish from the table silently: it
# would still RUN on a full run, but `--only` could never name it and the "N of M"
# figure above would be wrong. Counting zero is the same defect at full size.
STEP_DECLARED=$(grep -c '^if step ' "$SELF")
if [ "${STEP_COUNT:-0}" -eq 0 ] || [ "$STEP_COUNT" != "$STEP_DECLARED" ]; then
  printf 'conformance: internal error -- the step self-parser read %s of %s step lines in %s.\n' \
    "${STEP_COUNT:-0}" "$STEP_DECLARED" "$SELF" >&2
  printf '  Steps must be written exactly `if step "name" [chain]; then` ... `fi`.\n' >&2
  exit 2
fi
# Selection is by name and de-duplicated by name, so two steps sharing one would be
# announced as a single step and could never be told apart by `--only`. They are unique
# today; this is what keeps that true rather than assumed.
STEP_UNIQUE=$(printf '%s\n' "$STEP_TABLE" | cut -d'|' -f2 | sort -u | grep -c '^.')
if [ "$STEP_UNIQUE" != "$STEP_COUNT" ]; then
  printf 'conformance: internal error -- %s step names for %s steps; these are duplicated:\n' \
    "$STEP_UNIQUE" "$STEP_COUNT" >&2
  printf '%s\n' "$STEP_TABLE" | cut -d'|' -f2 | sort | uniq -d | sed 's/^/  /' >&2
  exit 2
fi

if [ "$LIST" = 1 ]; then
  printf '%s\n' "$STEP_TABLE" | while IFS='|' read -r _i _nm _ch; do
    if [ -n "$_ch" ]; then printf '%3s  %s  [chain: %s]\n' "$_i" "$_nm" "$_ch"
    else                   printf '%3s  %s\n' "$_i" "$_nm"; fi
  done
  exit 0
fi

KIT=${KIT:?set KIT to the kit checkout}
WORK=${WORK:?set WORK to an empty scratch dir}

SELECTED=''; PULLED=0
if [ -n "$ONLY" ]; then
  _hit=$(printf '%s\n' "$STEP_TABLE" | while IFS='|' read -r _i _nm _ch; do
           printf '%s' "$_nm" | grep -Eiq -- "$ONLY" && printf '%s|%s|%s\n' "$_i" "$_nm" "$_ch"
         done)
  if [ -z "$_hit" ]; then
    printf 'conformance: --only %s matched no step, so nothing would run.\n' "$ONLY" >&2
    printf '  A run of zero steps is not a pass. `--list` shows the names.\n' >&2
    exit 2
  fi
  SELECTED=$(printf '%s\n' "$_hit" | cut -d'|' -f2)
  # Pull in each selected step's chain, from the chain's start up to that step.
  for _c in $(printf '%s\n' "$_hit" | cut -d'|' -f3 | grep -v '^$' | sort -u); do
    _max=$(printf '%s\n' "$_hit" |
           while IFS='|' read -r _i _nm _ch; do [ "$_ch" = "$_c" ] && printf '%s\n' "$_i"; done |
           sort -n | tail -1)
    _pre=$(printf '%s\n' "$STEP_TABLE" |
           while IFS='|' read -r _i _nm _ch; do
             [ "$_ch" = "$_c" ] && [ "$_i" -le "$_max" ] && printf '%s\n' "$_nm"
           done)
    SELECTED=$(printf '%s\n%s' "$SELECTED" "$_pre")
  done
  SELECTED=$(printf '%s\n' "$SELECTED" | grep -v '^$' | sort -u)
  _nsel=$(printf '%s\n' "$SELECTED" | grep -c '^.')
  PULLED=$((_nsel - $(printf '%s\n' "$_hit" | grep -c '^.')))
  printf '=== FILTERED RUN --only %s\n' "$ONLY"
  printf '    %s of %s steps will run' "$_nsel" "$STEP_COUNT"
  [ "$PULLED" -gt 0 ] && printf ', %s of them pulled in to build a shared fixture' "$PULLED"
  printf '.\n'
fi

ok=0; bad=0; skipped=0; ran=0; filtered=0
step_selected() { [ -z "$ONLY" ] || printf '%s\n' "$SELECTED" | grep -qxF -- "$1"; }
step() {
  if step_selected "$1"; then ran=$((ran+1)); printf '\n=== %s\n' "$1"; return 0; fi
  filtered=$((filtered+1)); return 1
}
check() { if [ "$1" = 0 ]; then ok=$((ok+1)); printf '  PASS  %s\n' "$2"
          else bad=$((bad+1)); printf '  FAIL  %s\n' "$2"; fi; }
# A control that could not run is not a control that passed. It does not fail the suite --
# an unrunnable check is not a defect -- but it is counted and named in the tally, because
# the tally and the exit code are what CI reads and "N passed, 0 failed" over a check that
# never executed is the same green-that-means-nothing this suite exists to refuse.
skip()  { skipped=$((skipped+1)); printf '  SKIP  %s — %s\n' "$2" "$1"; }

if step "environment"; then
uname -srm 2>/dev/null || echo "(no uname)"
bash --version | head -1; git --version; sqlite3 --version | awk '{print "sqlite3 "$1}'
(awk --version 2>/dev/null || awk -W version 2>&1) | head -1
fi

if step "scripts are executable in the git index"; then
# Not on disk: git on Windows cannot read the msys exec bit, so a chmod there never reaches
# the index and the file lands non-executable on Linux. The index is the shared truth.
#
# THE SELECTOR MUST MATCH CI'S, and it did not. This loop filtered to `.sh$|commit-msg`, while
# the workflow's "Exec bits survive a fresh clone" step checks EVERYTHING under tooling/ except
# schema.sql. So `kit_findings.py` landed at 100644 on 2026-08-10 and CI went red for EIGHT
# consecutive commits while this step stayed green -- a local gate weaker than the remote one
# is a local gate that certifies nothing.
#
# Selected the same way CI selects: anything tracked under tooling/ or templates/*.sh, minus a
# named exception list. A file that genuinely should not be executable is added HERE, visibly,
# rather than by narrowing the pattern until it stops complaining.
nx=0
for f in $(git -C "$KIT" ls-files tooling 'templates/*.sh'); do
  case "$f" in
    tooling/schema.sql) continue ;;   # data, never executed
  esac
  m=$(git -C "$KIT" ls-files -s "$f" | awk '{print $1}')
  [ "$m" = 100755 ] || { echo "  $m $f"; nx=1; }
done
check $nx "every script is 100755, by CI's own selector"
fi

if step "finding vocabulary has not drifted"; then
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
fi

if step "no agent is told to run a tool it does not have"; then
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

# The same shape for Write, and it is here because the Bash-only version above missed a live
# defect for months. `researcher.md` is granted Read, Grep, Glob, WebFetch, WebSearch and its
# Output section told it to WRITE a document to a directory. A design was built on the
# assumption that researcher could produce its own artefact, an approach review killed that
# design on exactly this point, and this step -- which exists to catch an agent told to use a
# tool it does not have -- said nothing, because it only ever looked for Bash.
#
# The matcher has to be narrower than "mentions write". Three lines in the no-Write agents
# talk about writes without instructing one: approach-reviewer and security-reviewer discuss
# check-then-act races ("separated from its write by an await"), and researcher says "Do not
# write the decision record". So a line must name write/create/save AND a file-ish object
# (a directory, a path, a .md) AND not be a prohibition. A prohibition that trips this check
# would train the next author to delete the prohibition, which is the wrong repair.
#
# KNOWN LIMIT, found by this check firing on its own fix: it matches TEXT, so prose that
# quotes the forbidden shape trips it. The sentence in researcher.md explaining what the old
# instruction said had to be reworded to stop describing the defect in the defect's own words.
# That is a real cost and it is stated rather than hidden, because the next author will hit it
# and the wrong repair is to weaken the matcher. `T-20260809-lint-the-kit-for-untrusted-text-interpol`
# is the same class one level up.
ungrantedw=0
for a in "$KIT"/agents/*.md; do
  tools=$(tr -d '\r' < "$a" | sed -n 's/^tools:[[:space:]]*//p' | head -1)
  case "$tools" in *Write*|*Edit*) continue ;; esac
  hit=$(tr -d '\r' < "$a" |
        grep -inE '(write|writes|create|save)[^.]*(director|\.md|file path|to a file)' |
        grep -viE 'do not|does not|never |rather than|instead of|without ' |
        grep -viE '(the )?(caller|orchestrator|operator|human)[^.]*(write|save|create)' | head -1)
  if [ -n "$hit" ]; then
    echo "  $(basename "$a") has no Write but is told to produce a file: ${hit%%:*}"
    ungrantedw=1
  fi
done
check $ungrantedw "no Write-less agent is instructed to produce a file"
fi

if step "a script broken by an apostrophe names the apostrophe"; then
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
fi

if step "a domain outside the declared industries is dropped, not stored"; then
# An unknown class is rejected loudly. A wrong domain was accepted SILENTLY and polluted the
# industry accelerator it feeds -- reviewers put the finding's subject there (`caching`,
# `cache-adapter-design`) because nothing said what a domain was. The `pattern` axis is where
# that belongs now, and a domain the project never declared must not survive.
step_dir="$WORK.dom"; rm -rf "$step_dir"; mkdir -p "$step_dir/.claude" "$step_dir/.project"
( cd "$step_dir" || exit 1
  git init -q -b main 2>/dev/null
  printf -- '---
paths.state: .project
accelerator.industry: .claude/bfsi.md
---
' > .claude/project-profile.md
  : > .claude/bfsi.md
  printf '%s' '{"findings":[{"class":"fail-open","severity":"major","lang":"go","pattern":"cache-port","domain":"not-an-industry","summary":"a domain that no project declared must be dropped"}]}' \
    | bash "$KIT/tooling/kit-finding.sh" --task T --agent a --json >/dev/null 2>&1
  grep -q '"domain":""' .project/events.ndjson && grep -q '"pattern":"cache-port"' .project/events.ndjson )
check $? "undeclared domain dropped, pattern retained"
rm -rf "$step_dir"
fi

if step "a trivial commit still has its trailers checked"; then
# git.trivial_pattern means trailers are not REQUIRED, not that they are not CHECKED. The
# early return let a `docs:` commit carry a typo'd Task-Id, which then indexed as a titleless
# phantom task -- and a pushed commit message cannot be corrected.
tx="$WORK.exempt"; rm -rf "$tx"; mkdir -p "$tx"
( cd "$tx" || exit 1
  git init -q -b main 2>/dev/null
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
fi

if step "pre-push blocks a wrong trailer while it can still be amended"; then
# commit-msg is skippable and absent for anyone who never ran kit-init; CI catches correctly
# but only after the push, when a commit message can no longer be changed. This repository
# carries a permanent phantom task from exactly that gap.
pp="$WORK.push"; rm -rf "$pp"; mkdir -p "$pp/remote" "$pp/work"
( cd "$pp/remote" || exit 1
  git init -q --bare -b main 2>/dev/null
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
fi

if step "spend is measured per agent, from that agent's own transcript" spend; then
# The defect this replaced: every SubagentStop received the SESSION transcript, which holds
# no subagent records at all, so each row was main-loop cost wearing an agent's name. The
# fixture therefore puts DIFFERENT numbers in the two transcripts -- a reader that fell back
# to the session file would produce the main loop's figures under the agent's label, and pass
# a test that only counted rows.
#
# Totals are cumulative per transcript, so recording twice must not double the cost, and
# Stop's sweep must not re-record what SubagentStop already wrote.
sx="$WORK.spend"; rm -rf "$sx"; mkdir -p "$sx/src" "$sx/sess/subagents"
( cd "$sx" || exit 1
  git init -q -b main 2>/dev/null
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
fi

if step "a reviewer's findings reach the table, and an unrecorded review is visible"; then
# The defect: reviewers emitted correctly formatted blocks and NOTHING consumed them. A real
# project that had run a T2 and a T3 review held zero finding rows, and every escape-rate number
# in the README was computed from that empty table -- `T3 0/13` reading as "nothing escaped"
# while meaning "nothing was recorded".
#
# This step used to exercise a hook that scraped those blocks out of a transcript. That
# component is DELETED, not repaired (docs/LESSONS.md S5): the reviewer returns structured data
# and the orchestrator records it, so there is no parser left to defend. What survives from the
# old step is everything that was never about scraping -- attribution after the fact, tier
# resolution, and the requirement that a review recording nothing SAYS so.
fl="$WORK.floop"; rm -rf "$fl"; mkdir -p "$fl/src"
( cd "$fl" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---
id: T-r
title: r
tier: T2
---
b
' > .project/tasks/T-r.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }
  F="$KIT/tooling/kit-finding.sh"

  # A reviewer that cannot know its task says so, rather than having one guessed for it.
  printf '%s' '{"findings":[{"class":"fail-open","severity":"major","lang":"sql","summary":"the first of two recorded before any task transition"},{"class":"correctness","severity":"minor","lang":"bash","summary":"the second of two recorded before any task transition"}]}' \
    | bash "$F" --unattributed --agent security-reviewer --json >/dev/null 2>&1

  # A review that found nothing is a MEASUREMENT and must survive as one. Silence here is what
  # let an empty table read as a clean record.
  printf '%s' '{"findings":[]}' | bash "$F" --unattributed --agent tester --json >/dev/null 2>&1
  grep -q '"kind":"finding-gap"' .project/events.ndjson || exit 1

  bash "$KIT/tooling/kit-index.sh"  >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  [ "$(Q "SELECT COUNT(*) FROM finding WHERE task_id IS NULL OR task_id='';")" = 2 ] || exit 1
  grep -q 'finding(s) unattributed' STATUS.generated.md || exit 1

  # The task then commits, and the same heuristic that binds spend binds these -- including the
  # tier, without which escape-rate-by-tier reports every finding as untiered.
  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-r
Tier: T2
Task-Status: progress"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  [ "$(Q "SELECT COUNT(*) FROM finding WHERE task_id='T-r' AND tier='T2';")" = 2 ] || exit 1
  # And the summary survived the whole trip, which is the column that makes a row readable.
  [ "$(Q "SELECT COUNT(*) FROM finding WHERE task_id='T-r' AND summary LIKE '%recorded before any task transition%';")" = 2 ] )
check $? "an empty review is recorded as a gap, and attribution and tier follow the task"
rm -rf "$fl"
fi
if step "a subagent whose transcript cannot be found is reported, not costed" spend; then
# The alternative -- writing the row anyway from whatever transcript is at hand -- is the
# defect. Nothing is recorded, and the fact that nothing was recorded is.
( cd "$sx" || exit 1
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id GHOST --agent coder
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id GHOST --agent coder
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  rows=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM spend;" | tr -d '\015')
  gaps=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE kind='spend-gap';" | tr -d '\015')
  [ "$rows" = 2 ] && [ "$gaps" = 1 ] )
check $? "no spend row, one spend-gap, and not one gap per firing"
rm -rf "$sx"
fi

if step "a CRLF profile and CRLF task files parse identically to LF"; then
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
fi

if step "a broken tier.rule cannot empty the index, and a lost task file fails closed"; then
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
( cd "$gx" || exit 1
  git init -q -b main 2>/dev/null
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
fi

if step "an ingest adapter cannot reach sqlite3's dot-commands"; then
# Adapter stdout is fed to the sqlite3 CLI through a file redirect, not through a driver, so a
# line whose FIRST character is `.` was a dot-command rather than SQL. `.shell touch x` ran a
# shell with the operator's permissions, on a path an agent can reach: the profile naming the
# adapter is an ordinary in-root file, and kit-guard.sh permits every in-root write by design.
# The refusal filter is a blacklist of schema-altering STATEMENTS and could not see `.shell`,
# `.system`, `.import`, `.load` or `.output`. The fix indents emitted lines by one space, which
# closes the channel without naming a command; sqlite3 then parses them as SQL and fails.
#
# TWO HALVES, and half 1 is why half 2 means anything. An absent marker proves nothing if the
# adapter never ran -- so half 1 shows adapter output genuinely reaching the database, and only
# then does half 2's absence say the dot-command was refused rather than never attempted.
dx="$WORK.dotcmd"; rm -rf "$dx"; mkdir -p "$dx/.claude" "$dx/.project/tasks"
( cd "$dx" || exit 1
  git init -q -b main 2>/dev/null
  { echo "---"; echo "paths.tasks:  .project/tasks"; echo "paths.state:  .project"
    echo "paths.status: STATUS.generated.md"; echo "tier.default: T1"
    echo "ingest.extra: .claude/probe.sh"; echo "---"; } > .claude/project-profile.md

  # HALF 1 -- adapter output reaches the database. If this stops being true the step is
  # measuring nothing, so it fails rather than skipping.
  printf '#!/usr/bin/env bash\n[ "$1" = emit ] && echo "INSERT OR REPLACE INTO meta(key,value) VALUES(\047probe\047,\0471\047);"\nexit 0\n' > .claude/probe.sh
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>p.err || exit 1
  [ "$(sqlite3 .project/index.db "SELECT value FROM meta WHERE key='probe';" | tr -d '\015')" = 1 ] || exit 1

  # HALF 2 -- the same channel carrying a dot-command executes nothing. The build FAILS, which
  # is the intended outcome: an indented dot-command is not valid SQL, and fail-closed on a
  # malformed adapter is the behaviour the surrounding code already relies on.
  printf '#!/usr/bin/env bash\n[ "$1" = emit ] && printf ".shell touch PWNED-DOTCMD\\n"\nexit 0\n' > .claude/probe.sh
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>q.err && exit 1
  [ -e PWNED-DOTCMD ] && exit 1
  exit 0 )
check $? "an adapter's dot-command is parsed as SQL, never executed as a shell"
rm -rf "$dx"
fi

if step "the write guard refuses every tool its matcher fires on"; then
# The guard matched Write|Edit|NotebookEdit and read only "file_path". NotebookEdit names its
# target "notebook_path", so the extraction came back empty, the no-target branch fail-opened,
# and a NotebookEdit anywhere on disk went through unexamined -- while SECURITY.md listed the
# tool by name under "enforced mechanically". Write outside exited 2; NotebookEdit outside
# exited 0.
#
# The check that was supposed to cover this greps hooks.json for the matcher STRING. That
# passes while the guard is broken, and would pass on a guard that refused nothing at all. It
# is a fine protocol assertion and stays where it is; it is not a behavioural one, so this step
# exercises the guard instead of reading it.
#
# BOTH DIRECTIONS PER TOOL. A guard that refused everything would pass an outside-only test and
# make the kit unusable, so each tool must also be allowed inside the root.
gt="$WORK.guard"; rm -rf "$gt"; mkdir -p "$gt"
( cd "$gt" || exit 1
  git init -q -b main 2>/dev/null
  : > inside.txt

  # Both probe paths are absolute and derived from git's OWN spelling of the root, not from
  # $PWD. On msys, Windows Temp is reachable as both /tmp/... and /c/Users/.../Temp/... -- two
  # spellings of one directory that `pwd -P` cannot collapse, because the alias is a mount and
  # not a symlink. A relative probe resolved against $PWD then lands in the other spelling and
  # the guard refuses it: fail-CLOSED, and a property of where this fixture happens to sit
  # rather than of the guard. Using one spelling for both sides tests inside-versus-outside,
  # which is what this step is for.
  root=$(git rev-parse --show-toplevel 2>/dev/null) ||
    { printf '    ^ fixture is not a git repository; the guard would exit 0 unexamined\n' >&2; exit 1; }
  inside="$root/inside.txt"
  outside="$root/../kit-guard-probe-outside.txt"

  for pair in "Write file_path" "Edit file_path" "NotebookEdit notebook_path"; do
    # shellcheck disable=SC2086
    set -- $pair; t=$1; k=$2
    printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "$t" "$k" "$outside" |
      bash "$KIT/tooling/kit-guard.sh" >/dev/null 2>&1
    [ $? = 2 ] || { printf '    ^ %s outside the root was NOT refused\n' "$t" >&2; exit 1; }
    printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "$t" "$k" "$inside" |
      bash "$KIT/tooling/kit-guard.sh" >/dev/null 2>&1
    [ $? = 0 ] || { printf '    ^ %s inside the root WAS refused\n' "$t" >&2; exit 1; }
  done

  # The drift check AC3 asks for. The matcher lives in hooks.json and the key mapping lives in
  # kit-guard.sh; they agreed by luck until they did not. Adding a fourth tool to the matcher
  # without teaching the guard its key now fails here rather than failing open in production.
  mt=$(grep -o '"matcher": "[^"]*"' "$KIT/hooks/hooks.json" | head -1 |
       sed 's/.*"matcher": "//; s/"$//')
  [ -n "$mt" ] || { printf '    ^ could not read the PreToolUse matcher\n' >&2; exit 1; }
  for t in $(printf '%s' "$mt" | tr '|' ' '); do
    case " Write Edit NotebookEdit " in
      *" $t "*) ;;
      *) printf '    ^ hooks.json matches %s but this step has no key for it, so the guard\n' "$t" >&2
         printf '      is untested for it -- add the tool key here and to kit-guard.sh\n' >&2
         exit 1 ;;
    esac
  done
  exit 0 )
check $? "every matched tool is refused outside the root and allowed inside it"
rm -rf "$gt"
fi

if step "a failed build leaves the previous index alone and keeps saying so"; then
# Two halves of one defect. `fl` was the only value on the task INSERT not passed through
# q(), so `tier.rule: src/** T3','x` ended the SQL literal early: the statement failed, the
# surrounding transaction still committed, and every task landed with tier NULL. Then the
# half-written DB was newer than every source, so the next --if-stale run -- the one that
# fires at session start -- declared it fresh and said nothing. One announcement, then silence,
# over a backlog with no tiers.
ax="$WORK.apos"; rm -rf "$ax"; mkdir -p "$ax/.claude" "$ax/.project/tasks"
( cd "$ax" || exit 1
  git init -q -b main 2>/dev/null
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
fi

if step "the two floor sources agree on a non-ASCII path, and ? is refused"; then
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
fi

if step "provenance is recorded, defaulted and split out of the rate it would dilute"; then
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
( cd "$vx" || exit 1
  git init -q -b main 2>/dev/null
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
  [ -z "$(bash "$KIT/tooling/kit-trailers.sh" message m2.txt 2>&1)" ] || exit 1

  # THE FAIL-CLOSED DERIVATION FILTER. `kit-event.sh <task> via` writes through the generic
  # ndjson reader, which stores the WHOLE JSON LINE as payload -- that is how a JSON blob once
  # landed in task.via and dropped a task carrying a recorded escape out of the headline metric.
  # The `payload IN (vocabulary)` clause on the derivation is what closes it, and NOTHING
  # exercised it: `kit-event.sh` appeared zero times in this suite, so deleting the clause left
  # every step green. Found in the T3 review of 2026-08-10.
  bash "$KIT/tooling/kit-event.sh" T-kit via >/dev/null 2>&1 ||
    { printf '    ^ kit-event.sh failed; the filter was never exercised\n' >&2; exit 1; }
  # The EVENT MUST EXIST before its absence can be mistaken for the filter working. Asserting
  # only `via = kit` afterwards passes identically when kit-event.sh wrote nothing at all -- a
  # vacuous check, inside the test added because the filter had no test. Found 2026-08-12.
  ev=$(grep -c '"kind":"via"' .project/events.ndjson)
  [ "${ev:-0}" -ge 1 ] ||
    { printf '    ^ no via event was written, so this proves nothing\n' >&2; exit 1; }
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  # The blob must NOT become the provenance, and the honest earlier value must survive.
  blob=$(sqlite3 .project/index.db "SELECT via FROM task WHERE id='T-kit';" | tr -d '\015')
  [ "$blob" = "kit" ] || { printf '    ^ a kit-event payload reached task.via: %s\n' "$blob" >&2; exit 1; }

  # A FUTURE-DATED trailer must not pin provenance. `at` is the AUTHOR date, which is whatever
  # GIT_AUTHOR_DATE said, so ordering the derivation by it let one commit declare itself last
  # forever and no later retraction could reach it. Ordering by `seq` -- AUTOINCREMENT over a
  # `--reverse` walk -- is the order history actually happened in.
  #
  # Without this commit the fixture cannot tell the two orderings apart: every other commit here
  # shares one fixed date, so `at DESC, seq DESC` and `seq DESC` agree and the mutation survives.
  echo f > src/f; git add -A
  GIT_AUTHOR_DATE="2099-01-01T00:00:00+00:00" git commit -q --no-verify -m "feat: dated ahead

Task-Id: T-kit
Tier: T2
Via: kit"

  # A human RETRACTS an earlier Via: kit with Via: unknown. `unknown` is in the vocabulary, so
  # the guard used to discard it and promotion into via:kit was one-way -- the design forbids
  # using `manual` for this, because the two mean different things.
  echo r > src/r; git add -A
  git commit -q --no-verify -m "chore: retract

Task-Id: T-kit
Tier: T2
Via: unknown"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  back=$(sqlite3 .project/index.db "SELECT via FROM task WHERE id='T-kit';" | tr -d '\015')
  [ "$back" = "unknown" ] || { printf '    ^ Via: unknown did not retract; via is %s\n' "$back" >&2; exit 1; }

  # And with no task left in the kit population, the report must SAY so and NAME the tier,
  # rather than print 0 / 0 in the shape of a measurement. Named per tier because a global
  # gate let one via:kit task anywhere silence the notice for every other tier.
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'absent denominator' STATUS.generated.md ||
    { printf '    ^ no empty-denominator notice after the retraction\n' >&2; exit 1; }
  grep -qE '^> \*\*No task in [^*]*T2[^*]*records having been run' STATUS.generated.md ||
    { printf '    ^ the notice does not name the tier it is about\n' >&2; exit 1; } )
check $? "via: vocabulary honoured, unknown by default, trailer wins, rate splits and names"
rm -rf "$vx"
fi

if step "a recorded escape cannot be filtered out of the report"; then
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
( cd "$ex" || exit 1
  git init -q -b main 2>/dev/null
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

  # The residue. This was written when it could NOT be reached through the front door: every id
  # in a trailer got a task row invented for it, so an escape belonging to no task was
  # unreachable and only a seeded row could exercise the branch. That invention has since been
  # removed, and the reachable version of this case is now covered end to end by the ghost step
  # below. The seeded form is kept rather than replaced, because it pins the reader --
  # kit-status.sh -- against a state regardless of which producer creates it, and an adapter is
  # a producer this suite does not run.
  #
  # The index is derived and disposable, which is what makes writing to it legitimate here.
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
  [ $((shown + ${orph:-0})) = "$dbesc" ] || exit 1

  # The same identity again, with one NULL id in `task`. SQLite does not enforce NOT NULL on a
  # TEXT PRIMARY KEY, and `x NOT IN (set holding NULL)` is NULL rather than true for every x --
  # so an unguarded residue subquery reports zero orphans here while the database still holds
  # one, and hides every other orphan with it. The report would read clean through the very
  # guard written to stop it reading clean.
  #
  # Seeded directly for the same reason as the row above: kit-index.sh rejects a blank id on
  # every insert, so this state is unreachable through shipped code TODAY and the guard would
  # otherwise be a claim nobody ever executed.
  sqlite3 .project/index.db "INSERT INTO task(id) VALUES(NULL);"
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'belong to no task in this index' STATUS.generated.md || exit 1
  dbesc=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE kind='escaped';" | sed $'s/\r$//' | tr -d ' ')
  shown=$(grep -oE '[0-9]+ / [0-9]+ all' STATUS.generated.md | awk '{s+=$1} END{print s+0}')
  orph=$(grep -oE '\*\*[0-9]+ recorded escape' STATUS.generated.md | tr -dc '0-9')
  [ "$dbesc" = 2 ] || exit 1
  [ $((shown + ${orph:-0})) = "$dbesc" ] || exit 1 )
check $? "escape survives a relabel out of via:kit; nothing stored is missing from the report, and a NULL id cannot silence the residue"
rm -rf "$ex"
fi

if step "a Task-Id matching no task file is named, not counted as work"; then
# One character in a pushed commit -- T-20260801 where T-20260731 was meant -- became a
# permanent open T1 task with no title and no epic: in the Open list, in the backlog count, and
# in the escape-rate denominator of a tier nobody ever assigned it. kit-trailers.sh warns at
# commit time and pre-push blocks before it is shared; both work, and neither reaches history
# that is already pushed, which is the only case this covers.
#
# Dropping it silently would trade a visible wrong number for an invisible one, so the whole
# behaviour is asserted together: absent from the backlog AND from the metrics, present in the
# report with the commit that introduced it, and reconciled with no migration when the file
# turns up later.
gh="$WORK.ghost"; rm -rf "$gh"; mkdir -p "$gh/src"
( cd "$gh" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---\nid: T-real\ntitle: r\ntier: T2\n---\nb\n' > .project/tasks/T-real.md
  git add -A && git commit -q --no-verify -m "chore: seed"

  # Spend is recorded BEFORE the ghost's commit, so the ghost's own status transition is the
  # next one after it -- precisely what the attribution heuristic binds to.
  printf '{"type":"assistant","message":{"model":"m","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}\n' > sess.jsonl
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" >/dev/null 2>&1

  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: w

Task-Id: T-ghost
Tier: T1
Task-Status: progress"
  sha=$(git rev-parse --short=7 HEAD)
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }

  # Not a task. The node survives, so the edges that point at the id still resolve.
  [ "$(Q "SELECT COUNT(*) FROM task WHERE id='T-ghost';")" = 0 ] || exit 1
  [ "$(Q "SELECT COUNT(*) FROM node WHERE id='T-ghost' AND type='task';")" = 1 ] || exit 1
  # Scoped to the Open section on purpose: the id DOES appear in the report, two sections
  # lower, and a bare `grep -v` for it would pass by finding the wrong line -- or fail by
  # finding the right one. Absent from the backlog and present in the report is the whole
  # behaviour, so each half is asserted where it belongs.
  sed -n '/^## Open/,/^## Closed/p' STATUS.generated.md | grep -qE '^- T-ghost' && exit 1
  # Backticks are part of the assertion, not incidental formatting: the id is rendered as a
  # code span precisely so a hostile id cannot act as markup, and a test matching the bare id
  # would go green again the day that escaping is dropped.
  grep -qE '^- `T-ghost`  '"$sha"'  seen as: .*progress' STATUS.generated.md || exit 1

  # Out of the DERIVED metrics too, not just the list -- the tier it was never assigned has no
  # row at all. Checking the Open list alone would pass while the denominator stayed wrong.
  grep -qE '^- T1 +' STATUS.generated.md && exit 1

  # And the cost does not vanish into it. Bound to an id with no task row, the spend would be
  # dropped by every figure in the report (all of which join `task`) while the unattributed
  # warning counts only a NULL task_id -- neither attributed nor reported, which is worse than
  # unattributed. It stays NULL, and the existing warning says so.
  [ "$(Q "SELECT COUNT(*) FROM spend WHERE task_id IS NULL OR task_id='';")" = 1 ] || exit 1
  grep -q 'spend record(s) unattributed' STATUS.generated.md || exit 1

  # The arrangement the first version of this test avoided, which is why it proved nothing: a
  # REAL task's transition, later than the ghost's. Skipping the ghost must not become binding
  # to whatever comes next -- that is not "unattributed", it is the cost of one task charged to
  # another, at another tier, reading as correct. Measured before the fix: it landed on T-real.
  echo z > src/c; git add -A
  git commit -q --no-verify -m "feat: unrelated

Task-Id: T-real
Tier: T2
Task-Status: done"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  [ "$(Q "SELECT COUNT(*) FROM spend WHERE task_id='T-real';")" = 0 ] || exit 1
  [ "$(Q "SELECT COUNT(*) FROM spend WHERE task_id IS NULL OR task_id='';")" = 1 ] || exit 1

  # The file arrives afterwards, which is a normal sequence rather than an error. There is no
  # reconciliation pass to run: the file emits the row, the derivation only adds what is
  # missing, and the id is a real task on the next index -- with the waiting spend attached.
  printf -- '---\nid: T-ghost\ntitle: g\ntier: T1\n---\nb\n' > .project/tasks/T-ghost.md
  git add -A && git commit -q --no-verify -m "chore: file it"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  [ "$(Q "SELECT COUNT(*) FROM task WHERE id='T-ghost';")" = 1 ] || exit 1
  grep -qE '^- T-ghost +g +\[T1\]' STATUS.generated.md || exit 1
  grep -q '## Unresolved task ids' STATUS.generated.md && exit 1
  grep -qE '^- T1 +0 / 0 via:kit +0 / 1 all$' STATUS.generated.md || exit 1
  [ "$(Q "SELECT COUNT(*) FROM spend WHERE task_id='T-ghost';")" = 1 ] || exit 1 )
check $? "a ghost id is out of the backlog and every metric, named with its commit, and reconciles when filed"
rm -rf "$gh"
fi

if step "an unknown blocker still blocks, and an id cannot hide itself from the report"; then
# Two failures found by review of the change above, both of which it introduced.
#
# 1. TOPOLOGY BEATS PRIORITY is kit-plan.sh's first stated rule, and not inventing a task row
#    silently defeated it: the depends_on edge survives, its target has no task row, and the
#    planner's filter drops the CONSTRAINT rather than the task. Measured against the parent
#    commit -- a task blocked by an unfiled id moved from layer 1 to layer 0, first in the
#    plan, as though nothing were in its way. An unknown blocker is not a satisfied one.
# 2. A task id is arbitrary text from a git trailer, and this whole feature exists for history
#    that never passed the commit-msg hook. Rendered raw, an id beginning `<!--` sorts first
#    under BINARY collation and comments out every row below it AND the count. A report its own
#    input can silence is not a control.
ub="$WORK.unblock"; rm -rf "$ub"; mkdir -p "$ub/src"
( cd "$ub" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---\nid: T-A\ntitle: a\ntier: T2\nblocked_by: T-B-unfiled\n---\nb\n' > .project/tasks/T-A.md
  # T-C depends on T-D as well as on T-A, which is what makes the scoring assertion below
  # possible: T-C is withheld through T-A, while T-D survives and has a withheld dependent.
  printf -- '---\nid: T-C\ntitle: c\ntier: T1\nblocked_by: T-A,T-D\n---\nb\n'      > .project/tasks/T-C.md
  printf -- '---\nid: T-D\ntitle: d\ntier: T1\n---\nb\n'                           > .project/tasks/T-D.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  echo x > src/a; git add -A
  git commit -q --no-verify -m "feat: a

Task-Id: <!-- T-hidden
Tier: T1
Task-Status: progress"
  echo y > src/b; git add -A
  git commit -q --no-verify -m "feat: b

Task-Id: T-zzz-sorts-after
Tier: T1
Task-Status: done"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-plan.sh" >"$PWD/plan.out" 2>"$PWD/plan.err"
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }

  # The blocked task is withheld, and so is what waits behind it. T-D is untouched, which is
  # what stops "withhold" from quietly meaning "plan nothing".
  [ "$(Q "SELECT COUNT(*) FROM plan_item WHERE task_id='T-A';")" = 0 ] || exit 1
  [ "$(Q "SELECT COUNT(*) FROM plan_item WHERE task_id='T-C';")" = 0 ] || exit 1
  [ "$(Q "SELECT COUNT(*) FROM plan_item WHERE task_id='T-D';")" = 1 ] || exit 1
  # Withheld silently is the same defect wearing a different face: a task missing from the plan
  # reads as a task the plan judged unimportant.
  grep -q 'T-A blocked by T-B-unfiled' plan.err || exit 1

  # The id is inert, the rows after it survive, and the count still says three.
  grep -qF '`<!-- T-hidden`' STATUS.generated.md || exit 1
  grep -qF '`T-zzz-sorts-after`' STATUS.generated.md || exit 1
  grep -qE '^> \*\*3 task id\(s\) are referenced' STATUS.generated.md || exit 1
  # Origin is shown rather than guessed: a trailer id carries its commit, a blocked_by id names
  # the file that declared it -- where "correct the trailer" would be advice about no trailer.
  grep -qF 'declared by `.project/tasks/T-A.md`' STATUS.generated.md || exit 1
  # Dropping a finished task's history is deliberate; being unable to tell it happened is not.
  # T-zzz-sorts-after completed and has no file, so the cost of that drop is stated.
  grep -qE '^> \*\*1 id\(s\) carry a recorded ' STATUS.generated.md || exit 1

  # EVERY field is escaped, not only the id -- the assertion above pins the path, this one pins
  # the event kinds. `Task-Status:` is checked against no vocabulary, so a trailer puts arbitrary
  # text into `seen as:`; hardening the id alone held only while the id sat first on the line,
  # which is an accident of field order rather than a property of the fix.
  grep -qE 'seen as: `[a-z,]+`$' STATUS.generated.md || exit 1

  # The magnitude, not just the trigger, and in the index rather than only on a stderr this
  # very fixture redirects away. Measured before it existed: 22 open tasks, one mistyped
  # blocked_by, one task planned and twenty-one gone, reported by a single line naming a root.
  grep -qE 'open task\(s\) withheld' plan.err || exit 1
  [ "$(Q "SELECT value FROM meta WHERE key='plan_withheld:default';")" = "2 3" ] || exit 1

  # ON STDOUT, and asserted there specifically. The finding this answers was that the magnitude
  # reached nobody when stderr was dropped -- and the first fix for it moved the number into the
  # index and then read it back out through kit_warn, which is stderr again. A test that greps
  # only plan.err passes just as happily with the stdout line deleted: mutation-checked, and it
  # did exactly that. The channel is the fix, so the channel is what gets asserted.
  grep -qE '^# 2 of 3 open task\(s\) withheld' plan.out || exit 1

  # Priority must not be inflated by work that cannot be released. T-D survives and its only
  # dependent, T-C, is withheld; scoring it over the raw graph counts that dependent anyway.
  # w_unblocks=3, w_tier=1, T-D is T1, so the score is 3*0 + 1 = 1 when withheld descendants
  # are excluded and 3*1 + 1 = 4 when they are not. Pinned exactly, because "not zero" would
  # pass either way.
  [ "$(Q "SELECT printf('%.1f',score) FROM plan_item WHERE task_id='T-D';")" = "1.0" ] || exit 1

  # A NULL id cannot empty the section. Same SQLite deviation the residue query was hardened
  # against; the query added alongside it was not, and one NULL row blanked a bullet, put the
  # count out of step with the rows, and could remove the section outright.
  sqlite3 .project/index.db "INSERT INTO node(id,type,path,title) VALUES(NULL,'task',NULL,NULL);"
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -qE '^> \*\*3 task id\(s\) are referenced' STATUS.generated.md || exit 1
  grep -qE '^- $' STATUS.generated.md && exit 1

  # The FOURTH field. Three were stripped and a comment claimed all of them; the commit sha went
  # out raw, and a backtick plus a newline in it fabricated a bullet and moved the rendered count
  # with it, because the count is `grep -c .` over lines rather than rows. Both are asserted --
  # the row count AND the printed number -- because either alone passes while the other is wrong.
  sqlite3 .project/index.db "UPDATE event SET commit_sha='ab'||CHAR(96)||'cd'||CHAR(10)||'- fabricated row'
                              WHERE task_id='T-zzz-sorts-after';"
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  [ "$(sed -n '/^## Unresolved/,/^> /p' STATUS.generated.md | grep -c '^- ')" = 3 ] || exit 1
  grep -qE '^> \*\*3 task id\(s\) are referenced' STATUS.generated.md || exit 1
  grep -qF '- fabricated row' STATUS.generated.md && exit 1

  # A FAILING PLAN QUERY MUST REACH THE CALLER. It stopped doing so when the withheld read-back
  # became the last command in the script: a `case` matching nothing returns 0, so empty stdout
  # and success -- indistinguishable from "no work left" -- was what an orchestrator received.
  # The existing exit-status check only ever exercised the success path, so it went quiet at the
  # same time and said nothing.
  #
  # Injected with a shim rather than raced. The realistic cause is kit-index.sh swapping the
  # database underneath a concurrent run at session start, and a race this suite loses on purpose
  # is a race it will also lose by accident on someone else's machine.
  realsq=$(command -v sqlite3)
  mkdir -p shimbin
  { printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do case "$a" in *"ORDER BY p.layer, p.rank"*) exit 1 ;; esac; done\n'
    printf 'exec "%s" "$@"\n' "$realsq"; } > shimbin/sqlite3
  chmod +x shimbin/sqlite3
  PATH="$PWD/shimbin:$PATH" bash "$KIT/tooling/kit-plan.sh" --next 5 >/dev/null 2>&1
  [ $? -ne 0 ] || exit 1
  rm -rf shimbin

  # Spend naming an id with no task row is in a figure or in the warning, never neither: the
  # figures that join `task` drop it, and a test for NULL alone would never mention this row.
  sqlite3 .project/index.db "INSERT INTO spend(transcript,scope,at,turns,tok_in,tok_out,cache_read,cache_write,context,task_id)
                             VALUES('tr-x','main','2026-01-01T00:00:00Z',1,10,10,0,0,0,'T-B-unfiled');"
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'spend record(s) unattributed' STATUS.generated.md || exit 1 )
check $? "an unfiled blocker withholds its dependents and is reported; a hostile id cannot suppress the section"
rm -rf "$ub"
fi

if step "a reviewer returns findings as data, and a bad batch records nothing"; then
# The structured contract that replaced the prose block. Three properties matter and none is
# visible by inspection: a rejected batch must record NOTHING (a half-stored review is a
# finding table that disagrees with the review it came from), a summary must survive the trip
# through the append-only log intact, and an empty review must be distinguishable from a
# review that never happened.
sj="$WORK.sjson"; rm -rf "$sj"; mkdir -p "$sj/src"
# `cd || exit` rather than `cd && <one command>`: chaining only the next command left every
# later line running in whatever directory the shell was already in, and with no `set -e` a
# failed cd would have run kit-init.sh and committed a fixture task INSIDE THE KIT'S OWN REPO.
( cd "$sj" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---\nid: T-j\ntitle: j\ntier: T2\n---\nb\n' > .project/tasks/T-j.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  F="$KIT/tooling/kit-finding.sh"
  # NOT `grep -c ... || echo 0`: grep prints 0 AND exits 1 when it matches nothing, so that
  # idiom yields the two-line string "0\n0" and every later comparison against it is false.
  # It is in LESSONS as a known trap and it bit here anyway, silently, until the counts differed.
  nfind() { _c=$(grep -c '"kind":"finding"' .project/events.ndjson 2>/dev/null); printf '%s' "${_c:-0}"; }
  before=$(nfind)

  # One good finding and one with an unknown class. All-or-nothing means NEITHER is stored.
  printf '%s' '{"findings":[{"class":"fail-open","severity":"major","summary":"a real one that must not be stored either"},{"class":"invented","severity":"major","summary":"the one that poisons the batch"}]}' \
    | bash "$F" --task T-j --agent implementation-reviewer --json >/dev/null 2>&1
  rej=$?
  after=$(nfind)

  # Hostile input in EVERY string field, not only `summary`. The first version of this case put
  # the quote in `summary` alone, and that is precisely why the critical stayed invisible to CI:
  # `lang`, `pattern`, `domain` and `file` reached the writer unsanitised and a quote in any of
  # them corrupts the line permanently. A backslash and a quote are what the awk reader cannot
  # see past, and a CR inside the string splits one event into two malformed lines.
  # Written with a QUOTED heredoc, not printf: printf collapses `\\` into a lone backslash and
  # produces JSON that is invalid for a reason unrelated to what is being tested, which is how
  # this case first went red. The payload has to reach the validator exactly as a reviewer
  # would send it.
  cat > hostile.json <<'HOSTILE'
{"findings":[{"class":"correctness","severity":"nit","lang":"ba\"sh","pattern":"a\\b","domain":"x\"y","file":"a\"b.sh","line":42,"summary":"the guard reads \"x\" and a \\ breaks it"}]}
HOSTILE
  bash "$F" --task T-j --agent implementation-reviewer --json < hostile.json >/dev/null 2>&1
  good=$?

  # Empty is a measurement; a missing key is not the same statement.
  printf '%s' '{"findings":[]}' | bash "$F" --task T-j --agent tester --json >/dev/null 2>&1
  empty=$?
  printf '%s' '{}' | bash "$F" --task T-j --agent tester --json >/dev/null 2>&1
  nokey=$?

  # The two gap reasons mean opposite things: `empty` is evidence, `rejected` is a hole where
  # findings existed and were refused. Recording only the first -- which is what the first
  # version did -- kept the harmless half and dropped the harmful one.
  ge=$(grep -c '"kind":"finding-gap","at":"[^"]*","agent":"tester"' .project/events.ndjson)
  gr=$(grep -c '"reason":"rejected"' .project/events.ndjson)
  gm=$(grep -c '"reason":"empty"' .project/events.ndjson)

  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }
  rows=$(Q "SELECT COUNT(*) FROM finding;")
  summ=$(Q "SELECT summary FROM finding;")
  loc=$(Q "SELECT file_path||':'||line_no FROM finding;")
  # Read back the OTHER hostile fields too. Asserting only `summary` is what let the critical
  # through: the row can be present and readable while lang or pattern carries an injected key.
  oth=$(Q "SELECT lang||'|'||pattern FROM finding;")
  # Every line of the append-only log must still be one parseable JSON object.
  pyok=$(python3 -c "
import json,sys
bad=0
for l in open('.project/events.ndjson','rb').read().decode('utf-8').split(chr(10)):
    if l.strip():
        try: json.loads(l)
        except Exception: bad+=1
print(bad)" 2>/dev/null || echo 99)

  [ "$rej" = 2 ] && [ "$before" = "$after" ] && [ "$good" = 0 ] &&
  [ "$empty" = 0 ] && [ "$nokey" = 2 ] && [ "$rows" = 1 ] && [ "$pyok" = 0 ] &&
  [ "$loc" = "a'b.sh:42" ] && [ "$oth" = "ba'sh|a'b" ] &&
  [ "${gr:-0}" -ge 1 ] && [ "${gm:-0}" -ge 1 ] &&
  [ "$summ" = "the guard reads 'x' and a ' breaks it" ] )
check $? "one bad finding records none, hostile input in every field round-trips, empty differs from absent"

# A caller handing over a review must never have it swallowed. Outside an adopted project the
# recorder used to exit 0 having consumed stdin and written nothing -- success reported over a
# destroyed review.
nj="$WORK.notadopted"; rm -rf "$nj"; mkdir -p "$nj"
( cd "$nj" || exit 1
  git init -q -b main 2>/dev/null
  printf '%s' '{"findings":[{"class":"fail-open","severity":"major","summary":"this review must not be swallowed"}]}' \
    | bash "$KIT/tooling/kit-finding.sh" --task T --agent x --json >/dev/null 2>&1
  [ $? -ne 0 ] )
check $? "a piped review is refused, not silently discarded, outside an adopted project"
rm -rf "$nj"
rm -rf "$sj"
fi

if step "a finding has a stable id and can be marked addressed"; then
# Two properties, and the first is load-bearing for the second.
#
# IDENTITY. The id used to be `at:n`, n counting indexed findings in sorted order, so an event
# merged in from a branch with an earlier timestamp renumbered every finding after it --
# measured on this repository's own log, one inserted line moved all 219. A mark keyed on such
# an id does not fail to resolve; it silently reattaches to the NEIGHBOURING finding, which is
# worse than no mark. So the mutation to watch for here is any return to a positional counter.
#
# ADDRESSED. `vindicated` says whether a finding was REAL. Nothing said whether it was FIXED,
# so "is there an open critical on this task" was uncomputable and the trial protocol's first
# pre-flight box was waved through on its first execution. The two facts are orthogonal and
# this proves all four combinations are representable, not merely that a column exists.
rs="$WORK.resolve"; rm -rf "$rs"; mkdir -p "$rs"
( cd "$rs" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---\nid: T-r\ntitle: r\ntier: T2\n---\nb\n' > .project/tasks/T-r.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  EV=.project/events.ndjson
  F="$KIT/tooling/kit-finding.sh"; R="$KIT/tooling/kit-resolve.sh"
  Q() { sqlite3 .project/index.db "$1" 2>/dev/null | tr -d '\015'; }
  reindex() { rm -f .project/index.db; bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1; }
  # Real commits, because `--commit` must now RESOLVE. The fixture used to cite `deadbee` and
  # `aaaaaaa`, which is exactly the defect an approach reviewer named: a mark with no evidence
  # and a mark citing a SHA that never existed were the same row, and the second reads as
  # substantiated. A fixture that cannot tell them apart cannot catch it either.
  newsha() { git commit -q --no-verify --allow-empty -m "fixture commit $1"; git rev-parse HEAD; }

  printf '%s' '{"findings":[{"class":"fail-open","severity":"critical","summary":"the first one, which gets fixed"},{"class":"correctness","severity":"critical","summary":"the second one, which stays open"}]}' \
    | bash "$F" --task T-r --agent implementation-reviewer --json >/dev/null 2>&1
  reindex
  ids0=$(Q "SELECT group_concat(id,' ') FROM finding ORDER BY at,id;")
  n0=$(Q "SELECT COUNT(*) FROM finding;")

  # THE MERGE. An event from a branch whose clock ran earlier -- the case .gitattributes'
  # merge=union makes routine. Nothing about the two findings above changed, so nothing about
  # their ids may change either.
  printf '%s\n' '{"task":"T-r","kind":"finding","at":"2000-01-01T00:00:00Z","agent":"other-branch","class":"perf","severity":"minor","lang":"bash","summary":"recorded on a branch with an earlier clock"}' >> "$EV"
  reindex
  ids1=$(Q "SELECT group_concat(id,' ') FROM finding WHERE at > '2001' ORDER BY at,id;")
  n1=$(Q "SELECT COUNT(*) FROM finding;")

  # A BYTE-IDENTICAL duplicate is two rows, not one. Pre-contract findings carry no summary, so
  # two distinct defects on one task in one second serialise alike; collapsing them would drop a
  # finding silently, which is the failure mode this file exists to refuse.
  dupline='{"task":"T-r","kind":"finding","at":"2000-01-02T00:00:00Z","agent":"o","class":"perf","severity":"nit","lang":"bash"}'
  printf '%s\n%s\n' "$dupline" "$dupline" >> "$EV"
  reindex
  ndup=$(Q "SELECT COUNT(*) FROM finding WHERE at='2000-01-02T00:00:00Z';")

  # THE GOLDEN ID. A fixed event line must always produce this exact id -- here, on the other
  # CI platform, and after any rewrite of the hash. The id is FNV-1a 32 over the line, and awk
  # arithmetic is IEEE double: an implementation that multiplies without splitting into 16-bit
  # halves needs 55 bits of mantissa, silently rounds, and computes a different value on a
  # different awk. Every id in the repository would then depend on which machine last indexed.
  #
  # This is asserted END TO END, through kit-index.sh, on purpose. The first version of this
  # check pasted the algorithm into the test and compared it against the published vectors --
  # which proves an algorithm correct without proving it is the one in use, and a mutation that
  # broke the multiply inside kit-index.sh SURVIVED it. LESSONS S1, found by mutating rather
  # than by reading.
  printf '%s\n' '{"task":"T-r","kind":"finding","at":"2000-01-03T00:00:00Z","agent":"golden","class":"perf","severity":"nit","lang":"bash","summary":"a fixed line whose id must not move"}' >> "$EV"
  reindex
  gold=$(Q "SELECT id FROM finding WHERE at='2000-01-03T00:00:00Z';")

  fid=$(Q "SELECT id FROM finding WHERE summary LIKE 'the first one%';")
  oid=$(Q "SELECT id FROM finding WHERE summary LIKE 'the second one%';")

  # A typo must fail where it is typed. Appending a mark for an id no finding has puts a line
  # in a permanent log that can only ever be reported as an orphan, while the operator saw
  # exit 0 and believed it landed.
  evb=$(grep -c '"kind":"finding-fixed"' "$EV" 2>/dev/null); evb=${evb:-0}
  bash "$R" --finding "T-r:nosuchid" --fixed >/dev/null 2>&1; bogus=$?
  eva=$(grep -c '"kind":"finding-fixed"' "$EV" 2>/dev/null); eva=${eva:-0}

  SHA_FID=$(newsha fid)
  bash "$R" --finding "$fid" --fixed --commit "$SHA_FID" --note "closed by the one-writer move" \
    >/dev/null 2>&1; markrc=$?
  bash "$KIT/tooling/kit-vindicate.sh" --task T-r --class fail-open --real >/dev/null 2>&1
  # Rebuilt FROM SCRATCH, not updated in place. A mark that lived only in the database would
  # be erased by the next reindex -- present, plausible, and gone.
  reindex
  fx=$(Q "SELECT COALESCE(fixed_at,'NULL') FROM finding WHERE id='$fid';")
  fc=$(Q "SELECT COALESCE(fixed_commit,'NULL') FROM finding WHERE id='$fid';")
  # Read through --list, the reader this field was added for. Selecting the column directly
  # proves the column is populated and says nothing about whether anything surfaces it, which
  # is the whole complaint the note was filed under.
  case "$(bash "$R" --list --task T-r 2>/dev/null)" in
    *"(fixed: closed by the one-writer move)"*) fnote=1 ;; *) fnote=0 ;;
  esac
  vd=$(Q "SELECT COALESCE(vindicated,'NULL') FROM finding WHERE id='$fid';")
  openc=$(Q "SELECT COUNT(*) FROM finding WHERE severity='critical' AND fixed_at IS NULL;")

  # ALL FOUR COMBINATIONS, CONSTRUCTED. The criterion this fixture is cited for claims the four
  # vindicated-by-fixed states are representable, and BOTH reviewers of the T3 round found that
  # only `--real` was ever exercised -- `vindicated=0` appeared nowhere, so at most three
  # existed and the fourth was asserted by the tick alone. `false and fixed` is the interesting
  # one: a reviewer was wrong AND the code was changed anyway, which one column cannot say.
  # `correctness` is vindicated real and left UNFIXED, which is the real-and-open corner --
  # without it three of the four counts below could be satisfied by one finding each.
  bash "$KIT/tooling/kit-vindicate.sh" --task T-r --class correctness --real >/dev/null 2>&1
  bash "$KIT/tooling/kit-vindicate.sh" --task T-r --class perf --false >/dev/null 2>&1
  pid=$(Q "SELECT id FROM finding WHERE class='perf' AND at='2000-01-03T00:00:00Z';")
  SHA_PID=$(newsha pid)
  bash "$R" --finding "$pid" --fixed --commit "$SHA_PID" >/dev/null 2>&1
  reindex
  c_rf=$(Q "SELECT COUNT(*) FROM finding WHERE vindicated=1 AND fixed_at IS NOT NULL;")
  c_ro=$(Q "SELECT COUNT(*) FROM finding WHERE vindicated=1 AND fixed_at IS NULL;")
  c_ff=$(Q "SELECT COUNT(*) FROM finding WHERE vindicated=0 AND fixed_at IS NOT NULL;")
  c_fo=$(Q "SELECT COUNT(*) FROM finding WHERE vindicated=0 AND fixed_at IS NULL;")
  four=0
  [ "${c_rf:-0}" -ge 1 ] && [ "${c_ro:-0}" -ge 1 ] &&
  [ "${c_ff:-0}" -ge 1 ] && [ "${c_fo:-0}" -ge 1 ] && four=1

  # A SECOND TASK. With one task in the fixture, a change that keyed the indexer's per-finding
  # arrays by task would pass everything above while silently scoping identity to a task --
  # ids, duplicate detection and mark resolution are all repository-wide, and nothing here
  # showed that until there were two tasks to be wide across.
  printf -- '---\nid: T-r2\ntitle: r2\ntier: T2\n---\nb\n' > .project/tasks/T-r2.md
  git add -A && git commit -q --no-verify -m "chore: second task"
  printf '%s' '{"findings":[{"class":"fail-open","severity":"critical","summary":"a critical on the OTHER task, same class as the first"}]}' \
    | bash "$F" --task T-r2 --agent implementation-reviewer --json >/dev/null 2>&1
  reindex
  tid=$(Q "SELECT id FROM finding WHERE summary LIKE 'a critical on the OTHER task%';")
  SHA_TID=$(newsha tid)
  bash "$R" --finding "$tid" --fixed --commit "$SHA_TID" >/dev/null 2>&1
  reindex
  t2fx=$(Q "SELECT COALESCE(fixed_commit,'NULL') FROM finding WHERE id='$tid';")
  t1fx=$(Q "SELECT COALESCE(fixed_commit,'NULL') FROM finding WHERE id='$fid';")

  # Retraction. A fix that turned out not to be one must be expressible, or the mark is a
  # one-way door and the first mistake is permanent.
  bash "$R" --finding "$fid" --open >/dev/null 2>&1
  reindex
  fx2=$(Q "SELECT COALESCE(fixed_at,'NULL') FROM finding WHERE id='$fid';")
  vd2=$(Q "SELECT COALESCE(vindicated,'NULL') FROM finding WHERE id='$fid';")

  # THREE MARKS BACK TO BACK. Ordering must not depend on how fast the machine is. At
  # whole-second resolution these land in one second and the tie breaks on the TEXT of the
  # line -- `"fixed":0}` sorts before `"fixed":1,"commit":...` -- so the retraction is applied
  # first, the fix wins, and `--open` silently does nothing. That is what happened: green here,
  # red on ubuntu-latest, because a container is fast enough to put them in the same second.
  # Timestamps are sub-second now, and this asserts the property rather than the format.
  SHA_A=$(newsha a)
  bash "$R" --finding "$oid" --fixed --commit "$SHA_A" >/dev/null 2>&1
  bash "$R" --finding "$oid" --open >/dev/null 2>&1
  SHA_B=$(newsha b)
  bash "$R" --finding "$oid" --fixed --commit "$SHA_B" >/dev/null 2>&1
  reindex
  lastw=$(Q "SELECT COALESCE(fixed_commit,'NULL') FROM finding WHERE id='$oid';")
  # No two marks may share a timestamp -- if any do, the one that loses is decided by string
  # order, which is not a fact about when it happened. Compared against the NUMBER OF MARKS
  # rather than a literal, so adding a case to this fixture cannot quietly weaken it.
  nat=$(grep -o '"kind":"finding-fixed","at":"[^"]*"' "$EV" | sort -u | wc -l | tr -d ' ')
  nmk=$(grep -c '"kind":"finding-fixed"' "$EV"); nmk=${nmk:-0}

  # A REAL COLLISION. Two DIFFERENT lines, one `at`, one FNV-1a 32 hash -- found by brute force
  # (1.7M tries, tools in the task notes) because this pair cannot be written by hand and the
  # fail-closed path cannot be exercised without one. A control that cannot run is not a
  # control, and refusing to apply a mark to an ambiguous id is the whole reason the collision
  # is detected at all.
  printf '%s\n' '{"task":"T-r","kind":"finding","at":"2000-01-04T00:00:00Z","agent":"collide","class":"compliance","severity":"nit","lang":"bash","summary":"collision fixture 1549599"}' >> "$EV"
  printf '%s\n' '{"task":"T-r","kind":"finding","at":"2000-01-04T00:00:00Z","agent":"collide","class":"compliance","severity":"nit","lang":"bash","summary":"collision fixture 1712382"}' >> "$EV"
  reindex
  ncol=$(Q "SELECT COUNT(*) FROM finding WHERE at='2000-01-04T00:00:00Z';")
  colmeta=$(Q "SELECT value FROM meta WHERE key='finding_id_collisions';")
  # Both rows survive -- neither line is dropped -- but a mark on the shared base id is
  # withheld, because attaching it to one of them would be a guess that asserts a specific
  # defect was fixed.
  # REFUSED WHERE IT IS TYPED. This used to be accepted with exit 0 and a success message while
  # every rebuild silently discarded it -- and the fixture asserted BOTH halves of that
  # mismatch on adjacent lines without noticing it was documenting a false success.
  HEADSHA=$(git rev-parse HEAD)
  bash "$R" --finding "2000-01-04T00:00:00Z:77087be7" --fixed --commit "$HEADSHA" >/dev/null 2>&1
  colmark=$?
  reindex
  ambflag=$(Q "SELECT COUNT(*) FROM finding WHERE at='2000-01-04T00:00:00Z' AND id_ambiguous=1;")

  # The indexer keeps its own refusal, and it is now the only way an ambiguous mark can arrive:
  # written on a branch where the colliding line did not yet exist and merged in afterwards.
  # Planted by hand for that reason -- kit-resolve refuses it at the keyboard, so a fixture that
  # only went through the command could no longer reach this path at all.
  printf '{"kind":"finding-fixed","at":"2030-06-02T00:00:00.000000Z","task":"T-r","actor":"fixture","finding":"2000-01-04T00:00:00Z:77087be7","fixed":1}\n' >> "$EV"
  reindex
  colfixed=$(Q "SELECT COUNT(*) FROM finding WHERE at='2000-01-04T00:00:00Z' AND fixed_at IS NOT NULL;")
  ambmeta=$(Q "SELECT value FROM meta WHERE key='finding_ambiguous_marks';")

  # A SHA THAT DOES NOT RESOLVE IS NOT EVIDENCE. `deadbee` was accepted by the old code and by
  # this fixture, which is how a mark citing a commit that never existed came to read as
  # substantiated.
  bash "$R" --finding "$oid" --fixed --commit deadbeefdeadbeef >/dev/null 2>&1; badsha=$?
  # A mark whose commit later leaves the history is reported rather than left resolving to air.
  #
  # TWO marks citing the SAME vanished SHA, deliberately. The counter reports "fix mark(s)" and
  # was counting DISTINCT commits, so three marks on one dead SHA under-reported as one. With a
  # single planted mark the two behaviours give the same number and the mutation reverting it
  # SURVIVED -- a fixture that cannot tell the fix from the defect is not evidence for either.
  mid=$(Q "SELECT id FROM finding WHERE at='2000-01-01T00:00:00Z';")
  _n=1
  for _f in "$pid" "$mid"; do
    printf '{"kind":"finding-fixed","at":"2030-06-01T00:00:0%s.000000Z","task":"T-r","actor":"fixture","finding":"%s","fixed":1,"commit":"%s"}\n' \
      "$_n" "$_f" "0000000000000000000000000000000000000001" >> "$EV"
    _n=$((_n + 1))
  done
  reindex
  missmeta=$(Q "SELECT value FROM meta WHERE key='finding_fix_commit_missing';")
  # The mark carries its task, so a task timeline shows its findings being resolved. Compared
  # against the number of marks made on T-r findings rather than a literal: EVERY one must carry
  # it, and a literal would quietly stop covering the marks added later in this fixture.
  marktask=$(Q "SELECT COUNT(*) FROM event WHERE kind='finding-fixed' AND task_id='T-r';")
  marksonr=$(Q "SELECT COUNT(*) FROM event e WHERE e.kind='finding-fixed'
                 AND EXISTS (SELECT 1 FROM finding f WHERE f.task_id='T-r'
                              AND e.payload LIKE '%'||f.id||'%');")

  # An orphan mark ALREADY IN the log -- from a hand edit, or a merge that brought the mark
  # without the finding -- is reported. Applied as an UPDATE it would match nothing and exit 0,
  # which is a gate reading clean because its evidence never arrived.
  printf '%s\n' '{"kind":"finding-fixed","at":"2030-01-01T00:00:00Z","actor":"fixture","finding":"nothing-has-this-id","fixed":1}' >> "$EV"
  rm -f .project/index.db
  orph=$(bash "$KIT/tooling/kit-index.sh" 2>&1 >/dev/null | grep -c 'name no known finding')

  # A WHOLE-SECOND MARK DENOTES THE START OF ITS SECOND. Timestamps are compared as strings and
  # `.` sorts before `Z`, so `...:07Z` landed AFTER every `...:07.######Z` -- backwards. Here a
  # hand-written whole-second RETRACTION is planted in the same second as the microsecond fix
  # that precedes it in time; the fix must still win. Every mark this command writes is
  # sub-second, so without a planted one this reordering is untestable and invisible.
  t2sec=$(Q "SELECT substr(fixed_at,1,19) FROM finding WHERE id='$tid';")
  printf '{"kind":"finding-fixed","at":"%sZ","actor":"fixture","finding":"%s","fixed":0}\n' "$t2sec" "$tid" >> "$EV"
  reindex
  t2keep=$(Q "SELECT COALESCE(fixed_commit,'NULL') FROM finding WHERE id='$tid';")

  # `--at` is the ordering key, not a label, and it was taken on trust.
  python3 "$KIT/tooling/kit_findings.py" --resolve --finding x --fixed 1 --at "yesterday" \
    >/dev/null 2>&1; atbad=$?
  python3 "$KIT/tooling/kit_findings.py" --resolve --finding x --fixed 1 --at "2026-01-01T00:00:00Z" \
    >/dev/null 2>&1; atgood=$?

  # WHAT REACHES THE FILE ANYONE READS. The indexer announced orphaned and ambiguous marks on
  # stderr alone, and stderr from a run inside kit-status.sh, a hook or CI is seen by nobody --
  # so the criticals list could be short for the one reason that must never be quiet.
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_orph=$(grep -c 'name no known finding' STATUS.generated.md); s_orph=${s_orph:-0}
  s_amb=$(grep -c 'REFUSED as ambiguous' STATUS.generated.md); s_amb=${s_amb:-0}

  # CLOSING A TASK IS NOT FIXING ITS CRITICALS, and a REFUTED critical is not outstanding work.
  # A third task carries one of each: the gate used to filter `state='progress'`, so closing the
  # task cleared it exactly as well as fixing the defect.
  printf -- '---\nid: T-r3\ntitle: r3\ntier: T2\n---\nb\n' > .project/tasks/T-r3.md
  git add -A && git commit -q --no-verify -m "chore: third task"
  printf '%s' '{"findings":[{"class":"fail-open","severity":"critical","summary":"critical on a task that then gets closed"},{"class":"race","severity":"critical","summary":"critical that a reviewer later refuted"}]}' \
    | bash "$F" --task T-r3 --agent implementation-reviewer --json >/dev/null 2>&1
  bash "$KIT/tooling/kit-vindicate.sh" --task T-r3 --class race --false >/dev/null 2>&1
  printf '{"task":"T-r3","kind":"done","at":"2030-07-01T00:00:00Z"}\n' >> "$EV"
  reindex
  r3state=$(Q "SELECT state FROM task WHERE id='T-r3';")
  gatecount=$(Q "SELECT COUNT(*) FROM finding WHERE severity='critical' AND fixed_at IS NULL
                  AND COALESCE(vindicated,1) <> 0;")
  gateclosed=$(Q "SELECT COUNT(*) FROM finding f JOIN task t ON t.id=f.task_id
                   WHERE f.severity='critical' AND f.fixed_at IS NULL
                     AND COALESCE(f.vindicated,1) <> 0 AND t.state IN ('done','abandoned');")
  gaterefuted=$(Q "SELECT COUNT(*) FROM finding WHERE severity='critical' AND fixed_at IS NULL
                    AND vindicated=0;")
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_closed=$(grep -c 'already done or abandoned' STATUS.generated.md); s_closed=${s_closed:-0}
  s_refuted=$(grep -c 'excluded as refuted' STATUS.generated.md); s_refuted=${s_refuted:-0}

  # A CLASS-SCOPED REFUTATION IS NOT A JUDGEMENT ON EVERY FINDING OF THAT CLASS. kit-vindicate
  # keys on (task, class), so a `--false` about one finding also refutes a critical sharing its
  # class -- which would then leave the gate having never been judged. T-r3 carries two
  # `fail-open` findings for exactly this: one critical, one minor.
  printf '%s' '{"findings":[{"class":"fail-open","severity":"minor","summary":"a harmless fail-open sharing the class of the critical"}]}' \
    | bash "$F" --task T-r3 --agent implementation-reviewer --json >/dev/null 2>&1
  bash "$KIT/tooling/kit-vindicate.sh" --task T-r3 --class fail-open --false >/dev/null 2>&1
  reindex
  ambigref=$(Q "SELECT COUNT(*) FROM finding f WHERE f.severity='critical' AND f.fixed_at IS NULL
                 AND f.vindicated=0 AND NOT 1 = (SELECT COUNT(*) FROM finding g
                        WHERE COALESCE(g.task_id,'')=COALESCE(f.task_id,'')
                          AND COALESCE(g.class,'')=COALESCE(f.class,''));")
  pfrc=$(cd "$rs" && bash "$KIT/tooling/kit-preflight.sh" --criticals >/dev/null 2>&1; echo $?)
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_ambigref=$(grep -c 'refutation that cannot be trusted' STATUS.generated.md); s_ambigref=${s_ambigref:-0}
  # The notice above is driven by its own counter, so it survives a regression in the LIST. The
  # list is what a reader acts on: T-r3 must still be IN it, because its critical carries a
  # refutation that cannot be trusted and is therefore still outstanding. Without this, reverting
  # the gate predicate to the too-eager `COALESCE(vindicated,1) <> 0` changed nothing any
  # assertion looked at -- a mutation survived and said so.
  s_r3crit=$(sed -n '/## Outstanding criticals/,/^## /p' STATUS.generated.md | grep -c 'T-r3')
  s_r3crit=${s_r3crit:-0}
  # The listing must agree with the gate about that finding rather than calling it plain OPEN.
  case "$(bash "$R" --list --task T-r3 2>/dev/null)" in *"OPEN?"*) listagree=1 ;; *) listagree=0 ;; esac
  # And EVERY mark records WHO made it -- what the `Via:` analogy claimed and did not have.
  # The two marks this fixture plants by hand carry `"actor":"fixture"` for the same reason a
  # real one carries an email: a mark with no actor is a mark nobody can be asked about, and
  # the invariant is worth more than the two exceptions would be.
  markactor=$(Q "SELECT COUNT(*) FROM event WHERE kind='finding-fixed'
                  AND (actor IS NULL OR actor='');")


  # AN ABSENT COUNTER IS NOT A ZERO COUNTER. Reading them with ${x:-0} made a stale index assert
  # that no mark had failed to apply -- the same fail-open as this section's critical, one level
  # down, shipped by the fix for it.
  sqlite3 .project/index.db "DELETE FROM meta WHERE key LIKE 'finding_%';" >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_absent=$(grep -c 'ABSENT from this index' STATUS.generated.md); s_absent=${s_absent:-0}
  reindex

  # THE CLEAN CASE MUST BE ABLE TO PRINT. Its line began with `-`, which bash printf parses as
  # an option, so it errored to stderr and emitted NOTHING -- an empty section, which reads as
  # no criticals. It had never run, in this case or in the failure case below.
  # Its own commit: reusing SHA_FID here put several marks in the log carrying that SHA, and the
  # "survives a rebuild" assertion selects the mark BY its commit -- so the subquery returned
  # three timestamps and compared them against one. The message read "got X, wanted X" with the
  # difference off the end of the line, which is its own small lesson about naming a condition.
  SHA_ALL=$(newsha all)
  for c in $(Q "SELECT id FROM finding WHERE severity='critical' AND fixed_at IS NULL;"); do
    bash "$R" --finding "$c" --fixed --commit "$SHA_ALL" >/dev/null 2>&1
  done
  reindex
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_none=$(grep -c 'none outstanding' STATUS.generated.md); s_none=${s_none:-0}

  # THE UNMEASURABLE CASE. An index built before `fixed_at` existed passes the readability
  # check at the top of kit-status.sh, because `task` is intact -- only this section notices.
  # Silence there is the critical its own T3 round found.
  # DROP COLUMN needs SQLite 3.35+, and its status was DISCARDED. On an older toolchain the
  # column survived, the two assertions below went red, and they blamed the code for something
  # that was never about the code -- the CRLF-guard failure again, where a check red for an
  # unrelated reason stops being read.
  sqlite3 .project/index.db "ALTER TABLE finding DROP COLUMN fixed_at;" >/dev/null 2>&1
  altrc=$?
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  s_unmeas=$(grep -c 'NOT MEASURED' STATUS.generated.md); s_unmeas=${s_unmeas:-0}
  s_falseclean=$(grep -c 'none outstanding' STATUS.generated.md); s_falseclean=${s_falseclean:-0}
  # Same broken index: a listing must FAIL rather than print nothing and exit 0.
  bash "$R" --list --severity critical >/dev/null 2>&1; listrc=$?
  reindex
  # ...and a genuinely empty result is a different statement, SAID rather than left blank. The
  # first version asserted only exit 0 -- which was already true before the fix, so it could not
  # fail for the thing it was named after. The message is what is checked now.
  listemptymsg=$(bash "$R" --list --severity nosuchseverity 2>&1); listempty=$?
  case "$listemptymsg" in *"not a failed query"*) listesaid=1 ;; *) listesaid=0 ;; esac

  # Probing a database that is not there must not CREATE one: `sqlite3 <path> <query>` does.
  # A stray empty index.db is later read as an index with no tasks in it.
  ( cd "$rs" || exit 1; rm -f .project/index.db
    bash "$R" --finding "anything" --fixed >/dev/null 2>&1 )
  strays=0; [ -f .project/index.db ] && strays=1
  reindex

  # THE AMBIGUITY PROBE AGAINST AN INDEX THAT PREDATES ITS COLUMN. This read `2>/dev/null` with
  # `${amb:-0}`, so the column error became "not ambiguous", the refusal was skipped, and the
  # tool printed "recorded" for a mark every rebuild would discard. Nothing exercised it -- the
  # stale-index case above drops `fixed_at` and tests the REPORT, not the mark path -- so a
  # mutation restoring the old probe survived and said so.
  sqlite3 .project/index.db "ALTER TABLE finding DROP COLUMN id_ambiguous;" >/dev/null 2>&1
  precolalt=$?
  bash "$R" --finding "$oid" --fixed --commit "$SHA_A" >/dev/null 2>&1; precolrc=$?
  reindex

  want() { [ "$2" = "$3" ] || { printf '    ^ %s: got %s, wanted %s\n' "$1" "$2" "$3" >&2; exit 1; }; }
  want "an earlier-dated merge adds a finding" "$n1" "$((n0 + 1))"
  want "  ...and renumbers none of the others" "$ids1" "$ids0"
  want "identical lines stay two findings"     "$ndup" 2
  want "a fixed line has a fixed id"           "$gold" "2000-01-03T00:00:00Z:addbabbf"
  want "an unknown id is refused"              "$bogus" 2
  want "  ...and nothing is appended"          "$eva" "$evb"
  want "a known id is accepted"                "$markrc" 0
  want "the mark survives a rebuild"           "$fx" "$(Q "SELECT at FROM event WHERE kind='finding-fixed' AND payload LIKE '%'||'$SHA_FID'||'%';")"
  want "  ...carrying its commit"              "$fc" "$SHA_FID"
  want "  ...and its note, surfaced by --list" "$fnote" 1
  want "all four vindicated x fixed states"    "$four" 1
  want "a mark on a second task applies"       "$t2fx" "$SHA_TID"
  want "  ...without disturbing the first"     "$t1fx" "$SHA_FID"
  want "vindicated is untouched by fixing"     "$vd" 1
  want "one critical fixed leaves one open"    "$openc" 1
  want "--open retracts the fix"               "$fx2" "NULL"
  want "  ...without retracting the verdict"   "$vd2" 1
  want "the last of three rapid marks wins"    "$lastw" "$SHA_B"
  want "  ...no two marks share a timestamp"   "$nat" "$nmk"
  want "an orphan mark is named, not ignored"  "$orph" 1
  want "a colliding pair stays two rows"       "$ncol" 2
  want "  ...and the collision is counted"     "$colmeta" 1
  want "a mark on that id is REFUSED when typed" "$colmark" 2
  want "  ...so nothing is marked fixed"       "$colfixed" 0
  want "  ...and both rows are flagged"        "$ambflag" 2
  want "a merged-in ambiguous mark is refused" "$ambmeta" 1
  want "a SHA that does not resolve is refused" "$badsha" 2
  want "both marks on one dead SHA counted"    "$missmeta" 2
  want "every mark carries its task"           "$marktask" "$marksonr"
  want "the stale-index fixture was built"     "$altrc" 0
  want "an empty listing SAYS it is empty"     "$listesaid" 1
  want "a whole-second mark starts its second" "$t2keep" "$SHA_TID"
  want "a malformed --at is refused"           "$atbad" 2
  want "  ...and a legal one is not"           "$atgood" 0
  want "the closing task is really closed"     "$r3state" "done"
  want "  ...its critical still counts"        "$gateclosed" 1
  want "  ...and status names it"              "$s_closed" 1
  want "an ambiguous refutation does NOT retire" "$ambigref" 1
  want "  ...so the gate still says STOP"      "$pfrc" 1
  want "  ...and status names the doubt"       "$s_ambigref" 1
  want "  ...and still LISTS the task"         "$s_r3crit" 1
  want "  ...and --list agrees with the gate"  "$listagree" 1
  want "no mark lacks an actor"                "$markactor" 0
  want "a refuted critical leaves the gate"    "$gaterefuted" 1
  want "  ...and the exclusion is named"       "$s_refuted" 1
  want "absent counters are not read as zero"  "$s_absent" 1
  want "status reports the orphan"             "$s_orph" 1
  want "status reports the refusal"            "$s_amb" 1
  want "a clean repo says so out loud"         "$s_none" 1
  want "an unmeasurable gate says NOT MEASURED" "$s_unmeas" 1
  want "  ...and never says none outstanding"  "$s_falseclean" 0
  want "a broken listing fails, not empties"   "$listrc" 1
  want "an empty listing says it is empty"     "$listempty" 0
  want "probing a missing index makes no db"   "$strays" 0
  want "the id_ambiguous fixture was built"    "$precolalt" 0
  want "a pre-column index refuses the mark"   "$precolrc" 2 )
check $? "finding ids survive a merge, and addressed is recorded, retractable and independent of vindicated"
rm -rf "$rs"
fi

if step "every agent's declared tier matches the table that documents it"; then
# MODELS.md names a tier per agent and the frontmatter declares one; nothing compared them, so a
# tier could be raised in one place and read the other way in the other. The vocabulary already
# taught this: a list restated in four locations had drifted in all four, and the fix was not
# vigilance but a check. Same shape, and cheap enough that there was no reason to wait for the
# drift to happen first.
drift=0
for a in "$KIT"/agents/*.md; do
  nm=$(basename "$a" .md)
  declared=$(sed -n 's/^model: //p' "$a" | tr -d '\r' | head -1)
  [ -n "$declared" ] || { echo "  $nm declares no model:"; drift=1; continue; }
  # The row that names this agent, then the tier in that row's second column.
  documented=$(grep -F "\`$nm\`" "$KIT/docs/MODELS.md" | grep '^|' |
               sed -n 's/^[^|]*|[^|]*| *`\([a-z]*\)` *|.*/\1/p' | head -1)
  if [ -z "$documented" ]; then
    echo "  $nm is not named in the MODELS.md table"; drift=1
  elif [ "$declared" != "$documented" ]; then
    echo "  $nm declares '$declared', MODELS.md says '$documented'"; drift=1
  fi
done
check $drift "agent frontmatter and MODELS.md agree on every tier"
fi

if step "the pre-flight gates are commands, and a cp -r copy does not pass isolation"; then
# The two criticals the first trial execution left open, and both are about a gate that reads
# fine and does the wrong thing.
#
# ISOLATION. §4 mandated `git clone` then `git remote remove origin`, and §0 permitted "A COPY
# or a clone with its remote removed". A `cp -r` copy duplicates `.git/config` verbatim, so it
# keeps `origin` pointed at the subject -- and `git push` is a Bash call, which kit-guard.sh
# does not match. The removal procedure covered only the route nobody would take when in a
# hurry. The rule is now a PROPERTY of the copy and this proves the property is checked for
# both routes, especially the one that used to slip through.
pf="$WORK.preflight"; rm -rf "$pf"; mkdir -p "$pf"
( cd "$pf" || exit 1
  git init -q -b main subject 2>/dev/null
  ( cd subject || exit 1
    git config user.email a@b.c; git config user.name T
    echo hello > f.txt; git add -A; git commit -q --no-verify -m "seed" )
  P="$KIT/tooling/kit-preflight.sh"

  # The route that used to pass: a plain recursive copy. It has origin only if the source had
  # one, so give the source a remote first -- which is what a real subject has.
  git -C subject remote add origin https://example.invalid/subject.git
  cp -r subject copy_cp
  bash "$P" --isolated copy_cp >/dev/null 2>&1; cprc=$?

  # The route the protocol described, done right and done wrong.
  git clone -q --no-hardlinks subject clone_ok 2>/dev/null
  git -C clone_ok remote remove origin 2>/dev/null
  bash "$P" --isolated clone_ok >/dev/null 2>&1; okrc=$?
  git clone -q --no-hardlinks subject clone_bad 2>/dev/null
  bash "$P" --isolated clone_bad >/dev/null 2>&1; badrc=$?

  # A --shared clone BORROWS the subject`s object store through `alternates`: a path back that
  # `git remote -v` cannot show, and one that makes `git gc` in either repository able to
  # affect the other. Written as a plain `git clone` first, which was wrong -- a local clone
  # hardlinks objects but writes no alternates file, so the check passed and the assertion was
  # measuring nothing. Hardlinks and alternates are different mechanisms and only one of them
  # is what this detects.
  git clone -q --shared subject clone_alt 2>/dev/null
  git -C clone_alt remote remove origin 2>/dev/null
  bash "$P" --isolated clone_alt >/dev/null 2>&1; altrc2=$?

  # "Not a repository" and "no such path" must NOT read as isolated. A check that passes when
  # it could not run is the shape this whole file exists to refuse.
  mkdir -p notarepo
  bash "$P" --isolated notarepo >/dev/null 2>&1; nrrc=$?
  bash "$P" --isolated /nonexistent-path-for-conformance >/dev/null 2>&1; nprc=$?

  want() { [ "$2" = "$3" ] || { printf '    ^ %s: got %s, wanted %s\n' "$1" "$2" "$3" >&2; exit 1; }; }
  want "a cp -r copy is NOT isolated"        "$cprc"  1
  want "a clone with origin is NOT isolated" "$badrc" 1
  want "a --shared clone is NOT isolated"    "$altrc2" 1
  want "a de-remoted clone IS isolated"      "$okrc"  0
  want "a non-repository is not a pass"      "$nrrc"  1
  want "a missing path is not a pass"        "$nprc"  2 )
check $? "isolation is checked as a property of the copy, by whichever route it was made"

# SPEND. §0 queried the index straight after running an agent. Hooks append EVENTS; spend rows
# exist only once kit-index.sh derives them -- so a live recorder failed a check written to
# detect a dead one, and the box said STOP to a working kit.
sp="$WORK.spendpf"; rm -rf "$sp"; mkdir -p "$sp"
( cd "$sp" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  git add -A && git commit -q --no-verify -m "chore: seed"
  P="$KIT/tooling/kit-preflight.sh"
  # THE TWO FAULTS MUST REPORT DIFFERENTLY, and asserting only the exit code cannot see that --
  # a mutation that deleted the no-events branch survived, because the other branch also
  # returned 1 and the check could not say which. "The hook never fired" and "the hook fired
  # and nothing derived it" have different causes and different fixes; the message is the
  # deliverable, not the status.
  nonemsg=$(bash "$P" --spend 2>&1); nonerc=$?
  case "$nonemsg" in *"no spend EVENT has ever been recorded"*) nonesaid=1 ;; *) nonesaid=0 ;; esac

  # An event the indexer cannot derive a row from: kit-index.sh skips a spend event with no
  # transcript, so this is the "hook fired, derivation produced nothing" state exactly.
  printf '%s\n' '{"kind":"spend","at":"2026-01-01T00:00:00Z","transcript":"","scope":"session","agent":"x","model":"sonnet","turns":1,"tok_in":10,"tok_out":20,"cache_read":0,"cache_write":0,"context":100}' \
    >> .project/events.ndjson
  rm -f .project/index.db
  undermsg=$(bash "$P" --spend 2>&1); underrc=$?
  case "$undermsg" in *"no spend row was derived"*) undersaid=1 ;; *) undersaid=0 ;; esac

  # One spend EVENT that DOES derive, and no index at all: the exact state after an agent
  # finishes, and the state in which the old box said STOP to a working kit.
  printf '%s\n' '{"kind":"spend","at":"2026-01-02T00:00:00Z","transcript":"t1","scope":"session","agent":"x","model":"sonnet","turns":1,"tok_in":10,"tok_out":20,"cache_read":0,"cache_write":0,"context":100}' \
    >> .project/events.ndjson
  rm -f .project/index.db
  bash "$P" --spend >/dev/null 2>&1; liverc=$?
  want() { [ "$2" = "$3" ] || { printf '    ^ %s: got %s, wanted %s\n' "$1" "$2" "$3" >&2; exit 1; }; }
  want "no spend event at all is a STOP"   "$nonerc" 1
  want "  ...and names the dead hook"      "$nonesaid" 1
  want "an underived event is a STOP"      "$underrc" 1
  want "  ...and names the OTHER fault"    "$undersaid" 1
  want "a live hook passes without a prior rebuild" "$liverc" 0 )
check $? "spend capture is judged from the event log, not from whatever the last rebuild held"
rm -rf "$pf" "$sp"
fi

if step "a refused review is retried with the diagnostics, boundedly"; then
# The contract asks a reviewer for one JSON object. Across four live runs it was ignored three
# times, and each time a human read the diagnostics and repaired the reply by hand -- the
# intervention acceptance criterion 1 forbids. This is the mechanism that replaces the human.
#
# The reviewer here is a FIXTURE, not a model: it fails the first time and succeeds only if the
# validator's own diagnostics actually reach it. That is what makes this deterministic enough
# to live in CI, and it is also the assertion -- a loop that retried blindly would still pass a
# test that only counted attempts.
rr="$WORK.retry"; rm -rf "$rr"; mkdir -p "$rr/src"
( cd "$rr" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  printf -- '---
id: T-r
title: r
tier: T2
---
b
' > .project/tasks/T-r.md
  git add -A && git commit -q --no-verify -m "chore: seed"
  Q() { sqlite3 .project/index.db "$1" | tr -d '\015'; }

  # Bad first: fenced, and a summary past the 200-character cap. Good second, but ONLY if the
  # correction reached it.
  cat > rev.sh <<'REV'
#!/usr/bin/env bash
n=$(cat "$STATE" 2>/dev/null || echo 0); n=$((n+1)); printf '%s' "$n" > "$STATE"
prompt=$(cat)
if [ "$n" = 1 ]; then
  # Deliberately non-compliant three ways at once: prose preamble, a code fence, and a summary
  # past the 200-character cap. PRIOR-REPLY-MARKER is what attempt 2 looks for to prove the
  # retry carried this reply back; without it, "resend the same review" is addressed to a
  # process that cannot see what it said.
  long=$(awk 'BEGIN{printf "PRIOR-REPLY-MARKER "; while(i++<210)printf "x"}')
  printf 'Sure, here you go:\n\n```json\n{"verdict":"REJECT","findings":[{"class":"fail-open","severity":"major","summary":"%s"}]}\n```\n' "$long"
  exit 0
fi
# The retry must carry BOTH the diagnostics AND the original request. Checking only for the
# diagnostics passed while the request was being dropped -- and a stateless reviewer with no
# request returns nothing, which records as reason=empty: "a review looked and found nothing".
# Observed against a real reviewer on 2026-08-12.
case "$prompt" in
  *"REFUSED by the findings contract"*)
    case "$prompt" in
      *ORIGINAL-REQUEST-MARKER*)
        # And the reviewer's OWN previous reply must have come back with it, or "send that
        # same review again" is an instruction it cannot follow.
        case "$prompt" in
          *PRIOR-REPLY-MARKER*)
            printf '{"verdict":"REJECT","narrative":"n","findings":[{"class":"fail-open","severity":"major","lang":"bash","summary":"the diagnostics came back and this reply is the correction"}]}' ;;
          *) printf '{"findings":[]}' ;;
        esac ;;
      *) printf '{"findings":[]}' ;;
    esac ;;
  *) printf '{"findings":[]}' ;;
esac
REV
  # The marker is how the fixture proves the RETRY still carried the original request. Without
  # something from the request to look for, the check can only see the diagnostics and cannot
  # tell a coherent retry from one that dropped what was being asked.
  printf 'review it  ORIGINAL-REQUEST-MARKER' > p.txt
  STATE="$PWD/calls"; export STATE; rm -f "$STATE"
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent implementation-reviewer \
    --cmd "bash $PWD/rev.sh" --prompt-file p.txt --max-attempts 3 >/dev/null 2>&1
  ok=$?
  tries=$(cat "$STATE")

  # A reviewer that never complies must STOP, and must leave a row saying findings were lost.
  cat > never.sh <<'NEV'
#!/usr/bin/env bash
cat >/dev/null
n=$(cat "$STATE" 2>/dev/null || echo 0); printf '%s' "$((n+1))" > "$STATE"
echo "I will not comply."
NEV
  STATE="$PWD/calls2"; export STATE; rm -f "$STATE"
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent tester \
    --cmd "bash $PWD/never.sh" --prompt-file p.txt --max-attempts 2 >/dev/null 2>&1
  gave=$?
  tries2=$(cat "$STATE")

  # A reviewer command that itself fails is NOT a contract violation, and retrying a broken
  # invocation is how a loop spends a budget on nothing.
  # It COUNTS its calls, and the assertion is the count. Asserting only the exit status could
  # not tell "abandoned after one attempt" from "retried three times and gave up" -- both end
  # at 1 -- so the mutation that retried a broken invocation survived this check until the
  # count was added. A check that cannot distinguish the defect from the fix is decoration.
  cat > broke.sh <<'BRK'
#!/usr/bin/env bash
cat >/dev/null
n=$(cat "$STATE" 2>/dev/null || echo 0); printf '%s' "$((n+1))" > "$STATE"
exit 7
BRK
  STATE="$PWD/calls3"; export STATE; rm -f "$STATE"
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent tester \
    --cmd "bash $PWD/broke.sh" --prompt-file p.txt --max-attempts 3 >/dev/null 2>&1
  brc=$?
  tries3=$(cat "$STATE")

  # A MISSING prompt is a usage error before the first attempt. Ignoring it handed the reviewer
  # an empty prompt, whose empty reply recorded as reason=empty -- "a review found nothing" --
  # and exited 0. A review that never happened, reported clean. Critical, round 5.
  STATE="$PWD/calls4"; export STATE; rm -f "$STATE"
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent tester \
    --cmd "bash $PWD/rev.sh" --prompt-file no-such-file.txt --max-attempts 3 >/dev/null 2>&1
  nofile=$?
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent tester \
    --cmd "bash $PWD/rev.sh" --max-attempts 3 >/dev/null 2>&1
  noflag=$?
  # Neither may have called the reviewer at all.
  called=$([ -f "$STATE" ] && cat "$STATE" || printf '0')

  # A reviewer that does not read its stdin must not look like a broken command: piped, SIGPIPE
  # killed printf and pipefail reported the whole pipeline as failed.
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"findings\\":[{\\"class\\":\\"race\\",\\"severity\\":\\"nit\\",\\"summary\\":\\"this reviewer never read its stdin at all\\"}]}"\n' > nodrain.sh
  # The prompt must EXCEED the pipe buffer, or this control cannot fail. A short prompt fits in
  # the buffer, `printf` completes before the non-draining reader exits, and no SIGPIPE ever
  # happens -- so the mutation that pipes the prompt again passed this check until the prompt
  # got big. Real review prompts are briefs, not one-liners.
  awk 'BEGIN{while(i++<200000)printf "x"}' > big.txt
  bash "$KIT/tooling/kit-review-record.sh" --task T-r --agent documenter \
    --cmd "bash $PWD/nodrain.sh" --prompt-file big.txt --max-attempts 2 >/dev/null 2>&1
  nodrain=$?

  # A validator that FAILS is not a reviewer that was refused. Read as a refusal, the empty
  # correction became the next prompt and every remaining attempt reviewed nothing.
  bt="$PWD/brokenval"; mkdir -p "$bt"
  cp "$KIT/tooling/kit-review-record.sh" "$KIT/tooling/kit-finding.sh" "$KIT/tooling/kit-lib.sh" "$bt/"
  printf 'import sys\nsys.exit(1)\n' > "$bt/kit_findings.py"
  STATE="$PWD/calls5"; export STATE; rm -f "$STATE"
  bash "$bt/kit-review-record.sh" --task T-r --agent tester \
    --cmd "bash $PWD/never.sh" --prompt-file p.txt --max-attempts 4 >/dev/null 2>&1
  badval=$?
  tries5=$(cat "$STATE" 2>/dev/null || printf '0')

  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  rows=$(Q "SELECT COUNT(*) FROM finding;")
  summ=$(Q "SELECT summary FROM finding WHERE agent='implementation-reviewer';")
  gaps=$(Q "SELECT COUNT(*) FROM event WHERE kind='finding-gap';")
  # The gap must say WHICH review and WHY, not merely exist -- asserting the count alone was
  # the round-5 finding against this very fixture.
  gtask=$(Q "SELECT COUNT(*) FROM event WHERE kind='finding-gap' AND task_id='T-r' AND payload LIKE '%\"agent\":\"tester\"%' AND payload LIKE '%\"reason\":\"rejected\"%';")

  # Named one at a time. Ten conditions in a single `&&` chain report only "false", and a
  # fixture that cannot say WHICH guarantee broke costs a debugging session every time it goes
  # red. `check` cannot be used in here -- its counters would not survive the subshell -- so
  # the subshell names the failure and exits, and the one check outside reports it.
  want() { [ "$2" = "$3" ] || { printf '    ^ %s: got %s, wanted %s\n' "$1" "$2" "$3" >&2; exit 1; }; }
  want "corrected reply accepted"        "$ok"      0
  want "  ...on the second attempt"      "$tries"   2
  want "incorrigible reviewer gives up"  "$gave"    1
  want "  ...after exactly max attempts" "$tries2"  2
  want "broken command not retried"      "$brc"     1
  want "  ...called exactly once"        "$tries3"  1
  want "unreadable prompt refused"       "$nofile"  2
  want "missing prompt flag refused"     "$noflag"  2
  want "  ...reviewer never called"      "$called"  0
  want "non-draining reviewer accepted"  "$nodrain" 0
  want "  ...validator failure attempts" "$tries5"  1
  want "findings recorded"               "$rows"    2
  want "summary survived"                "$summ"    "the diagnostics came back and this reply is the correction"
  # Two tester gaps are expected here -- the incorrigible reviewer and the broken command --
  # so this asserts the SHAPE (task and reason are present and right), not an exact count.
  [ "$gtask" -ge 1 ] || { printf '    ^ no gap names both its task and reason=rejected\n' >&2; exit 1; }
  [ "$badval" != 0 ] || { printf '    ^ a validator failure exited 0\n' >&2; exit 1; }
  [ "$gaps" -ge 2 ] )
check $? "a refused reply is corrected and recorded; an incorrigible one stops and leaves a gap"
rm -rf "$rr"
fi

if step "the finding contract is defined in exactly one place"; then
# The vocabulary was restated in four files once and they all drifted. The FIELD LIST is the
# same hazard: an agent that lists the fields from memory will list them wrongly the day one
# changes. `kit-finding.sh --contract` is the single home, and this asserts the recorder and
# the validator still agree about what a finding is.
C=$(bash "$KIT/tooling/kit-finding.sh" --contract 2>/dev/null)
printf '%s' "$C" | grep -q 'summary   required' &&
printf '%s' "$C" | grep -q 'class     required' &&
printf '%s' "$C" | grep -q 'severity  required'
check $? "--contract names the three required fields"

# Both accessors answer "what may I send you", which is asked while READING, from wherever the
# reader happens to be standing. Run from a directory that is not an adopted project -- which
# is where the docs are read -- they must still answer. `--contract` did not, and the fix for
# that had no test, so moving it back inside the arg loop would have gone unnoticed. Run from a
# scratch dir with no profile, and also as a NON-first argument, which was a second regression.
nc="$WORK.nocontract"; rm -rf "$nc"; mkdir -p "$nc"
( cd "$nc" || exit 1
  bash "$KIT/tooling/kit-finding.sh" --contract 2>/dev/null | grep -q 'summary   required' || exit 1
  bash "$KIT/tooling/kit-finding.sh" --vocab 2>/dev/null | grep -q '^class:' || exit 1 )
check $? "--contract and --vocab answer outside an adopted project"
bash "$KIT/tooling/kit-finding.sh" --task T --vocab 2>/dev/null | grep -q '^class:'
check $? "and answer when they are not the first argument"
rm -rf "$nc"
# The validator must not carry its own copy of the vocabulary: it has to ASK for it, or the two
# drift the moment a class is added. Proved by narrowing the vocabulary at its one source and
# watching a previously-valid class be refused.
#
# The POSITIVE CONTROL is the point. The first version of this asserted only a non-zero exit,
# so it passed on a failed cp, a missing python3, or a syntax error -- a check that could not
# fail, in the guard against exactly that class, found by a T3 reviewer the next day
# (docs/LESSONS.md S1). Now the same copied tree must ACCEPT the finding before the narrowed
# one rejects it; if the copy is broken, the positive half fails and the step goes red.
vb="$WORK.vocabbreak"; rm -rf "$vb"; mkdir -p "$vb"
cp "$KIT/tooling/kit_findings.py" "$KIT/tooling/kit-lib.sh" "$KIT/tooling/kit-finding.sh" "$vb/"
GOOD='{"findings":[{"class":"fail-open","severity":"major","summary":"valid under the real vocabulary"}]}'
printf '%s' "$GOOD" | python3 "$vb/kit_findings.py" --validate >/dev/null 2>&1
pos=$?
sed -i.bak 's/^CLASSES=.*/CLASSES="only-this-one"/' "$vb/kit-finding.sh"; rm -f "$vb/kit-finding.sh.bak"
printf '%s' "$GOOD" | python3 "$vb/kit_findings.py" --validate >/dev/null 2>&1
neg=$?
[ "$pos" = 0 ] && [ "$neg" -ne 0 ]
check $? "the validator reads the vocabulary rather than restating it (accepts, then refuses)"
rm -rf "$vb"
fi

if step "an uninstrumented project is not reported as a free one"; then
# Spend is a MEASUREMENT, so its absence is information and must be printed. The section used
# to be gated on a non-empty table with no else, which made "the hooks never fired" and "the
# work cost nothing" byte-identical. Measured on the kit's own repo: 0 rows after twelve days
# and not one mention of cost in the output.
#
# BOTH branches are exercised. A step that only ran the populated one could not fail for the
# defect being fixed, which is the shape this suite exists to refuse.
sp="$WORK.spendrep"; rm -rf "$sp"; mkdir -p "$sp/sess/subagents" "$sp/src"
( cd "$sp" || exit 1
  git init -q -b main 2>/dev/null
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

  # EMPTY: the section must exist and must say it is not a zero.
  bash "$KIT/tooling/kit-index.sh"  >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q '^## Spend' STATUS.generated.md ||
    { printf '    ^ no Spend section at all when the table is empty\n' >&2; exit 1; }
  grep -q 'not a measurement of zero' STATUS.generated.md ||
    { printf '    ^ empty spend does not say it is unavailable rather than zero\n' >&2; exit 1; }
  grep -q 'UNAVAILABLE, not zero' STATUS.generated.md || exit 1
  # It must NOT print the populated section's furniture on an empty table.
  grep -q 'Billable input-token-equivalents' STATUS.generated.md &&
    { printf '    ^ the populated header printed with no rows behind it\n' >&2; exit 1; }

  # POPULATED: the real section returns, and the empty notice goes away.
  printf '{"type":"assistant","message":{"model":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":400,"cache_read_input_tokens":1000,"output_tokens":200}}}
' > sess/subagents/agent-A1.jsonl
  printf '{"agentType":"implementation-reviewer","spawnDepth":1}' > sess/subagents/agent-A1.meta.json
  : > sess.jsonl
  bash "$KIT/tooling/kit-spend.sh" --transcript "$PWD/sess.jsonl" --agent-id A1 --agent implementation-reviewer
  bash "$KIT/tooling/kit-index.sh"  >/dev/null 2>&1
  bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1
  grep -q 'Billable input-token-equivalents' STATUS.generated.md ||
    { printf '    ^ the populated Spend section did not return\n' >&2; exit 1; }
  grep -q 'not a measurement of zero' STATUS.generated.md &&
    { printf '    ^ the empty notice printed alongside real rows\n' >&2; exit 1; }
  # And the recorder itself works -- the hypothesis that it was broken was wrong, and this is
  # what keeps that answer true rather than remembered.
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM spend;' | tr -d '\015')" = 1 ] )
check $? "empty spend says unavailable, populated spend reports, and the recorder records"
rm -rf "$sp"
fi

if step "the trial protocol's unit matches the one the kit computes"; then
# docs/TRIAL-PROTOCOL.md fixes the unit a trial reports in, and a document is the easiest place
# for a number to drift out of agreement with the code. The weights are computed in exactly one
# place -- BTE in kit-status.sh -- and the protocol restates them in prose because a person has
# to read them. That restatement is the risk, so it is checked: the finding vocabulary was
# restated in four files once and all four drifted.
P="$KIT/docs/TRIAL-PROTOCOL.md"
[ -f "$P" ]; check $? "the trial protocol exists"
# Pulled from the source rather than typed here, so this step cannot itself become a third copy.
#
# EXACTLY ONE definition, asserted first. A second `BTE=` line would make the sed emit eight
# fields, and `set --` would then check only the first four while reporting success -- the
# check would silently stop covering the definition that was actually in use.
NBTE=$(grep -c '^BTE=' "$KIT/tooling/kit-status.sh")
[ "$NBTE" = 1 ]
check $? "kit-status.sh defines BTE exactly once (found $NBTE)"
W=$(sed -n 's/^BTE="(s\.tok_in\*\([0-9]*\) + s\.cache_write\*\([0-9]*\) + s\.cache_read\*\([0-9]*\) + s\.tok_out\*\([0-9]*\))"/\1 \2 \3 \4/p' "$KIT/tooling/kit-status.sh")
set -- $W
# Scaled by 100 in the SQL so the weights stay integers; the prose states them unscaled.
[ "${1:-}" = 100 ] && [ "${2:-}" = 125 ] && [ "${3:-}" = 10 ] && [ "${4:-}" = 500 ]
check $? "the weights are still 1 / 1.25 / 0.1 / 5 in kit-status.sh (read: $W)"
grep -q 'input×1 + cache-write×1.25 + cache-read×0.1 + output×5' "$P"
check $? "and the protocol states those same four weights"
# The protocol's central warning: the harness per-agent figure is context size, not cost. If
# that sentence goes, the next trial quotes the wrong column exactly as the first one did.
grep -q 'final context size' "$P" && grep -qi 'do NOT use the harness' "$P"
check $? "the protocol still warns off the harness per-agent figure"

# The two criticals the T2 review found before first use. Both are one sentence away from
# regressing, and both would be paid for by a trial on a real client codebase.
#
# 1. Isolation. "A copy or a read-only clone" left origin pointing at the subject, and git push
#    is a Bash call the guard never sees. The removed remote IS the control.
#
#    This checked for `git remote -v` in the prose, which was true of the document while its
#    §0 still offered "A COPY" as an alternative -- a phrasing that skipped the removal
#    entirely, since `cp -r` duplicates .git/config with origin intact. Prose agreeing with
#    prose is not the property. The check is now the COMMAND both sections point at, and
#    whether it actually refuses each route is proved in its own step.
grep -q 'git remote remove origin' "$P" && grep -q 'kit-preflight.sh --isolated' "$P"
check $? "the protocol removes the remote and verifies isolation with a command"
# §0 must not reintroduce the alternative that made the removal optional. Named exactly, so
# that rewording the box is fine and re-offering an unverified copy is not.
if grep -q 'A COPY or a clone with its remote removed' "$P"; then
  check 1 "S0 no longer offers an unverified copy as an alternative"
else
  check 0 "S0 no longer offers an unverified copy as an alternative"
fi
# The guard's matcher is quoted in the protocol as the reason. If the hook ever grows Bash
# coverage that sentence becomes false, so tie it to the hook rather than to prose.
grep -q '"matcher": "Write|Edit|NotebookEdit"' "$KIT/hooks/hooks.json"
check $? "the guard still matches only Write|Edit|NotebookEdit, as the protocol states"
# 2. The per-agent figure. The protocol must not mandate one the kit does not emit while also
#    forbidding the only way to derive it -- that pair is what made revision 1 unexecutable.
grep -q 'It does \*\*not\*\* emit a per-agent figure' "$P"
check $? "the protocol says plainly that no per-agent BTE is emitted"
# Asserted against the TRACKED SCHEMA, never against .project/index.db. That file is gitignored
# and derived, so it exists on a developer's machine and NOT on a fresh CI clone -- the first
# version of this check queried it, passed locally for that reason alone, and went red on both
# CI platforms within one push. LESSONS.md S9: the gate you cannot run locally is the one that
# catches you. A conformance check must depend only on what is committed.
sed -n '/CREATE TABLE spend/,/^);/p' "$KIT/tooling/schema.sql" | grep -qE '^  agent  *TEXT'
check $? "and spend still declares the agent column the protocol's query groups by"

# §7 names a template. Revision 1 named a shape with no file, so every trialist would have
# invented one and comparability would have died at the artefact.
[ -f "$KIT/docs/TRIALS/TEMPLATE.md" ]
check $? "the report template §7 points at exists"
fi

if step "the via vocabulary is defined in exactly one place"; then
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
fi

if step "a tier below its floor is reported"; then
# Under-tiering is silent and it is the dangerous direction. Two of three recorded tiers in a
# real backlog were below their floor -- and a floor computed only from touched files would
# have caught NONE of them, because 7 of 8 open tasks had no commits yet. Hence the declared
# paths source, which is what this exercises.
#
# Its own directory: an earlier version of this check mutated the shared fixture and broke
# the losslessness comparison three steps later.
tf="$WORK.floor"; rm -rf "$tf"; mkdir -p "$tf"
( cd "$tf" || exit 1
  git init -q -b main 2>/dev/null
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
fi

if step "the step filter cannot report a vacuous pass"; then
# `--only` is a development-loop convenience, but two of its failure modes are the exact
# shape this suite exists to refuse: a pattern that matches nothing reporting a clean run,
# and a filtered run reading like a whole one. Neither is visible by inspection and both
# are cheap to assert, so they are asserted rather than trusted.
#
# Every nested run is marked, and a marked run skips this step. Relying on the patterns
# below never naming this step is not enough: the `--bogus` case is a full run the moment
# its guard stops working, and that full run re-enters this step. Mutating that guard away
# turned the suite into a fork bomb, which is why the sentinel is here and not the comment
# that used to be.
if [ -n "${KIT_CONFORMANCE_NESTED:-}" ]; then
  skip "this run is itself one of those nested checks" "the step filter's own guarantees"
else
fx="$WORK.filter"; rm -rf "$fx"; mkdir -p "$fx"
export KIT_CONFORMANCE_NESTED=1
KIT="$KIT" WORK="$fx" bash "$SELF" --only 'zz-no-step-is-called-this' >"$fx/vac.out" 2>&1; rc=$?
[ "$rc" = 2 ]; check $? "a pattern matching no step exits 2 rather than passing with nothing run"
grep -q 'matched no step' "$fx/vac.out"; check $? "and names the pattern that matched nothing"

KIT="$KIT" WORK="$fx" bash "$SELF" --list >"$fx/list.out" 2>&1; rc=$?
nl=$(grep -c '^ *[0-9]' "$fx/list.out")
[ "$rc" = 0 ] && [ "${nl:-0}" -ge 2 ]; check $? "--list names the steps ($nl found) so a pattern can be chosen"

KIT="$KIT" WORK="$fx" bash "$SELF" --only 'environment' >"$fx/part.out" 2>&1
grep -q '^=== PARTIAL RUN' "$fx/part.out"; check $? "a filtered run announces itself as partial"
# The full run's tally is this line and nothing else on it. A filtered run that ever
# printed it would be indistinguishable from conformance in a pasted terminal.
grep -Eq '^=== [0-9]+ passed, [0-9]+ failed$' "$fx/part.out"; rc=$?
[ "$rc" -ne 0 ]; check $? "and never prints the full run's tally line"

KIT="$KIT" WORK="$fx" bash "$SELF" --only 'environment' --only 'validate' >"$fx/two.out" 2>&1
# Asserted on the selection line rather than by counting `=== ` headers, because the
# banners are `=== ` lines too and counting them passed this at four.
grep -qE '^ +2 of [0-9]+ steps will run\.$' "$fx/two.out"
check $? "two --only patterns select two steps, not one and not all"

# Paired with --only so that a build which stops refusing unknown arguments runs one cheap
# step rather than the whole suite. The discrimination is the same -- refused is exit 2,
# ignored is a clean exit 0 -- and the cost when it is ignored is bounded.
KIT="$KIT" WORK="$fx" bash "$SELF" --only 'environment' --bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ]; check $? "an unknown argument exits 2 rather than being ignored"
unset KIT_CONFORMANCE_NESTED
rm -rf "$fx"
fi
fi

if step "entry analysis reports an undocumented choice and writes no task"; then
# ADR 0001. The entry mechanism turns a codebase into FACTS, anchored to files, and writes no
# task anywhere. Both halves are asserted here, and the presence half is why this step exists:
# design 1's fixture asserted only absences, so a kit-entry.sh consisting of `exit 0` passed it.
#
# The fixture holds three source files chosen to pin the scanner from both directions:
# retry.go carries an undocumented constant (a real choice, no explanation), cache.go carries a
# 12-line rationale block, edge.go a 9-line one. The 9-line block must appear AT ITS TRUE
# LENGTH: the tool applies no minimum on the way out, because two of ten independently
# nominated rationale sites in this repository sit in runs of 3 and 5 lines and any >=10 gate
# discards them permanently. A filter the reader applies is recoverable; one the writer applies
# is not.
#
# No `grep -P`: BSD grep on the macOS runner does not have it, and the TSV field checks are awk.
en="$WORK.entry"; rm -rf "$en"; mkdir -p "$en/src"
( cd "$en" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1

  printf 'package main\n\nconst maxRetries = 7\n' > src/retry.go
  { echo 'package main'; echo
    echo '// Cache entries are evicted on write, not on read, because a read-path eviction'
    echo '// walks the whole map under the same lock the request holds. Measured at 40ms of'
    echo '// added tail latency on a 50k-entry cache, which is worse than the memory it saves.'
    echo '// The obvious simplification -- evict lazily when a reader finds a stale entry --'
    echo '// was tried and reverted: it moves the walk onto the hot path rather than removing'
    echo '// it, and it makes eviction time depend on read traffic, so a quiet cache never'
    echo '// evicts at all and a busy one evicts twice. Do not reintroduce it without a'
    echo '// benchmark on a cache of at least 50k entries, and read the revert first.'
    echo '// The write-path walk is bounded by the batch size, which is why it is acceptable'
    echo '// here and would not be acceptable on the read path.'
    echo '// See also the eviction test, which fails if this becomes lazy again.'
    echo '// Twelve lines, deliberately: this block is the fixture for run-length 12.'
    echo 'func evict() {}'; } > src/cache.go
  { echo 'package main'; echo
    echo '// Nine lines, deliberately. This block exists to prove the scanner applies no'
    echo '// minimum length of its own: it must appear in the runs file at length 9, not be'
    echo '// filtered out. Real rationale in this repository lives in runs this short --'
    echo '// kit-guard.sh carries three lines and kit-index.sh five -- so a scanner that'
    echo '// drops short runs drops exactly the rationale a reader most needs, while'
    echo '// reporting a clean list that looks complete. That failure is invisible: the'
    echo '// output is well-formed and simply missing things, which is the shape this'
    echo '// whole suite exists to refuse. Nine comment lines, counted: an off-by-one here'
    echo '// is caught by the exact-length assertion below rather than absorbed by it.'
    echo 'func edge() {}'; } > src/edge.go

  # A doc-shaped file, so the doc_shaped column is exercised in BOTH states. The column is
  # specified by ADR 0001 and was simply absent from the first implementation -- the table had
  # ten columns where the design says eleven, and nothing here noticed, because no assertion
  # named it. An unasserted column is an unimplemented column that happens to be documented.
  mkdir -p docs && printf '# Note\n\nWhy the retry count is 7.\n' > docs/note.md
  : > src/empty.py
  printf '.eslintrc\n' > .eslintrc
  # Committed now, deleted below. It lands in the co-change graph and NOT in the census, which is
  # the only way the coverage fraction's two populations can differ inside a fixture.
  printf 'package main\n// gone\nfunc gone() {}\n' > src/gone.go
  { echo 'int main(void) {'; echo '/*'; echo 'no leading star on these lines'
    echo 'and the block still runs to its close'; echo '*/'; echo 'return 0; }'; } > src/block.c
  git add -A && git commit -q --no-verify -m "chore: seed"
  printf 'package main\n\nconst maxRetries = 7\nvar _ = maxRetries\n' > src/retry.go
  rm -f src/gone.go
  git add -A && git commit -q --no-verify -m "feat: second commit"

  before=$(ls .project/tasks 2>/dev/null | wc -l | tr -d ' ')
  bash "$KIT/tooling/kit-entry.sh" >/dev/null 2>&1 || exit 1

  R=.project/entry-report.md; F=.project/entry-facts.tsv; C=.project/entry-comment-runs.tsv
  [ -f "$R" ] && [ -f "$F" ] && [ -f "$C" ] || exit 1

  # PRESENCE. Exact values, not `!= 0`. Three source files are counted and the three files
  # kit-init.sh commits are excluded AND counted -- an exclusion nobody can see is
  # indistinguishable from a file that was missed.
  grep -qx 'tracked_files 7'   "$R" || exit 1
  grep -qx 'skipped kit-owned 3' "$R" || exit 1
  grep -qx 'commits 2'         "$R" || exit 1
  grep -qE '^history (ok|degenerate|unavailable)' "$R" || exit 1
  grep -qE '^cochange (ok|empty)' "$R" || exit 1
  grep -qx 'comment_runs 3 in 3 files' "$R" || exit 1

  # Both run lengths pinned exactly, so a scanner off by one is red, and so is one that
  # silently reimposes a minimum length and drops the 9.
  awk -F'\t' '$1=="src/cache.go" && $4==12 {f=1} END{exit !f}' "$C" || exit 1
  awk -F'\t' '$1=="src/edge.go"  && $4==9  {f=1} END{exit !f}' "$C" || exit 1
  # The undocumented choice is REPORTED as a zero, never omitted. A file with no explanation is
  # the case the whole mechanism exists to surface, and dropping it would read as "nothing to
  # ask about here".
  awk -F'\t' '$1=="src/retry.go" && $4==0 {f=1} END{exit !f}' "$F" || exit 1
  # doc_shaped is field 10, and BOTH states are pinned: a file under a docs path is 1, a source
  # file is 0. Asserting only the 1 would pass against a column hardcoded to 1.
  awk -F'	' '$1=="docs/note.md" && $10==1 {f=1} END{exit !f}' "$F" || exit 1
  awk -F'	' '$1=="src/retry.go" && $10==0 {f=1} END{exit !f}' "$F" || exit 1
  # The census reconciles: every subject file is a row or a counted exclusion.
  grep -qx 'reconciled ok' "$R" || exit 1
  # Four behaviours from the previous review round had NO assertion until now. An unasserted
  # behaviour is indistinguishable from an unimplemented one -- which is exactly how doc_shaped
  # came to be specified in ADR 0001 and in the design, absent from the code, and green anyway.
  grep -qx 'merges 0' "$R" || exit 1
  grep -qx 'skipped scanfail 0' "$R" || exit 1
  # An empty file is TEXT with no content, not binary. It gets a row with lines 0.
  awk -F'\t' '$1=="src/empty.py" && $3==0 {f=1} END{exit !f}' "$F" || exit 1
  # A /* */ block whose interior lines carry no leading * is ONE run, at its true length.
  awk -F'\t' '$1=="src/block.c" && $4==4 {f=1} END{exit !f}' "$C" || exit 1
  # A subject's own root dotfile belongs to the SUBJECT, not to the kit.
  awk -F'\t' '$1==".eslintrc" {f=1} END{exit !f}' "$F" || exit 1

  # ABSENCE. Necessary, not sufficient -- every assertion above already failed for an
  # `exit 0` implementation.
  after=$(ls .project/tasks 2>/dev/null | wc -l | tr -d ' ')
  [ "$before" = "$after" ] || exit 1
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  [ "$(sqlite3 .project/index.db 'SELECT COUNT(*) FROM task;' | tr -d '\015 ')" = 0 ] || exit 1


  # No artefact may contain a line that reads as a task file's own grammar.
  grep -qE '^(id|tier|state): ' "$R" "$F" "$C" && exit 1
  exit 0 )
check $? "entry analysis reports the choice, counts its exclusions, and writes no task"
rm -rf "$en"
fi

if step "co-change coverage divides by the population it counted"; then
# `cochange ok N pairs, M of T files` printed `84 of 81` on this repository: a fraction above one.
# The numerator counted every file in the co-change graph -- task files, kit-owned files, files
# deleted years ago -- and the denominator counted only subject files that exist NOW. Two different
# populations, and the tell was that the answer was impossible rather than merely wrong.
#
# This needs its own repository. The entry fixture has two commits, and `cochange.hub_pct` treats a
# file appearing in more than 20% of commits as a hub -- so at two commits EVERY file is suppressed,
# the graph is empty, and an assertion placed there passes on `cochange empty` without ever reaching
# the branch. The first version of this check did exactly that and survived the mutation that
# reintroduces the defect.
cc="$WORK.cochange"; rm -rf "$cc"; mkdir -p "$cc/src"
( cd "$cc" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  # gone.go is committed and then deleted: it lives in the graph and not in the census, which is
  # the only way a fixture can make the two populations differ.
  printf 'package main\nfunc gone() {}\n' > src/gone.go
  git add -A && git commit -q --no-verify -m "chore: seed"
  # Twelve commits, each touching a disjoint pair, so no file exceeds the 20% hub threshold and
  # pairs actually form.
  i=1
  while [ "$i" -le 12 ]; do
    j=$((i + 1))
    printf 'package main\n// f%s\nfunc f%s() {}\n' "$i" "$i" > "src/f$i.go"
    printf 'package main\n// g%s\nfunc g%s() {}\n' "$j" "$j" > "src/g$j.go"
    git add -A && git commit -q --no-verify -m "feat: pair $i"
    i=$((i + 1))
  done
  rm -f src/gone.go
  git add -A && git commit -q --no-verify -m "chore: drop gone"
  bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
  bash "$KIT/tooling/kit-entry.sh" >/dev/null 2>&1 || exit 1
  R=.project/entry-report.md
  # The branch must actually be REACHED. On `cochange empty` everything below is vacuous, which is
  # how the first version of this check passed while measuring nothing.
  ccline=$(grep '^cochange ok ' "$R") || { echo "  the co-change graph is empty -- this step measured nothing"; exit 1; }
  m=$(printf '%s' "$ccline" | sed 's/.* \([0-9][0-9]*\) of \([0-9][0-9]*\) files.*/\1/')
  t=$(printf '%s' "$ccline" | sed 's/.* \([0-9][0-9]*\) of \([0-9][0-9]*\) files.*/\2/')
  [ "$m" -le "$t" ] || { echo "  coverage $m exceeds census $t"; exit 1; }
  # Positive half: the populations DO differ here, so the notice naming the difference must appear.
  # The inequality alone would still pass against a numerator counted over the whole graph.
  grep -q 'outside the census' "$R" || { echo "  the out-of-census notice is missing"; exit 1; }
  exit 0 )
check $? "co-change coverage counts subject files on both sides, and names what the graph holds beyond them"
rm -rf "$cc"
fi

if step "a proposal that cannot be pasted safely is refused, and a question is not a checkbox"; then
# The judgement half of the entry mechanism produces prose, and a fixture cannot gate a model.
# What it CAN gate is the file the orchestrator wrote from that prose, which is what --check reads.
#
# Two of these are the design's own rules rather than formatting taste. A question carries no
# checkbox, because the task this serves says an undocumented choice is a QUESTION and never work,
# and a tickbox invites closing instead of answering. And a candidate title must survive being
# pasted into a shell -- ADR 0001 recorded that as enforced by nobody, on the grounds that the tool
# never sees the titles, which stopped being true the moment the tool read the written proposal.
pr="$WORK.prop"; rm -rf "$pr"; mkdir -p "$pr"
( cd "$pr" || exit 1
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  git add -A && git commit -q --no-verify -m "chore: seed"
  { echo '## Open questions'; echo
    echo '1. Why is the retry count 7?'; echo '   evidence: src/retry.go:3'; echo '   answer:'; echo
    echo '## Candidate tasks'; echo
    echo '- [ ] Document the retry budget'
    echo "      kit-task.sh --title 'Document the retry budget' --tier T1"; echo
    echo '## Could not determine'; echo
    echo '- co-change: empty'; } > good.md

  bash "$KIT/tooling/kit-entry.sh" --check good.md >out.txt 2>&1 || exit 1
  grep -q 'proposal conforms' out.txt || exit 1
  # It said "none filed by this check", so prove it: no task file appeared.
  [ "$(ls .project/tasks 2>/dev/null | wc -l | tr -d ' ')" = 0 ] || exit 1

  # Each refusal separately, because one boolean over six conditions cannot say which broke.
  want() { bash "$KIT/tooling/kit-entry.sh" --check "$1" >/dev/null 2>&1; [ "$?" = 1 ] || { echo "  not refused: $2"; return 1; }; }
  sed "s/Document the retry budget' --tier/Document \`whoami\` budget' --tier/" good.md > backtick.md
  sed "s/Document the retry budget' --tier/Document \$(id) budget' --tier/"    good.md > dollar.md
  sed "s/Document the retry budget' --tier/Doc; rm -rf . budget' --tier/"      good.md > semi.md
  sed 's/^1\. Why/- [ ] Why/'            good.md > tickbox.md
  grep -v 'Could not determine'          good.md > nogaps.md
  grep -v 'kit-task.sh --title'          good.md > noline.md
  sed "s/Document the retry budget' --tier/Doc's budget' --tier/"  good.md > quote.md
  sed "s/Document the retry budget' --tier/Doc | tee b' --tier/"   good.md > pipe.md
  sed "s/Document the retry budget' --tier/Doc \& b' --tier/"      good.md > amp.md
  sed "s/Document the retry budget' --tier/Doc < b' --tier/"       good.md > lt.md
  sed "s/Document the retry budget' --tier/Doc > b' --tier/"       good.md > gt.md
  rc=0
  # Every character the docs claim is refused, not a sample of three. ADR 0001 asserted that a
  # conformance step proved EACH refusal while only three were tested -- and the quote, the one
  # that ends the quoting, was the one silently broken.
  want quote.md    'a single quote in a title'  || rc=1
  want pipe.md     'a pipe in a title'          || rc=1
  want amp.md      'an ampersand in a title'    || rc=1
  want lt.md       'a < in a title'             || rc=1
  want gt.md       'a > in a title'             || rc=1
  # Scoping the counts made these two INVISIBLE rather than wrong, which trades one silent state
  # for another. They are refused.
  { cat good.md; echo "      kit-task.sh --title 'Stray line' --tier T1"; } > stray.md
  sed 's/^- co-change: empty/- [ ] co-change: empty/' good.md > latebox.md
  want stray.md    'a kit-task.sh line outside the section' || rc=1
  want latebox.md  'a checkbox after the candidate section' || rc=1
  want backtick.md 'a backtick in a title'      || rc=1
  want dollar.md   'a $(...) in a title'        || rc=1
  want semi.md     'a semicolon in a title'     || rc=1
  want tickbox.md  'a checkbox on a question'   || rc=1
  want nogaps.md   'no could-not-determine'     || rc=1
  want noline.md   'a candidate with no kit-task.sh line' || rc=1
  # A usage error is NOT a refusal: exit 2 means the question could not be asked.
  bash "$KIT/tooling/kit-entry.sh" --check /nonexistent >/dev/null 2>&1; [ "$?" = 2 ] || rc=1
  exit $rc )
check $? "a conforming proposal passes, thirteen malformed ones are refused, and --check files nothing"
rm -rf "$pr"
fi

if step "greenfield and an imported history are the same mechanism, not special cases"; then
# The task's first acceptance criterion is that ONE mechanism handles all three starting
# conditions -- greenfield being brownfield with an empty inventory, modernization being
# brownfield plus a stack delta. That claim is cheap to make and was, in the design, entirely
# untested: the branches existed and had never once executed.
#
# THIS STEP COVERS TWO OF THE THREE. Greenfield and an imported history are here. MODERNIZATION IS
# NOT: its source-to-target delta lives in the solution overlay, which is unbuilt, so there is
# nothing to express it with and nothing to assert. Deferred by the operator on 2026-08-16 rather
# than quietly counted as covered -- see T-20260815-ac6-modernization-delta-is-claimed-but-u. An
# earlier version of this comment named all three conditions above a step that tests two, which is
# the shape where a reader checks the box because the comment said so.
#
# Three cases, because a state that is always the same value is not a state:
#   A  greenfield        no subject files at all      -> tracked_files 0, and it must not hang
#   B  imported history  files, exactly one commit    -> history degenerate, facts still full
#   C  the same repo     after a second commit        -> history ok
# C is what stops B passing for a script with `history degenerate` hardcoded. Without it the
# other two assertions are satisfied by a constant.
#
# Case A is also the `awk` with no file operands hazard, which this repo has been bitten by:
# an awk invoked with zero files reads stdin and waits forever, and a suite that hangs is
# read as a slow machine rather than as a defect.
gf="$WORK.green"; gi="$WORK.import"; rm -rf "$gf" "$gi"; mkdir -p "$gf" "$gi"
R=.project/entry-report.md; F=.project/entry-facts.tsv; C=.project/entry-comment-runs.tsv
( cd "$gf" || exit 1
  # --- A. greenfield: the kit is adopted and nothing else exists yet ---
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  git add -A && git commit -q --no-verify -m "chore: kit only"
  bash "$KIT/tooling/kit-entry.sh" >/dev/null 2>&1 || exit 1
  grep -qx 'tracked_files 0' "$R" || exit 1
  grep -qx 'comment_runs 0 in 0 files' "$R" || exit 1
  grep -qx 'markers 0' "$R" || exit 1
  # The facts file is a HEADER and no rows -- not an empty file, which would be
  # indistinguishable from a run that died before writing anything.
  [ "$(awk 'END{print NR}' "$F")" = 1 ] || exit 1
  [ "$(awk 'END{print NR}' "$C")" = 0 ] || exit 1
  exit 0 )
gfa=$?
# NOT `( ... ) || exit 1`. At top level that `exit` terminates the whole suite: the step prints
# its heading, nothing else, no verdict and no tally, and CI sees a non-zero status with no FAIL
# line to explain it. A mutation found this -- emptying the facts header made case A fail, and
# the run vanished instead of reporting. Each case's status is captured and both are handed to
# `check`, which is the only thing that records a result.
( cd "$gi" || exit 1
  # --- B. a vendor import: the kit files and the whole subject in ONE commit ---
  # It has to be one commit. Adopting, committing, then adding the sources is a TWO-commit
  # repository and reports `history ok` -- which is what the first version of this fixture
  # actually built, so it asserted `degenerate` against a repo that was not.
  git init -q -b main 2>/dev/null
  git config user.email a@b.c; git config user.name T
  bash "$KIT/tooling/kit-init.sh" >/dev/null 2>&1
  mkdir -p src
  printf 'package main\n// one\n// two\n// three\nfunc a() {}\n' > src/a.go
  printf 'package main\nfunc b() {}\n' > src/b.go
  git add -A && git commit -q --no-verify -m "chore: vendor import"
  bash "$KIT/tooling/kit-entry.sh" >/dev/null 2>&1 || exit 1
  grep -qx 'tracked_files 2' "$R" || exit 1
  grep -qx 'commits 1' "$R" || exit 1
  grep -qx 'history degenerate: single-commit history' "$R" || exit 1
  # The history is degenerate; the FILE FACTS are not. A single-commit subject must still get
  # its census, or "modernization is brownfield plus a delta" is false at the first subject
  # that arrives as a vendor drop.
  awk -F'\t' '$1=="src/a.go" && $4==3 {f=1} END{exit !f}' "$C" || exit 1

  # --- C. the same repository, one commit later ---
  # Without this, B is satisfied by a script with the string hardcoded. A state that only ever
  # takes one value is not a state.
  printf 'package main\nfunc b() { _ = 1 }\n' > src/b.go
  git add -A && git commit -q --no-verify -m "feat: second"
  bash "$KIT/tooling/kit-entry.sh" >/dev/null 2>&1 || exit 1
  grep -qx 'history ok' "$R" || exit 1
  grep -qx 'commits 2' "$R" || exit 1
  exit 0 )
gib=$?
[ "$gfa" = 0 ] && [ "$gib" = 0 ]
check $? "greenfield reports zeroes without hanging, a one-commit import reports degenerate history, and a second commit clears it"
[ "$gfa" = 0 ] || echo "  ^ the greenfield case failed"
[ "$gib" = 0 ] || echo "  ^ the imported-history case failed"
rm -rf "$gf" "$gi"
fi

if step "validate.py"; then
(cd "$KIT" && { python3 validate.py >/dev/null 2>&1 || python validate.py >/dev/null 2>&1; })
check $? "validate.py exits 0"
fi

if step "deterministic fixture" fixture; then
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
#   3. 2026-08-15: templates/project-profile.md gained `paths.adr` and `paths.design_input`
#      (ADR 0001). Same cause as 2 -- kit-init.sh copies the template into the seed commit.
#      The cause was established BEFORE re-pinning, as this comment requires, and the
#      evidence is: the previous commit still PASSED on the old pins, so the suite was not
#      broken; `git ls-tree -r` of the old and new seed trees differ in EXACTLY ONE blob,
#      `.claude/project-profile.md`; and `git cat-file -p` of the two blobs differs by
#      exactly the six added lines and nothing else. A full fresh-clone run was 64 passed,
#      1 failed, that one being this check -- so nothing else moved with it.
#   4. 2026-08-15: kit-init.sh now adds kit-entry.sh's four artefacts to the adoption
#      .gitignore, and .gitignore is in the seed commit. PREDICTED before the run rather than
#      diagnosed after it -- the mechanism is identical to 2 and 3, and a check whose next
#      failure you can name in advance is a check that is understood. Evidence, same discipline:
#      exactly one blob differs between the seed trees (`.gitignore`), its content differs by
#      exactly the four added lines, and the run was 67 passed with this as the only failure.
EXPECT_HEAD=d75b07d81cbc4c0053578d9614cbbaf5e9238790
# The seed alone, so a mismatch says WHICH half moved: seed intact means this script changed,
# seed moved means a file kit-init.sh commits did.
EXPECT_SEED=db3377a9af5aefd3879d228ccb9e78d8f5f5a12b
fi

if step "trailer hook" fixture; then
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
fi

if step "pipeline" fixture; then
bash "$KIT/tooling/kit-index.sh" > idx.log 2>&1
rc=$?; check $rc "kit-index.sh"
# Show why. Swallowing this cost a full CI round trip to diagnose a one-character fix.
[ $rc = 0 ] || { echo "  --- kit-index.sh output ---"; sed 's/^/  /' idx.log | head -20; }
grep -q "recovered by full-message scan" idx.log; check $? "recovers the squash-stranded trailers"
bash "$KIT/tooling/kit-plan.sh" --next 5 >/dev/null 2>&1; check $? "kit-plan.sh"
bash "$KIT/tooling/kit-status.sh" >/dev/null 2>&1; check $? "kit-status.sh"
fi

if step "derived state" fixture; then
sqlite3 -header .project/index.db "SELECT id,state,tier,lang,epic FROM task ORDER BY id;" | tr -d '\r'
sqlite3 .project/index.db "SELECT key,value FROM meta ORDER BY key;" | tr -d '\r'
fi

if step "timestamps are canonical UTC" fixture; then
# %aI would carry the author local offset and render differently across git versions, so
# the same history produced different indexes on different machines and ORDER BY compared
# offsets lexically. Everything must be ...Z.
n=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM event WHERE at NOT LIKE '%Z';" | tr -d '\r')
[ "${n:-1}" = 0 ]; check $? "every event.at ends in Z"
fi

if step "co-change" fixture; then
CC=$(sqlite3 .project/index.db "SELECT COUNT(*) FROM cochange;" | tr -d '\r')
[ "${CC:-0}" -gt 0 ]; check $? "co-change graph was built ($CC rows)"
sqlite3 .project/index.db "SELECT COUNT(*) FROM cochange WHERE src LIKE '%README%';" | tr -d '\r' | grep -qx 0
check $? "README excluded as a hub"
fi

if step "delete and rebuild is lossless" fixture; then
sqlite3 .project/index.db ".dump" | grep -v "INSERT INTO goal" | tr -d '\r' | LC_ALL=C sort > b.dump
rm -f .project/index.db
bash "$KIT/tooling/kit-index.sh" >/dev/null 2>&1
bash "$KIT/tooling/kit-plan.sh" --next 5 >/dev/null 2>&1
sqlite3 .project/index.db ".dump" | grep -v "INSERT INTO goal" | tr -d '\r' | LC_ALL=C sort > a.dump
cmp -s b.dump a.dump; check $? "rebuild is byte-identical"
fi

if step "CI gate" fixture; then
bash "$KIT/tooling/kit-trailers.sh" range "HEAD~1..HEAD" --enforce >/dev/null 2>&1
check $? "passes on a well-formed commit"
fi

if step "FINGERPRINT" fixture; then
H=$(git rev-parse HEAD)
printf '  head    %s\n' "$H"
# The fixture chain is fully determined, so under `--only` these two values are the
# same ones a full run prints -- but they cover the chain, not the suite, and an
# unlabelled fingerprint pasted out of a filtered run would claim otherwise.
[ -n "$ONLY" ] && printf '  (partial run: covers the fixture chain, not conformance)\n'
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
fi

if [ -n "$ONLY" ]; then
  # Deliberately not the same sentence as a full run. `35 passed, 0 failed` over a
  # filtered run would be a worse defect than the slowness the filter cures, so the
  # word PARTIAL, the pattern, and the number of steps that did not run all appear
  # before the counts anyone reads.
  printf '\n=== PARTIAL RUN --only %s\n' "$ONLY"
  printf '=== %d passed, %d failed' "$ok" "$bad"
  [ "$skipped" -gt 0 ] && printf ', %d NOT EXERCISED on this platform' "$skipped"
  printf ' over %d of %d steps; %d did not run\n' "$ran" "$STEP_COUNT" "$filtered"
  printf '=== NOT a conformance pass. Only the full run is, and only CI runs it on every platform.\n'
else
  printf '\n=== %d passed, %d failed' "$ok" "$bad"
  [ "$skipped" -gt 0 ] && printf ', %d NOT EXERCISED on this platform' "$skipped"
  printf '\n'
fi
exit $bad
