# sync-agents.ps1 — compose the kit's canonical sources into the runtime paths Claude Code loads from
# (.claude/ at the container root, which is NOT a git repo).
#
#   Source of truth  : docs/ai-workflow/agents/core/           portable method, owns frontmatter
#                      docs/ai-workflow/agents/overlay/<proj>/  project vocabulary; _shared.md + per-agent
#                      docs/ai-workflow/commands/ + settings.json
#   Runtime / loaded : <container-root>/.claude/{agents,commands}/ + settings.json   (generated)
#
# ⚠️ WHY THE SPLIT. The agents used to encode one project's vocabulary and its scar tissue in the same
# file as the reviewing method — so they could not be used on a second project without either leaking
# wrong facts into it or losing the hard-won failure-mode lists. core/ is what transfers; overlay/ is what
# does not. A new project writes an overlay and inherits the method, including the universal defect
# classes; it then ACCUMULATES its own citations underneath them, which is the part no kit can ship.
#
# ⚠️ EXTENDED LATER: commands/ and settings.json used to live only in the untracked
# container-root .claude/, versioned nowhere. See the settings.json note below for why it syncs differently.
#
# Usage:  pwsh sync-agents.ps1 [-Project <name>] [-Destination <project-root>]
[CmdletBinding()]
param(
  [string]$Project,
  # The PROJECT ROOT to install into — the directory your harness loads `.claude/` from.
  [string]$Destination,
  # Deliberately re-point a checkout at a different project. Requires intent, because the safe reading of
  # a mismatch is "wrong flag", not "new project".
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# 🔴 A STANDALONE KIT HAS NO IMPLICIT PROJECT ROOT — it must be told, or it guesses wrong silently.
#
# This used to be `Join-Path $PSCommandPath '..\..\..'`, which encodes one assumption: that the script
# lives at `<project>/docs/ai-workflow/`, i.e. exactly three levels below the destination. That is true
# when the kit is VENDORED into a project, and false for a standalone clone — where it resolved to the
# clone's GRANDPARENT. Running it from a fresh clone would have created `.claude/agents/` two levels
# above the repo, in a directory that is not a project, and the destination guard would then have claimed
# that location. A wrong path that CREATES something is worse than one that errors.
#
# So: `-Destination` wins; otherwise the vendored layout is DETECTED rather than assumed; otherwise this
# refuses and says what to pass.
if ($Destination) {
  $root = [System.IO.Path]::GetFullPath($Destination)
  if (-not (Test-Path $root)) { throw "-Destination '$root' does not exist." }
} else {
  $parent      = Split-Path -Leaf $PSScriptRoot
  $grandparent = Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)
  if ($parent -eq 'ai-workflow' -and $grandparent -eq 'docs') {
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
  } else {
    throw @"
Cannot infer the project root from this script's location.

  script : $PSCommandPath
  layout : not the vendored '<project>/docs/ai-workflow/' shape

A standalone kit checkout is not a project, so there is no correct place to write .claude/agents/ —
guessing would create one in the wrong directory and then claim it.

Pass the project root explicitly:
  pwsh sync-agents.ps1 -Project <name> -Destination <path-to-project-root>
"@
  }
}
$dstRoot = Join-Path $root '.claude'
$coreDir = Join-Path $PSScriptRoot 'agents\core'
$ovlRoot = Join-Path $PSScriptRoot 'agents\overlay'

# --- pick the overlay ---------------------------------------------------------
if (-not $Project) {
  $dirs = @(Get-ChildItem $ovlRoot -Directory -ErrorAction SilentlyContinue)
  if ($dirs.Count -eq 1) { $Project = $dirs[0].Name }
  elseif ($dirs.Count -eq 0) { $Project = $null }
  else { throw "Multiple overlays found ($($dirs.Name -join ', ')). Pass -Project <name>." }
}
$ovlDir = if ($Project) { Join-Path $ovlRoot $Project } else { $null }

# 🔴 A NAMED OVERLAY THAT DOES NOT EXIST IS AN ERROR, NOT A NO-OP. Without this, `-Project auip` (typo)
# composed core-only agents, reported success, and printed "core + overlay 'auip'" — claiming an overlay
# had been applied when none was found. The result is a live agent set with no project vocabulary at all,
# which is precisely the silent-downgrade shape this repo keeps paying for: the failure is invisible
# because the thing that failed is the thing that would have told you.
if ($Project -and -not (Test-Path $ovlDir)) {
  $available = @(Get-ChildItem $ovlRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
  throw ("No overlay '$Project' at $ovlDir." + "`n" +
    $(if ($available) { "Available: $($available -join ', ')" } else { "This kit ships no overlays — write agents/overlay/$Project/_shared.md first (see agents/overlay/README.md), or omit -Project to compose core only." }))
}

# --- destination guard --------------------------------------------------------
# 🔴 THE SELECTOR PICKS THE OVERLAY; IT DOES NOT PICK THE DESTINATION. This script always writes to the
# container root of the checkout it lives in:
#
#     <container>/docs/ai-workflow/sync-agents.ps1   ->   <container>/.claude/agents/
#
# So running `-Project b` inside project A's checkout composes B's agents straight over A's live agent
# set, silently, and whoever synced last wins. That is a one-flag mistake with no error and no diff to
# notice — the reviewers a project relies on would simply start speaking another project's vocabulary,
# asserting another project's decision IDs as rules.
#
# The marker records which project this destination belongs to. A mismatch REFUSES and changes nothing.
# The safe reading of a mismatch is "wrong flag", never "new project" — so re-pointing needs -Force.
$marker    = Join-Path $dstRoot '.kit-project'
$markerVal = if (Test-Path $marker) { ((Get-Content -Raw $marker) -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^\s*#' } | Select-Object -First 1).Trim() } else { $null }
$wantVal   = if ($Project) { $Project } else { '<core-only>' }

if ($markerVal -and $markerVal -ne $wantVal -and -not $Force) {
  # stderr via [Console] rather than Write-Error: this script sets $ErrorActionPreference='Stop', which
  # makes Write-Error TERMINATING — so the `exit 3` below never ran and the guard reported 1 instead.
  # A guard whose exit code is not the documented one is a guard nobody can branch on.
  [Console]::Error.WriteLine(@"

DESTINATION GUARD - refusing to sync, nothing was changed.

  This checkout's .claude/ belongs to : $markerVal
  You asked to compose               : $wantVal
  Destination                        : $dstRoot

The overlay selector does not change where output lands. Composing '$wantVal' here would REPLACE
'$markerVal''s live agents in place.

  - Wrong flag?      re-run with -Project $markerVal (or with no flag if only one overlay exists).
  - Wrong checkout?  run this from $wantVal's own checkout - one kit checkout per project.
  - Really re-point this checkout at '$wantVal'? re-run with -Force.
"@)
  exit 3
}
if ($markerVal -and $markerVal -ne $wantVal -and $Force) {
  Write-Warning "Re-pointing this checkout from '$markerVal' to '$wantVal' (-Force)."
}

# --- frontmatter helpers ------------------------------------------------------
# Frontmatter is simple `key: value` lines. Treat a leading `---` as frontmatter ONLY if a closing `---`
# turns up within the first 30 lines AND the block holds at least one `key: value` — otherwise a markdown
# horizontal rule at the top of an overlay would be silently swallowed as metadata.
function Split-Front([string]$text) {
  $lines = $text -split "`r?`n"
  if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return @{ Front = [ordered]@{}; Body = $text } }
  $close = -1
  for ($i = 1; $i -lt [Math]::Min($lines.Count, 30); $i++) { if ($lines[$i].Trim() -eq '---') { $close = $i; break } }
  if ($close -lt 0) { return @{ Front = [ordered]@{}; Body = $text } }
  $front = [ordered]@{}
  for ($i = 1; $i -lt $close; $i++) {
    $m = [regex]::Match($lines[$i], '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$')
    if ($m.Success) { $front[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  if ($front.Count -eq 0) { return @{ Front = [ordered]@{}; Body = $text } }
  return @{ Front = $front; Body = ($lines[($close + 1)..($lines.Count - 1)] -join "`n").TrimStart("`n") }
}

function Read-Part([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  return Split-Front (Get-Content -Raw -LiteralPath $path)
}

# --- compose agents -----------------------------------------------------------
$dstAgents = Join-Path $dstRoot 'agents'
New-Item -ItemType Directory -Force -Path $dstAgents | Out-Null

$shared = if ($ovlDir) { Read-Part (Join-Path $ovlDir '_shared.md') } else { $null }
$made = @()

foreach ($f in (Get-ChildItem $coreDir -Filter *.md | Sort-Object Name)) {
  $core = Read-Part $f.FullName
  $ovl  = if ($ovlDir) { Read-Part (Join-Path $ovlDir $f.Name) } else { $null }

  # Core owns the frontmatter; overlay keys OVERRIDE it (a project may retune `description`, which is the
  # trigger text the harness shows, or `model`, which is a cost decision the project owns).
  $front = [ordered]@{}
  foreach ($k in $core.Front.Keys) { $front[$k] = $core.Front[$k] }
  if ($ovl) { foreach ($k in $ovl.Front.Keys) { $front[$k] = $ovl.Front[$k] } }

  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine('---')
  foreach ($k in $front.Keys) { [void]$sb.AppendLine("${k}: $($front[$k])") }
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine()
  [void]$sb.AppendLine($core.Body.TrimEnd())
  if ($shared) { [void]$sb.AppendLine(); [void]$sb.AppendLine('---'); [void]$sb.AppendLine(); [void]$sb.AppendLine($shared.Body.TrimEnd()) }
  if ($ovl -and $ovl.Body.Trim()) { [void]$sb.AppendLine(); [void]$sb.AppendLine($ovl.Body.TrimEnd()) }

  Set-Content -LiteralPath (Join-Path $dstAgents $f.Name) -Value $sb.ToString().TrimEnd() -NoNewline
  $made += [PSCustomObject]@{ Agent = $f.BaseName; Overlay = [bool]$ovl }
}

# Kit README travels with the agents so the runtime copy explains itself.
$kitReadme = Join-Path $PSScriptRoot 'agents\README.md'
if (Test-Path $kitReadme) { Copy-Item $kitReadme (Join-Path $dstAgents 'README.md') -Force }

# Claim the destination. Written only AFTER a successful compose, so a failed run never leaves a marker
# asserting an ownership that does not match what is actually on disk.
Set-Content -LiteralPath $marker -Value @"
$wantVal
# Written by docs/ai-workflow/sync-agents.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm').
# This records which project .claude/agents/ was composed for. The sync refuses to overwrite a
# destination claimed by a different project (use -Force to re-point deliberately).
# Safe to delete: the next sync re-creates it and adopts this checkout.
"@
if (-not $markerVal) { Write-Host "Claimed this destination for '$wantVal' (.claude/.kit-project)." -ForegroundColor DarkGray }

$what = if ($ovlDir) { "core + overlay '$Project'" } else { 'core only (no overlay selected)' }
Write-Host "Composed agents  ($what)  ->  $dstAgents" -ForegroundColor Green
$made | ForEach-Object { Write-Host ("  - {0,-26} {1}" -f $_.Agent, $(if ($_.Overlay) { 'core + overlay' } else { 'core only' })) }

# --- commands (straight copy) -------------------------------------------------
$srcCmd = Join-Path $PSScriptRoot 'commands'
$dstCmd = Join-Path $dstRoot 'commands'
if (Test-Path $srcCmd) {
  New-Item -ItemType Directory -Force -Path $dstCmd | Out-Null
  Copy-Item (Join-Path $srcCmd '*.md') $dstCmd -Force
  Write-Host "Synced commands/ ->  $dstCmd"
  Get-ChildItem $dstCmd -Filter *.md | ForEach-Object { Write-Host "  - $($_.Name)" }
}

# --- settings.json (report, do not clobber) -----------------------------------
# The one file a machine may legitimately diverge on — a permission granted here, a hook being trialled.
# Overwriting it the way we overwrite agents would silently discard that. settings.local.json is never
# touched; that is the sanctioned place for machine-specific overrides.
$srcSet = Join-Path $PSScriptRoot 'settings.json'
$dstSet = Join-Path $dstRoot 'settings.json'
if (Test-Path $srcSet) {
  if (-not (Test-Path $dstSet)) {
    Copy-Item $srcSet $dstSet -Force
    Write-Host "Installed settings.json (was absent)" -ForegroundColor Green
  } elseif ((Get-FileHash $srcSet).Hash -eq (Get-FileHash $dstSet).Hash) {
    Write-Host "settings.json matches the kit."
  } else {
    Write-Warning "settings.json DIFFERS from the kit copy. Not overwritten - merge deliberately."
    Write-Host "  kit     : $srcSet"
    Write-Host "  runtime : $dstSet"
  }
}
