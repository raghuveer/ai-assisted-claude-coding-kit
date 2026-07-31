#!/usr/bin/env bash
# kit-accel.sh resolve [--agent NAME] | propose [--min N] [--out FILE]
#
# Accelerators are external, shared, versioned files. Two rules:
#
#   1. BOUND TO AGENTS, NOT SESSIONS. An accelerator is small at rest and large when
#      loaded. `resolve --agent X` returns only what X needs, so an industry
#      obligations list can be five thousand tokens and never reach the orchestrator.
#   2. CONTRIBUTION IS A PROPOSAL, NEVER A WRITE. `propose` emits candidate lines for
#      human review. An accelerator that auto-accumulates compounds one project's
#      mistake across every project that later loads it.
#
# Provenance is tracked per line: a seeded guess must never be mistaken for a finding
# that was earned. Unmarked seed content becomes permanent by default — that is the
# failure mode, not the seeding itself.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || { kit_warn "not a git repository"; exit 0; }
kit_active "$ROOT" || exit 0
PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")
DB="$ROOT/$STATE_DIR/index.db"

CMD=${1:-resolve}; shift 2>/dev/null || true
AGENT=""; MIN=2; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT=${2:-}; shift; shift ;;
    --min)   MIN=${2:-2};  shift; shift ;;
    --out)   OUT=${2:-};   shift; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

# --min is interpolated into a HAVING clause in three separate queries; validate it here
# rather than trusting it at each site.
case "$MIN" in ''|*[!0-9]*) kit_warn "--min must be a whole number"; exit 2 ;; esac

# accelerator.technology / accelerator.industry are repeatable in the profile.
# Form: <path> [-> agent,agent]   — omitting the arrow means every reviewing agent.
emit_group() {
  local key=$1 kind=$2
  kit_cfg_all "$PROFILE" "$key" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    local path agents
    case "$line" in
      *"->"*) path=${line%%->*}; agents=${line##*->} ;;
      *)      path=$line;        agents="" ;;
    esac
    path=$(printf '%s' "$path" | sed 's/[[:space:]]*$//')
    agents=$(printf '%s' "$agents" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$path" ] || continue
    if [ ! -f "$ROOT/$path" ]; then
      kit_warn "accelerator declared but missing: $path"; continue
    fi
    # Filter by agent binding when asked. An unbound accelerator applies to all.
    if [ -n "$AGENT" ] && [ -n "$agents" ]; then
      case ",$agents," in *",$AGENT,"*) ;; *) continue ;; esac
    fi
    printf '%s\t%s\t%s\n' "$kind" "$path" "${agents:-*}"
  done
}

case "$CMD" in

resolve)
  # Deterministic path lookup — the project declares which accelerators apply, so
  # selection is never a model judgement and never reads the wrong file.
  found=$( { emit_group accelerator.technology technology
             emit_group accelerator.industry   industry; } )
  if [ -z "$found" ]; then
    [ -n "$AGENT" ] && exit 0
    kit_warn "no accelerators declared in project-profile.md"; exit 0
  fi
  printf '%s\n' "$found"
  ;;

propose)
  [ -f "$DB" ] || { kit_warn "no index; run kit-index.sh first"; exit 1; }
  OUT=${OUT:-$ROOT/$STATE_DIR/accelerator-proposal.md}
  # A candidate is a (lang|domain, class) pair seen at least --min times and never
  # refuted. Occurrence count is shown so a reviewer can weigh it rather than trust it.
  {
    printf '# Accelerator contribution proposal\n\n'
    printf '<!-- GENERATED. Nothing here is applied automatically. Review each line,\n'
    printf '     then copy accepted ones into the shared accelerator marked [earned]. -->\n\n'
    printf 'Threshold: at least %s occurrences, no refuted findings.\n\n' "$MIN"

    printf '## Technology candidates\n\n'
    tech=$(sqlite3 -separator ' | ' "$DB" "
      SELECT lang, class, COUNT(*), SUM(COALESCE(vindicated,0))
        FROM finding
       WHERE lang IS NOT NULL AND lang <> ''
         -- a finding carrying a domain belongs to the industry accelerator;
         -- letting it through here contaminates the stack profile with
         -- obligations that are not true of the language.
         AND (domain IS NULL OR domain = '')
       GROUP BY lang, class
      HAVING COUNT(*) >= $MIN AND SUM(CASE WHEN vindicated=0 THEN 1 ELSE 0 END)=0
       ORDER BY COUNT(*) DESC;" 2>/dev/null)
    if [ -n "$tech" ]; then
      printf '%s\n' "$tech" | while IFS='|' read -r lang class n v; do
        printf -- '- [ ] `%s` / **%s** — seen%s times, %s confirmed  `[earned]`\n' \
          "$(echo "$lang" | xargs)" "$(echo "$class" | xargs)" " $(echo "$n" | xargs)" "$(echo "$v" | xargs)"
      done
    else
      printf '_none above threshold_\n'
    fi

    printf '\n## Industry candidates\n\n'
    ind=$(sqlite3 -separator ' | ' "$DB" "
      SELECT domain, class, COUNT(*), SUM(COALESCE(vindicated,0))
        FROM finding
       WHERE domain IS NOT NULL AND domain <> ''
       GROUP BY domain, class
      HAVING COUNT(*) >= $MIN AND SUM(CASE WHEN vindicated=0 THEN 1 ELSE 0 END)=0
       ORDER BY COUNT(*) DESC;" 2>/dev/null)
    if [ -n "$ind" ]; then
      printf '%s\n' "$ind" | while IFS='|' read -r dom class n v; do
        printf -- '- [ ] `%s` / **%s** — seen%s times, %s confirmed  `[earned]`\n' \
          "$(echo "$dom" | xargs)" "$(echo "$class" | xargs)" " $(echo "$n" | xargs)" "$(echo "$v" | xargs)"
      done
    else
      printf '_none above threshold_\n'
    fi

    printf '\n## Below threshold (not proposed)\n\n'
    sqlite3 -separator ' | ' "$DB" "
      SELECT COALESCE(NULLIF(lang,''),NULLIF(domain,''),'?'), class, COUNT(*)
        FROM finding GROUP BY 1, class HAVING COUNT(*) < $MIN ORDER BY 3 DESC;" 2>/dev/null \
      | sed 's/^/- /' | head -20
    printf '\n_Single occurrences are not patterns. They stay here until they recur._\n'
  } > "$OUT"
  printf '%s\n' "${OUT#$ROOT/}"
  ;;

export)
  # Aggregate-only. This is the project boundary: shape crosses, instance never does.
  # No finding text, no paths, no task ids, no titles — not by convention but because
  # the query cannot select them. A client repo's specifics must not reach a shared
  # accelerator, and "we were careful" is not a control.
  [ -f "$DB" ] || { kit_warn "no index; run kit-index.sh first"; exit 1; }
  OUT=${OUT:-$ROOT/$STATE_DIR/accelerator-export.ndjson}
  # Stable, non-identifying project handle. The SALT is what makes it non-identifying: an
  # unsalted digest of the origin URL — cksum or anything else — is reversible by anyone
  # who can enumerate candidate client repo URLs, and that is precisely the party this
  # export is defended against. git hash-object keeps the dependency set to git, which is
  # hard-required already.
  ORIGIN=$(git -C "$ROOT" remote get-url origin 2>/dev/null || printf '%s' "$ROOT")
  SALT=$(kit_cfg "$PROFILE" kit.export_salt "")
  if [ -z "$SALT" ]; then
    kit_warn "kit.export_salt is unset — the project handle is an unsalted digest of the"
    kit_warn "origin URL and can be reversed by guessing it. Set a random value in"
    kit_warn "project-profile.md before this export leaves the project."
  fi
  PH="p$(printf '%s\037%s' "$SALT" "$ORIGIN" | git hash-object --stdin | cut -c1-16)"
  # Not overridable from the project profile. The version stamped here is the kit's, not
  # the project's; letting a repo relabel it is exactly the misinformation this field
  # exists to prevent.
  KV=$(kit_version)
  [ -n "$KV" ] || { KV="unknown"; kit_warn "cannot read plugin.json — exporting kit version as 'unknown'"; }
  : > "$OUT"
  sqlite3 "$DB" "
    SELECT 'technology', lang, class, COUNT(*), SUM(COALESCE(vindicated,0)),
           SUM(CASE WHEN vindicated=0 THEN 1 ELSE 0 END)
      FROM finding
     WHERE lang IS NOT NULL AND lang <> '' AND (domain IS NULL OR domain = '')
     GROUP BY lang, class HAVING COUNT(*) >= $MIN;
    SELECT 'industry', domain, class, COUNT(*), SUM(COALESCE(vindicated,0)),
           SUM(CASE WHEN vindicated=0 THEN 1 ELSE 0 END)
      FROM finding
     WHERE domain IS NOT NULL AND domain <> ''
     GROUP BY domain, class HAVING COUNT(*) >= $MIN;" 2>/dev/null |
  while IFS='|' read -r kind key class n vind refuted; do
    [ -n "$kind" ] || continue
    printf '{"kind":"%s","key":"%s","class":"%s","n":%s,"vindicated":%s,"refuted":%s,"project":"%s","kit":"%s"}\n' \
      "$kind" "$key" "$class" "${n:-0}" "${vind:-0}" "${refuted:-0}" "$PH" "$KV" >> "$OUT"
  done
  printf '%s\n' "${OUT#$ROOT/}"
  ;;

*) kit_warn "unknown command: $CMD (resolve | propose | export)"; exit 2 ;;
esac
