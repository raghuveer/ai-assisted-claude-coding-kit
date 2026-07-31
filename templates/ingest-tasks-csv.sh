#!/usr/bin/env bash
# Reference ingest adapter — reads tasks from a CSV instead of markdown files.
#
# Not useful in itself. It exists to be the shortest complete example of the contract in
# docs/ADAPTERS.md, and to be the thing a GitHub-issues or REST adapter is copied from.
#
# Enable it in .claude/project-profile.md:
#
#     ingest.tasks: .claude/ingest-tasks-csv.sh
#
# CSV columns, no header:  id,title,tier,lang,epic,blocked_by
# blocked_by is space-separated inside the field.
set -uo pipefail

CSV="${KIT_ROOT}/.project/tasks.csv"

case "${1:-emit}" in

  # A short opaque string describing the current state of the source. kit-index.sh stores it
  # and compares on the next --if-stale run. Mtime cannot serve here: a remote source changes
  # with no local file touched, so an adapter that cannot answer this honestly should print
  # nothing, which forces a rebuild every time rather than silently serving a stale index.
  fingerprint)
    [ -f "$CSV" ] || { echo "absent"; exit 0; }
    git hash-object "$CSV"
    ;;

  emit)
    [ -f "$CSV" ] || exit 0
    # Single quotes are the only SQL metacharacter that matters here, and doubling them is
    # the whole escape. Emitting SQL is the contract precisely because the built-in sources
    # already do it -- see section 1 of kit-index.sh, which this mirrors row for row.
    awk -F, '
      function q(s){ gsub(/\x27/,"\x27\x27",s); return s }
      function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
      NF && $1 !~ /^[ \t]*#/ {
        id=trim($1); if (id=="") next
        ti=trim($2); if (ti=="") ti=id
        printf "INSERT OR REPLACE INTO node VALUES(\x27%s\x27,\x27task\x27,NULL,\x27%s\x27);\n", q(id), q(ti)
        printf "INSERT OR REPLACE INTO task(id,epic,state,tier,lang,blocked_by) VALUES(\x27%s\x27,\x27%s\x27,\x27open\x27,\x27%s\x27,\x27%s\x27,\x27%s\x27);\n", \
          q(id), q(trim($5)), q(trim($3)), q(trim($4)), q(trim($6))
        n=split(trim($6), dep, /[ ]+/)
        for (i=1;i<=n;i++) if (dep[i]!="")
          printf "INSERT OR IGNORE INTO edge VALUES(\x27%s\x27,\x27%s\x27,\x27depends_on\x27);\n", q(id), q(dep[i])
      }' "$CSV"
    ;;

  *) echo "usage: $0 emit|fingerprint" >&2; exit 2 ;;
esac
