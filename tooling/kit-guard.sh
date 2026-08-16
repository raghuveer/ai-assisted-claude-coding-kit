#!/usr/bin/env bash
# kit-guard.sh — PreToolUse net: the kit never writes outside the project root.
# A net, not a security boundary: the real boundary is that scripts use paths
# relative to the root. Parse failure allows the write and warns, because a
# guard that blocks every edit on a malformed payload is a guard people remove.
#
# Three path forms are in play on Windows -- git reports C:/repo, bash reports /c/repo,
# and the tool payload carries C:\repo. Comparing them raw made this check decorative:
# a C:\... path failed the leading-slash test, was taken for a relative path, and was
# waved through unexamined. Everything below is normalised into one form before compare.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
PAYLOAD=$(cat)

# EVERY KEY THE MATCHED TOOLS CAN CARRY, not just one. The hook matcher is
# Write|Edit|NotebookEdit, but this read only "file_path" -- and NotebookEdit names its target
# "notebook_path". So P came back empty for it, the no-target branch below took the fail-open
# path, and a NotebookEdit anywhere on disk was waved through unexamined while SECURITY.md
# claimed the tool was refused. Write outside the root exited 2; NotebookEdit outside exited 0.
#
# This list is the ONE place the mapping lives, and tests/conformance.sh asserts that the hook
# matcher names no tool absent from it -- so adding a fourth tool to hooks.json without teaching
# this line goes red instead of quietly failing open. Two lists in two files agreeing by luck is
# what produced the defect.
#
# First match, not last. A greedy .* walks to the FINAL key in the payload, so writing a file
# whose own content mentions file_path checked that inner value instead of the real target.
# grep -o emits matches in order; head -1 takes the tool's own argument. The alternation keeps
# that property: the first occurrence of EITHER key is still the tool's own.
# The trailing sed undoes JSON's doubled backslashes.
P=$(printf '%s' "$PAYLOAD" |
    grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"[^"]*"' |
    head -1 |
    sed 's/^.*:[[:space:]]*"//; s/"$//; s/\\\\/\\/g')
[ -n "$P" ] || exit 0                      # no target key in payload: nothing to check

# Canonical form: forward slashes, /c/... for drive letters, relative anchored at cwd,
# and "." / ".." resolved lexically. Lexical rather than realpath because a Write targets
# a file that does not exist yet, so the path cannot be resolved through the filesystem.
norm() {
  # Values arrive on stdin, never via -v: awk applies escape processing to -v assignments,
  # so C:\Windows\System32 lands in the program as C:WindowsSystem32 -- the separators are
  # gone before gsub can normalise them, and the path silently stops resembling itself.
  printf '%s\n%s\n' "$1" "$2" | awk '
    NR == 1 { p = $0; next }
    {
      cwd = $0
      gsub(/\\/, "/", p); gsub(/\\/, "/", cwd)
      if (cwd ~ /^[A-Za-z]:\//) cwd = "/" tolower(substr(cwd, 1, 1)) substr(cwd, 3)
      if (p !~ /^\// && p !~ /^[A-Za-z]:\//) p = cwd "/" p
      if (p ~ /^[A-Za-z]:\//) p = "/" tolower(substr(p, 1, 1)) substr(p, 3)
      n = split(p, part, "/"); top = 0
      for (i = 1; i <= n; i++) {
        s = part[i]
        if (s == "" || s == ".") continue
        if (s == "..") { if (top > 0) top--; continue }
        stack[++top] = s
      }
      out = ""
      for (i = 1; i <= top; i++) out = out "/" stack[i]
      print (out == "" ? "/" : out)
      exit
    }'
}

# Then resolve through the filesystem, because lexical work alone still leaves two paths
# naming one directory: Windows 8.3 short names (RAGHUV~1.DEN vs raghuveer.dendukuri) and
# symlinks. `cd` + `pwd -P` collapses both. A Write targets a file that need not exist, so
# resolve the deepest existing ancestor and re-attach the remainder.
resolve() {
  local p=$1 tail=""
  while [ -n "$p" ] && [ "$p" != "/" ]; do
    if [ -d "$p" ]; then
      p=$(cd "$p" 2>/dev/null && pwd -P) || return 1
      printf '%s%s' "$p" "$tail"
      return 0
    fi
    tail="/${p##*/}$tail"
    p=${p%/*}
  done
  printf '/%s' "${tail#/}"
}

R=$(resolve "$(norm "$ROOT" "$PWD")")
Q=$(resolve "$(norm "$P" "$PWD")")

# Fail open, loudly. An unresolvable path is a parse failure, not evidence of an escape.
if [ -z "$R" ] || [ -z "$Q" ]; then
  printf 'kit: could not resolve path, allowing: %s\n' "$P" >&2
  exit 0
fi

# Prefix test by string, not by glob: "$R"/* as a case pattern would treat any glob
# metacharacter in the project path as a wildcard.
[ "$Q" = "$R" ] && exit 0
[ "${Q#"$R"/}" != "$Q" ] && exit 0

printf 'kit: refusing write outside project root: %s\n' "$P" >&2
printf 'kit:   resolved to %s, root is %s\n' "$Q" "$R" >&2
exit 2
