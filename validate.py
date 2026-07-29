#!/usr/bin/env python3
"""validate.py — structural check against documented Claude Code plugin conventions.

Not a substitute for `claude plugin validate`, which runs the real schema. This checks
the things that silently produce a plugin that loads but does nothing: components in
the wrong place, stray .md files in auto-discovery directories, absolute paths that
only work on the author's machine.
"""
import json, os, re, subprocess, sys, stat

# Windows consoles default to cp1252 and several messages here carry en/em dashes, which
# arrive as mojibake or raise UnicodeEncodeError depending on the console.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.abspath(__file__))
errors, warnings, ok = [], [], []


def E(m): errors.append(m)
def W(m): warnings.append(m)
def O(m): ok.append(m)


def frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    fm = {}
    for line in text[3:end].splitlines():
        if ":" in line and not line.startswith(" "):
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip()
    return fm


# ---- manifest -----------------------------------------------------------------
man = os.path.join(ROOT, ".claude-plugin", "plugin.json")
if not os.path.isfile(man):
    E(".claude-plugin/plugin.json missing — required, and must be in .claude-plugin/")
else:
    try:
        m = json.load(open(man, encoding="utf-8"))
        if not m.get("name"):
            E("plugin.json: 'name' is required")
        else:
            O(f"plugin.json name={m['name']} version={m.get('version','(unset)')}")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", m.get("name", "")):
            W(f"plugin name '{m.get('name')}' is not kebab-case")
    except json.JSONDecodeError as e:
        E(f"plugin.json is not valid JSON: {e}")

mk = os.path.join(ROOT, ".claude-plugin", "marketplace.json")
if os.path.isfile(mk):
    try:
        d = json.load(open(mk, encoding="utf-8"))
        for f in ("name", "owner", "plugins"):
            if f not in d:
                E(f"marketplace.json: missing '{f}'")
        for p in d.get("plugins", []):
            if "name" not in p or "source" not in p:
                E(f"marketplace.json: plugin entry needs name and source: {p}")
        O(f"marketplace.json lists {len(d.get('plugins', []))} plugin(s)")
    except json.JSONDecodeError as e:
        E(f"marketplace.json is not valid JSON: {e}")

# ---- components must be at plugin root, not under .claude-plugin/ -------------
for comp in ("commands", "agents", "skills", "hooks"):
    stray = os.path.join(ROOT, ".claude-plugin", comp)
    if os.path.exists(stray):
        E(f"{comp}/ is nested inside .claude-plugin/ — must be at plugin root")

# ---- agents: flat .md files, every file IS an agent ---------------------------
adir = os.path.join(ROOT, "agents")
if os.path.isdir(adir):
    subdirs = [d for d in os.listdir(adir) if os.path.isdir(os.path.join(adir, d))]
    if subdirs:
        E(f"agents/ has subdirectories {subdirs} — discovery is flat; "
          f"nested agents are never loaded")
    n = 0
    for f in sorted(os.listdir(adir)):
        if not f.endswith(".md"):
            continue
        p = os.path.join(adir, f)
        fm = frontmatter(p)
        if fm is None:
            E(f"agents/{f}: no YAML frontmatter — every .md here loads as an agent")
            continue
        if not fm.get("description"):
            E(f"agents/{f}: frontmatter needs 'description'")
        if f.lower() in ("readme.md", "contributing.md", "notes.md"):
            E(f"agents/{f}: documentation in agents/ is loaded AS an agent — move it")
        n += 1
    O(f"agents: {n} discovered, flat, all with frontmatter")

# ---- skills: one subdirectory each, each with SKILL.md ------------------------
sdir = os.path.join(ROOT, "skills")
if os.path.isdir(sdir):
    n = 0
    for d in sorted(os.listdir(sdir)):
        full = os.path.join(sdir, d)
        if not os.path.isdir(full):
            W(f"skills/{d} is a file — skills are directories containing SKILL.md")
            continue
        sk = os.path.join(full, "SKILL.md")
        if not os.path.isfile(sk):
            E(f"skills/{d}/SKILL.md missing")
            continue
        fm = frontmatter(sk)
        if not fm or not fm.get("name") or not fm.get("description"):
            E(f"skills/{d}/SKILL.md: frontmatter needs 'name' and 'description'")
        else:
            if fm["name"] != d:
                W(f"skills/{d}: frontmatter name '{fm['name']}' != directory name")
            if len(fm["description"]) > 400:
                W(f"skills/{d}: description is {len(fm['description'])} chars — "
                  f"it is resident in every session; keep it tight")
            n += 1
    O(f"skills: {n} valid (each ~100 tokens resident)")

# ---- hooks -------------------------------------------------------------------
hp = os.path.join(ROOT, "hooks", "hooks.json")
if os.path.isfile(hp):
    raw = open(hp, encoding="utf-8").read()
    try:
        h = json.load(open(hp, encoding="utf-8"))
        if "hooks" not in h:
            E("hooks/hooks.json: top-level 'hooks' key required")
        cmds = re.findall(r'"command"\s*:\s*"([^"]+)"', raw)
        for c in cmds:
            if "${CLAUDE_PLUGIN_ROOT}" not in c:
                E(f"hooks.json command without ${{CLAUDE_PLUGIN_ROOT}}: {c}")
        O(f"hooks: {len(cmds)} command(s), all using ${{CLAUDE_PLUGIN_ROOT}}")
        for ev in h.get("hooks", {}):
            script = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}/(\S+\.sh)', str(h["hooks"][ev]))
            if script and not os.path.isfile(os.path.join(ROOT, script.group(1))):
                E(f"hooks.json {ev} references missing script: {script.group(1)}")
    except json.JSONDecodeError as e:
        E(f"hooks.json is not valid JSON: {e}")

# ---- absolute paths would break on every other machine -----------------------
for dp, _, fs in os.walk(ROOT):
    # Split on the platform separator. "/.git" never matches on Windows, where os.walk
    # yields backslashes, so .git was being walked in full on every Windows run.
    if ".git" in dp.split(os.sep):
        continue
    for f in fs:
        if not f.endswith((".sh", ".json", ".md")) or f == "validate.py":
            continue
        p = os.path.join(dp, f)
        try:
            t = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        # The regex already states the intent: any developer's home directory. The filter
        # that used to follow narrowed it to literally "/home/claude", so a real finding
        # like /home/alice/src/kit.sh matched the regex and was then silently discarded.
        for m in re.findall(r"(/home/\w+/[\w./-]+|/Users/\w+/[\w./-]+)", t):
            E(f"{os.path.relpath(p, ROOT)}: absolute path baked in: {m}")

# ---- executables --------------------------------------------------------------
tdir = os.path.join(ROOT, "tooling")
if os.path.isdir(tdir):
    names = [f for f in sorted(os.listdir(tdir))
             if f.endswith(".sh") or f == "commit-msg"]
    if os.name == "nt":
        # Windows has no POSIX permission bits for Python to read — os.stat reports only
        # the read-only attribute, so the filesystem check below is false for every file
        # here no matter what chmod did. What actually ships is the mode git recorded.
        try:
            r = subprocess.run(["git", "-C", ROOT, "ls-files", "-s", "tooling"],
                               capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            r = None
        if r is None or r.returncode != 0 or not r.stdout.strip():
            W("tooling: exec bits unreadable on Windows and the tree is not committed — "
              "check `git ls-files -s tooling/` (want 100755) before publishing")
        else:
            ne = []
            for line in r.stdout.splitlines():
                mode, _, rest = line.partition(" ")
                name = rest.split("\t", 1)[-1].rsplit("/", 1)[-1]
                if name in names and mode != "100755":
                    ne.append(name)
            if ne:
                E(f"tooling: not executable in the git index: {', '.join(sorted(ne))}")
            else:
                O(f"tooling: {len(names)} scripts marked 100755 in the git index")
    else:
        ne = [f for f in names
              if not os.stat(os.path.join(tdir, f)).st_mode & stat.S_IXUSR]
        if ne:
            W(f"tooling: not executable: {', '.join(ne)}")
        else:
            O("tooling: all scripts executable")

# ---- report -------------------------------------------------------------------
for m in ok:
    print(f"  ok    {m}")
for m in warnings:
    print(f"  warn  {m}")
for m in errors:
    print(f"  FAIL  {m}")
print(f"\n{len(ok)} ok, {len(warnings)} warnings, {len(errors)} errors")
sys.exit(1 if errors else 0)
