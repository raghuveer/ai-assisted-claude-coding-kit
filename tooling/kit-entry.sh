#!/usr/bin/env bash
# kit-entry.sh          turn an existing codebase into FACTS, anchored to files
#
# Writes three derived artefacts under `paths.state` and NOTHING else, ever:
#
#   entry-facts.tsv        one row per tracked file, uncapped
#   entry-comment-runs.tsv one row per run of consecutive comment lines, uncapped
#   entry-report.md        totals, degeneracy states, markers -- bounded, and every section
#                          states its ranking key
#
# It writes no task file, no SQL and no index row. That refusal is the only structural control
# in the entry design (ADR 0001) and it is exactly as strong as this script having no code that
# writes one -- the orchestrator that calls it holds Write and Bash, and kit-task.sh is not a
# gate. Stated, not pretended.
#
# WHY THERE IS NO AGGREGATION UNIT. A first design grouped by top-level directory ("areas") and
# inferred "this area has no rationale" from the doc-shaped files in it. Measured against three
# real repositories that was false in both directions: on THIS repository `tooling/` -- 1,554
# comment lines at 34.1% density, the densest rationale in the project -- reported zero, and on
# prometheus 13 of 23 areas reported zero including `config/` at 224 files. Directory
# attribution also destroys history: `(root)` absorbs 72% of prometheus's commits and 94% of
# actix-web's, because top-level files are touched constantly. So every fact here is anchored to
# a file, and the grouping is the model's job.
#
# WHY NOTHING IS CAPPED OR THRESHOLDED. The same measurement, on comment runs: a top-40 ranked
# section recovered 6 of 10 independently nominated rationale sites and did not move between a
# 4-line and a 12-line threshold, because the cap was doing the losing, not the threshold.
# Uncapped, all ten are reachable. Two of them sit in runs of 3 and 5 lines, so any minimum
# length applied HERE discards them permanently, while a reader can always filter a column.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 2; }
kit_active "$ROOT" || { kit_warn "kit not adopted here (no .claude/project-profile.md)"; exit 2; }
cd "$ROOT" || exit 1

# ---- --check: validate a proposal a model returned, before a human reads it -------------------
# Dispatched early, like kit-finding.sh's --vocab, because it neither reads the tree nor writes an
# artefact. It READS one file and returns a status.
#
# The format it enforces is docs/ENTRY-PROPOSAL.md. Two of the rules are load-bearing rather than
# cosmetic:
#
#   A question carries NO checkbox. A checkbox is a thing to tick and be done with; a question is
#   a thing to answer. This task exists because an undocumented design choice must be raised as a
#   QUESTION and never filed as work, and a tickbox beside one invites exactly the closing-without-
#   answering that the rule forbids.
#
#   A candidate title must be SAFE TO PASTE. ADR 0001 records the charset restriction as enforced
#   by nobody, on the grounds that "the tool never sees the titles" -- true of the design as
#   written, because the tool wrote facts and the model wrote the proposal. It is false here: the
#   orchestrator writes the file and this reads it back, so the shell metacharacters that would
#   execute at paste time can be refused rather than requested. Read the ADR knowing that.
#
# It does NOT enforce the hold. Nothing here stops anyone running kit-task.sh before a single
# question is answered, and a check that validated the shape and let the list be filed anyway
# would look like a gate while gating nothing.
if [ "${1:-}" = "--check" ]; then
  P=${2:-}
  [ -n "$P" ] || { kit_warn "usage: kit-entry.sh --check <proposal-file>"; exit 2; }
  [ -f "$P" ] || { kit_warn "no such proposal file: $P"; exit 2; }
  bad=0
  qline=$(grep -n '^## Open questions' -- "$P" | head -1 | cut -d: -f1)
  cline=$(grep -n '^## Candidate tasks' -- "$P" | head -1 | cut -d: -f1)
  uline=$(grep -n '^## Could not determine' -- "$P" | head -1 | cut -d: -f1)
  [ -n "$qline" ] || { kit_warn "no '## Open questions' section"; bad=1; }
  [ -n "$cline" ] || { kit_warn "no '## Candidate tasks' section"; bad=1; }
  [ -n "$uline" ] || { kit_warn "no '## Could not determine' section -- an analysis silent about its own gaps reads as complete"; bad=1; }
  # ... and the heading alone is not the section. An empty one is silence with a title on it.
  if [ -n "$uline" ] && ! awk -v a="$uline" 'NR>a && NF && $0 !~ /^##/ {found=1} END{exit !found}' < "$P"; then
    kit_warn "'## Could not determine' is empty -- a heading is not a disclosure"; bad=1
  fi
  if [ -n "$qline" ] && [ -n "$cline" ]; then
    [ "$qline" -lt "$cline" ] ||
      { kit_warn "questions must come BEFORE candidates: a reader meets the unknowns first"; bad=1; }
    if awk -v a="$qline" -v b="$cline" 'NR>a && NR<b && /^[[:space:]]*[-*][[:space:]]*\[[ xX]\]/ {found=1} END{exit !found}' < "$P"; then
      kit_warn "a question carries a checkbox -- a question is answered, not ticked"; bad=1
    fi
  fi
  ncand=0; nq=0
  # BOTH counts are scoped to the candidate section. Unscoped, they could balance ACROSS sections:
  # `ncand` counted every checkbox after the heading, including any in `## Could not determine`,
  # and `nlines` grepped the whole file -- so a candidate MISSING its command line and a stray
  # command line elsewhere cancelled out, and the check passed on a proposal wrong in both places.
  # Two wrong numbers agreeing is the failure mode, which is why the fixture asserts each
  # separately rather than testing one file with both defects.
  cend=$(awk -v a="${cline:-0}" 'NR>a && /^## / {print NR; exit}' < "$P")
  [ -n "$cend" ] || cend=$(awk 'END{print NR+1}' < "$P")
  [ -n "$cline" ] && ncand=$(awk -v a="$cline" -v z="$cend" 'NR>a && NR<z && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {n++} END{print n+0}' < "$P")
  [ -n "$qline" ] && [ -n "$cline" ] && nq=$(awk -v a="$qline" -v b="$cline" 'NR>a && NR<b && /^[[:space:]]*[0-9]+\./ {n++} END{print n+0}' < "$P")
  nlines=$(awk -v a="${cline:-0}" -v z="$cend" 'NR>a && NR<z && /kit-task\.sh --title/ {n++} END{print n+0}' < "$P")
  # Scoping alone would make a stray checkbox or command line OUTSIDE the candidate section
  # invisible rather than wrong, which trades one silent state for another. They are refused: a
  # checkbox in `## Could not determine` is actionable work filed as a gap, and a command line
  # loose in the document is a paste sitting outside the list a human is reviewing.
  if [ -n "$cend" ]; then
    awk -v z="$cend" 'NR>=z && /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {found=1} END{exit !found}' < "$P" &&
      { kit_warn "a checkbox appears after the candidate section -- work does not belong in a gaps list"; bad=1; }
    awk -v z="$cend" 'NR>=z && /kit-task\.sh --title/ {found=1} END{exit !found}' < "$P" &&
      { kit_warn "a kit-task.sh line appears outside the candidate section"; bad=1; }
  fi
  [ "$ncand" = "$nlines" ] ||
    { kit_warn "$ncand candidate(s) but $nlines kit-task.sh line(s) -- every candidate carries the literal line the operator runs"; bad=1; }
  # WHITELIST THE WHOLE LINE. Do not extract the title and then inspect it: extraction has to
  # assume the quoting is well formed, and the one character that makes it malformed is the single
  # quote -- the very character most worth refusing. Two attempts got this wrong in opposite
  # directions and both were fail-open:
  #
  #   `[^\n]*` -- BSD read the class as "not backslash, not n", the substitution never matched,
  #               nothing was inspected, and EVERY title passed. Green on ubuntu, red on macos.
  #   `[^']*`  -- stops at the first quote, so `--title 'Doc's budget'` yields `Doc`, which is
  #               clean, and the quote arm became unreachable. Green on BOTH platforms while
  #               accepting the exact input it existed to refuse.
  #
  # So the shape is inverted: the line must MATCH a grammar of things known to be safe, and
  # anything else is refused unread. An unparseable line is refused rather than parsed, which is
  # the fail-closed direction. Adding a flag to kit-task.sh means adding it here, deliberately.
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    printf '%s\n' "$ln" | grep -qE "^[[:space:]]*kit-task\.sh --title '[A-Za-z0-9 ._-]+'([[:space:]]+--tier T[0-3])?([[:space:]]+--lang [A-Za-z0-9+#_-]+)?([[:space:]]+--epic [A-Za-z0-9_-]+)?[[:space:]]*$" ||
      { kit_warn "candidate line is not safe to paste: $ln"; bad=1; }
  done <<EOF
$(grep 'kit-task\.sh --title' < "$P")
EOF
  if [ "$bad" = 0 ]; then
    printf 'kit: proposal conforms -- %s question(s), %s candidate(s), none filed by this check\n' "$nq" "$ncand"
    exit 0
  fi
  exit 1
fi

PROFILE=$(kit_profile "$ROOT")
STATE=$(kit_cfg "$PROFILE" paths.state ".project")
TASKS=$(kit_cfg "$PROFILE" paths.tasks ".project/tasks")
OUTDIR="$ROOT/$STATE"
mkdir -p "$OUTDIR" || exit 1

FACTS="$OUTDIR/entry-facts.tsv"
RUNS="$OUTDIR/entry-comment-runs.tsv"
REPORT="$OUTDIR/entry-report.md"

# Every sort in this script is LC_ALL=C. A locale-dependent collation makes two runs on two
# machines disagree about the order of the same rows, which is the reproducibility the whole
# artefact rests on.
export LC_ALL=C

# ---- 1. the file list, and what is excluded from it ------------------------------------------
# Excluded: the kit's own footprint. A subject adopted five minutes ago would otherwise report
# the profile and the ignore rules as part of its own code, and the count that a fixture pins
# would drift with kit-init.sh rather than with the subject.
#
# The exclusion is COUNTED. An exclusion nobody can see is indistinguishable from a file that
# was missed, and this script's entire value is that its absences are legible.
ALL=$(git ls-files) || { kit_warn "git ls-files failed"; exit 1; }
KITOWNED=0; SUBJECT=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    .claude/*|"$STATE"/*|"$TASKS"/*) KITOWNED=$((KITOWNED+1)); continue ;;
    # NAMED, not shaped. This used to exclude every top-level dotfile, which is right for the two
    # files kit-init.sh writes and wrong for every other one a real subject keeps at its root --
    # .eslintrc, .golangci.yml, .dockerignore, .editorconfig, .nvmrc. Those are the subject's own
    # configuration, and excluding them put the subject's files under the KIT's label, where a
    # reader had no way to tell whose they were. If kit-init.sh starts writing another root file,
    # add it here deliberately rather than widening the pattern until the count looks right.
    .gitignore|.gitattributes) KITOWNED=$((KITOWNED+1)); continue ;;
  esac
  SUBJECT="$SUBJECT$f
"
done <<EOF
$ALL
EOF
NFILES=$(printf '%s' "$SUBJECT" | grep -c . || true)

# ---- 2. history, per file, and whether it is usable at all -----------------------------------
# `git log --name-only` once, not once per file: a repository with 18k commits and 1.6k files
# would otherwise be 1.6k git invocations.
#
# HISTORY DEGENERACY IS A STATE, NOT A ZERO. A subject imported as a single vendor commit -- the
# ordinary case for modernization -- has one date, one author and identical churn everywhere.
# Reporting that as measurements invites the reader to draw conclusions from noise.
NCOMMITS=$(git rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$NCOMMITS" = 0 ]; then HISTORY="unavailable: no commits"
elif [ "$NCOMMITS" = 1 ]; then HISTORY="degenerate: single-commit history"
else HISTORY="ok"; fi

NMERGES=$(git rev-list --count --merges HEAD 2>/dev/null || echo 0)
# `git log --name-only` prints NO file list for a merge commit, so on a merge-heavy history every
# per-file `commits` and `authors` here is a LOWER BOUND. The alternative, `-m`, walks each parent
# separately and counts the same change twice -- an overcount traded for an undercount. Neither is
# right, so the count stays as it is and the number of merges is published beside it: `merges 0`
# means the counts are exact, `merges 4000` tells a reader exactly what to distrust.
HIST=$(git log --format='C|%H|%ad|%ae' --date=short --name-only 2>/dev/null || true)

# ---- 3. co-change: read, never recompute -----------------------------------------------------
# An empty table has FIVE causes and today the index cannot tell them apart -- the four early
# exits in kit-index.sh's co-change block all return before the cochange_* meta rows are
# written (T-20260815-co-change-withheld-disabled-and-empty-ar). So an empty table is reported
# as "did not look", never as "no structural relationships exist", and the filed defect is named
# so the next reader knows the ambiguity is known rather than overlooked.
CC="empty: indistinguishable from withheld / disabled / no history / no index (T-20260815-co-change-withheld-disabled-and-empty-ar)"
CCDEG=""
DB="$OUTDIR/index.db"
if [ -f "$DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  ccpairs=$(sqlite3 "$DB" "SELECT COUNT(*) FROM cochange;" 2>/dev/null | tr -d '\015 ' || true)
  if [ -n "${ccpairs:-}" ] && [ "$ccpairs" -gt 0 ] 2>/dev/null; then
    # INTERSECTED with the census, not counted independently. The co-change graph is built by
    # kit-index.sh over every file in history -- task files, kit-owned files, files deleted years
    # ago -- while the census counts only subject files that exist now. Dividing one by the other
    # printed `84 of 81 files`, a coverage fraction above 1, which is the honest tell that the
    # numerator and denominator were different populations. Both sides are now the same set.
    CCDEG=$(sqlite3 "$DB" "SELECT REPLACE(src,'f:',''), COUNT(*) FROM cochange GROUP BY src;" 2>/dev/null | tr -d '\015')
    ccall=$(printf '%s\n' "$CCDEG" | grep -c '|' || true)
    ccfiles=$(printf '%s\n' "$CCDEG" | awk -F'|' -v subj="$SUBJECT" '
      BEGIN { n=split(subj,S,"\n"); for (i=1;i<=n;i++) if (S[i] != "") keep[S[i]]=1 }
      $1 != "" && ($1 in keep) { c++ } END { print c+0 }')
    CC="ok $ccpairs pairs, $ccfiles of $NFILES files"
    [ "$ccall" = "$ccfiles" ] ||
      CC="$CC (the graph also holds $((ccall - ccfiles)) file(s) outside the census: history reaches further back than the tree)"
  fi
fi

# ---- 4. per-file counts, and the comment runs ------------------------------------------------
# Comment tokens are NOT chosen by file extension. Choosing by extension hid this repository's
# 5th-longest rationale block -- 27 lines at kit-index.sh:935-961 -- because it is SQL comments
# inside a bash heredoc. Embedded languages are ordinary: SQL in shell and Go, awk in shell, JS
# in HTML. A file is scanned for the union, and a run may not MIX tokens, so a `#` block and a
# `--` block that touch are two runs rather than one.
#
# File selection is by extension OR a `#!` first line, because tooling/commit-msg and
# tooling/pre-push are real shell scripts with no extension and one of them was independently
# nominated as load-bearing rationale.
: > "$RUNS.tmp"
: > "$FACTS.tmp"
# Truncated like its siblings. It was appended to and never cleared, so a run killed part
# way left stale rows that the NEXT run counted as its own skips.
: > "$FACTS.miss"
SKIPBIN=0; SKIPUNREAD=0

printf '%s\n' "$SUBJECT" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || { printf 'unreadable\t%s\n' "$f" >> "$FACTS.miss"; continue; }
  # `--` on every one of these. A tracked file named `-n` or `--version` is legal in git and is
  # parsed as OPTIONS by grep, head and awk -- so it would be miscounted as binary, or change
  # the behaviour of the tool that reads it, rather than being scanned. Rare, and silent, which
  # is the combination that makes it worth guarding rather than assuming.
  #
  # A NUL byte means binary. Counted, never silently dropped.
  # `grep -qI ''`, not `grep -qI .` -- and an explicit empty-file case before it. The old test
  # needed a line containing at least one CHARACTER, so an empty file and a file of only blank
  # lines both matched nothing and were filed under `skipped binary`: a tracked `__init__.py` or
  # `.gitkeep` vanished from the census under a label saying it was unreadable, and the
  # reconciliation still balanced, which is what made it quiet. `-I` is what detects binary; the
  # pattern only has to match a line, and an empty pattern matches a blank one.
  if [ ! -s "$f" ] || LC_ALL=C grep -qI '' -- "$f" 2>/dev/null; then :; else
    printf 'binary\t%s\n' "$f" >> "$FACTS.miss"; continue
  fi
  ext=${f##*/}; case "$ext" in *.*) ext=".${ext##*.}" ;; *) ext="(none)" ;; esac
  # doc_shaped is a fact ABOUT THIS FILE -- its name and its path -- and never an inference about
  # a directory. "This area has no rationale" is the claim design 1 died on; "this file is named
  # like documentation" is checkable and is all that is asserted here.
  docshaped=0
  case "$f" in
    docs/*|doc/*|*/docs/*|*/doc/*) docshaped=1 ;;
  esac
  case "${f##*/}" in
    README*|readme*|CHANGELOG*|changelog*|CONTRIBUTING*|ADR-*|adr-*|RFC-*|rfc-*|*.md|*.rst|*.adoc) docshaped=1 ;;
  esac
  scan=0
  case "$f" in
    *.sh|*.py|*.yml|*.yaml|*.sql|*.rs|*.go|*.ts|*.tsx|*.js|*.c|*.h|*.cpp|*.java|*.rb|*.pl) scan=1 ;;
    *.md|*.txt|*.json|*.lock) scan=0 ;;
    *) case "$(head -c 2 -- "$f" 2>/dev/null)" in '#!') scan=1 ;; esac ;;
  esac
  # `--` goes BEFORE the program text. After it, `--` is a FILENAME, not an option terminator --
  # awk then tries to open a file called `--`, every scan fails, and entry-facts.tsv comes out as
  # a header with no rows. That is exactly what the first version of this guard did, and only
  # looking at the output caught it: the loop's exit status was still fine.
  awk -v path="$f" -v ext="$ext" -v scan="$scan" -v docshaped="$docshaped" -v runsfile="$RUNS.tmp" -- '
    # A /* */ block whose interior lines are NOT prefixed with `*` used to end the run at the
    # opening line: the most common C and Go layout survives only because gofmt writes the
    # leading star. So the block is tracked as a STATE. Everything between `/*` and `*/` is a
    # comment line with token `*`, whatever it starts with.
    function tok(l) {
      if (inblock) { if (l ~ /\*\//) inblock = 0; return "*" }
      if (l ~ /^[[:space:]]*\/\*/) { if (l !~ /\*\//) inblock = 1; return "*" }
      if (l ~ /^[[:space:]]*#/)   return "#"
      if (l ~ /^[[:space:]]*\/\//) return "//"
      if (l ~ /^[[:space:]]*--/)  return "--"
      if (l ~ /^[[:space:]]*\*/)  return "*"
      return ""
    }
    { lines = NR
      if (!scan) next
      k = tok($0)
      if (k != "" && k == cur) { run++ }
      else {
        if (run > 0) { printf "%s\t%d\t%d\t%d\t%s\n", path, start, NR-1, run, cur >> runsfile; blocks++ }
        if (k != "") { cur = k; run = 1; start = NR } else { cur = ""; run = 0 }
      }
      if (k != "") cl++
    }
    END {
      if (run > 0) { printf "%s\t%d\t%d\t%d\t%s\n", path, start, NR, run, cur >> runsfile; blocks++ }
      # lines from NR, never `wc -l`: BSD wc pads its output with spaces and the field would
      # then carry them into the TSV.
      printf "%s\t%s\t%d\t%d\t%d\t%d\n", path, ext, lines+0, cl+0, blocks+0, docshaped+0
    }' "$f" >> "$FACTS.tmp" || printf 'scanfail	%s
' "$f" >> "$FACTS.miss"
done

SCANFAIL=0
[ -f "$FACTS.miss" ] && {
  SKIPBIN=$(grep -c '^binary' "$FACTS.miss" || true)
  SKIPUNREAD=$(grep -c '^unreadable' "$FACTS.miss" || true)
  SCANFAIL=$(grep -c '^scanfail' "$FACTS.miss" || true)
}

# The invariant that makes the table trustworthy: every subject file is either a row or a
# counted exclusion. Without it a per-file awk that dies mid-loop removes a file from the census
# silently, and the report still says `tracked_files N` -- a complete-looking table missing
# things, which is the failure this whole tool exists to refuse. Reported, never fatal: the
# artefacts are still worth having, and a reader who cannot see the discrepancy cannot judge it.
ROWS=$(awk 'END{print NR}' "$FACTS.tmp")
ACCOUNTED=$((ROWS + SKIPBIN + SKIPUNREAD + SCANFAIL))
RECONCILED="ok"
[ "$ACCOUNTED" = "$NFILES" ] || RECONCILED="MISMATCH: $ACCOUNTED accounted for, $NFILES tracked"

# ---- 5. join history onto the per-file rows --------------------------------------------------
printf 'path\text\tlines\tcomment_lines\tcomment_blocks\tcommits\tfirst\tlast\tauthors\tdoc_shaped\tcochange_degree\n' > "$FACTS"
printf '%s\n' "$HIST" | awk -v facts="$FACTS.tmp" -v deg="$CCDEG" '
  BEGIN {
    n = split(deg, dl, "\n")
    for (i = 1; i <= n; i++) { split(dl[i], d, "|"); if (d[1] != "") degree[d[1]] = d[2] }
  }
  /^C\|/ { split($0, p, "|"); date = p[3]; who = p[4]; next }
  NF && date != "" {
    c[$0]++
    if (first[$0] == "" || date < first[$0]) first[$0] = date
    if (last[$0]  == "" || date > last[$0])  last[$0]  = date
    if (!( ($0 SUBSEP who) in seen)) { seen[$0 SUBSEP who] = 1; au[$0]++ }
  }
  END {
    while ((getline line < facts) > 0) {
      split(line, f, "\t")
      printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%d\t%s\t%d\n",
        f[1], f[2], f[3], f[4], f[5],
        c[f[1]]+0, (first[f[1]]=="" ? "-" : first[f[1]]), (last[f[1]]=="" ? "-" : last[f[1]]),
        au[f[1]]+0, f[6], degree[f[1]]+0
    }
  }' | sort -t"$(printf '\t')" -k1,1 >> "$FACTS"

sort -t"$(printf '\t')" -k1,1 -k2,2n "$RUNS.tmp" > "$RUNS"
NRUNS=$(grep -c . "$RUNS" || true)
NRUNFILES=$(cut -f1 "$RUNS" | sort -u | grep -c . || true)

MARKERS=$(printf '%s\n' "$SUBJECT" |
  grep -E '(^|/)(go\.mod|package\.json|Cargo\.toml|Dockerfile|pom\.xml|pyproject\.toml|requirements\.txt|[^/]*\.csproj)$' |
  sort || true)
NMARKERS=$(printf '%s' "$MARKERS" | grep -c . || true)

# ---- 6. the report ---------------------------------------------------------------------------
# Bounded, and every section names its ranking key in its own heading. There is deliberately no
# per-file section: an unnamed sort over the first N of 20,000 files is the tool choosing the
# answer, which is the aggregation decision ADR 0001 forbids, reimposed through a tiebreak.
{
  printf '# Entry facts — %s\n\n' "$(basename "$ROOT")"
  printf 'GENERATED by kit-entry.sh. Derived and disposable: delete it, run again, lose nothing.\n'
  printf 'It proposes nothing and files nothing. Per-file data is in `entry-facts.tsv`;\n'
  printf 'comment runs are in `entry-comment-runs.tsv`, uncapped and unfiltered — grep them.\n\n'
  printf '## Totals\n\n'
  printf 'tracked_files %d\n' "$NFILES"
  printf 'commits %d\n' "$NCOMMITS"
  printf 'history %s\n' "$HISTORY"
  printf 'cochange %s\n' "$CC"
  printf 'comment_runs %d in %d files\n' "$NRUNS" "$NRUNFILES"
  printf 'skipped kit-owned %d\n' "$KITOWNED"
  printf 'skipped binary %d\n' "$SKIPBIN"
  printf 'skipped unreadable %d\n' "$SKIPUNREAD"
  printf 'skipped scanfail %d\n' "$SCANFAIL"
  printf 'reconciled %s\n' "$RECONCILED"
  printf 'merges %d\n' "$NMERGES"
  printf '\n## Marker files (ranked by path, ascending; all shown)\n\n'
  # An empty section is NOT an empty answer. Printing the heading and nothing under it reads
  # identically to a scan that never ran, which is the absent-is-not-zero failure this kit
  # refuses everywhere else -- and it is what this section did on its first real run, against
  # this repository, which has no marker files at all. The count always prints.
  printf 'markers %d\n' "$NMARKERS"
  [ "$NMARKERS" = 0 ] && printf '(none — no dependency-manifest file matched; this is a measured zero, not an absent scan)\n'
  printf '%s\n' "$MARKERS" | while IFS= read -r m; do [ -n "$m" ] && printf 'marker %s\n' "$m"; done
  printf '\n## Extensions (ranked by count descending, extension ascending; all shown)\n\n'
  awk -F'\t' 'NR>1 {c[$2]++} END {for (e in c) printf "%d\t%s\n", c[e], e}' "$FACTS" |
    sort -k1,1nr -k2,2 | while IFS="$(printf '\t')" read -r n e; do printf 'ext %s %s\n' "$e" "$n"; done
  printf '\n## What this does not know\n\n'
  printf -- '- Rationale outside code comments — a design note, a wiki, a tracker — is not reachable\n'
  printf -- '  here at any setting. On this kit'"'"'s own repository that is roughly a sixth of it.\n'
  printf -- '- A comment run is located, never interpreted. Whether it explains anything is a\n'
  printf -- '  judgement, and this script does not make it.\n'
  printf -- '- Per-file `commits` and `authors` are LOWER BOUNDS when the history has merges, because\n'
  printf -- '  a merge commit lists no files under `--name-only`. `merges` above says how much to\n'
  printf -- '  distrust them; at `merges 0` they are exact.\n'
  printf -- '- A `/* */` block is followed as a block, but any comment style this scanner does not\n'
  printf -- '  know is simply not counted. It reports what it recognised, never that nothing is there.\n'
} > "$REPORT"

rm -f "$FACTS.tmp" "$RUNS.tmp" "$FACTS.miss"
printf '%s\n%s\n%s\n' "${FACTS#$ROOT/}" "${RUNS#$ROOT/}" "${REPORT#$ROOT/}"
