# Versioning and release

Semantic versioning, with the compatibility surface defined below — because the usual
semver intuitions do not transfer to this kit, and applying them unexamined produces the
wrong number about half the time.

## The version lives in exactly one file

`.claude-plugin/plugin.json`, key `version`. Nowhere else.

In particular the marketplace entry in `.claude-plugin/marketplace.json` carries **no**
version field. `claude plugin tag` advertises that it validates "plugin.json and any
enclosing marketplace entry agree", and adding a version there would enable that check —
but it would also give you two places to bump, which is the exact failure principle 1
exists to prevent. One kind of truth, one file. The check is not worth the duplication it
requires.

Scripts that need the version read it with `kit_version` from `tooling/kit-lib.sh`, which
parses `plugin.json`. It has **no hardcoded fallback** and returns empty when it cannot
read the file, so callers report `unknown` rather than a stale literal. This matters most
in `kit-accel.sh propose`, which stamps the version into accelerator exports that leave
the project: a wrong version there is worse than an absent one, because a wrong one is
believed.

## What the numbers mean here

The public surface is not an API. **It is state written into other people's repositories
and committed there.** A breaking change does not fail someone's build — it means a
teammate's clone reads a schema it does not understand, having done nothing but `git pull`.

So the test for MAJOR is: *does someone pulling this have to take an action?*

| Bump | Covers |
|---|---|
| **MAJOR** | commit trailer vocabulary · `.project/` layout · `events.ndjson` record schema · `project-profile.md` frontmatter keys — anything that requires migrating committed state |
| **MINOR** | new skills, agents, scripts, flags, tier rules, accelerators · **any `index.db` schema change** · additive `events.ndjson` fields |
| **PATCH** | bug fixes, documentation, warnings, performance |

### Why `index.db` schema changes are only MINOR

Because deleting the index and rebuilding is lossless. That invariant is stated in the
README and it is load-bearing here: the index is derived, gitignored, and never shared, so
a schema change reaches no user. `kit-index.sh` rebuilds from task files and git.

This is the practical payoff of keeping the index disposable — most internal churn stays
MINOR instead of inflating to MAJOR. It also gives you a tripwire: **if an `index.db`
schema change ever would break someone, the index has quietly become a second source of
truth**, and the version number is telling you an invariant broke. Fix the invariant, do
not bump the major.

### Why trailers are the hardest thing to change

Trailers are written into commit history. Changing the vocabulary means either rewriting
history or parsing two dialects forever — there is no third option, and no deprecation
window that helps. They are declared frozen in the README, so in practice a MAJOR bump for
trailer reasons means the promise was broken. That is the right amount of friction.

### Additive vs. breaking in `events.ndjson`

Adding a field is MINOR provided readers ignore unknown keys. Removing one, renaming one,
or changing the meaning of an existing one is MAJOR: the file is committed and shared, so
old and new versions of the kit will read the same records concurrently across a team for
as long as it takes everyone to update.

## Staying on 0.x

1.0 will mean: *the committed-state schema is stable, and if it moves I will ship a
migration.* That claim cannot honestly be made until the kit has been exercised by a second
person on a second machine — `events.ndjson`, the profile keys, and the generated
`commit-msg` hook have only ever run in one environment.

This is a reason to keep shipping 0.x, not a reason to delay releases. Under semver, 0.x
minor bumps may break compatibility; this document's MAJOR/MINOR split still describes
*intent*, and breaking changes before 1.0 are called out in the release notes.

## Tags

Format: **`vMAJOR.MINOR.PATCH`** — `v0.2.0`. One annotated tag per release, on `main`.

That string is not decoration; it is what a stranger types:

    /plugin marketplace add raghuveer/ai-assisted-claude-coding-kit@v0.2.0

`claude plugin tag` produces `coding-kit--v0.2.0` instead. That convention exists so a
marketplace carrying several plugins can version them independently. This marketplace
carries one, and the repository and marketplace share a name, so the prefix buys no
disambiguation while costing real typing friction in the pin. Use `claude plugin tag
--dry-run` as a pre-release check; create the tag by hand.

The `0.1` tag predates this policy and stays where it is. Published tags are never moved
or renamed — anyone who pinned to one is entitled to keep getting the same bytes.

### Never name a branch what its release tag will be

Git resolves `refs/tags/<name>` before `refs/heads/<name>`, so a branch and tag sharing a
name makes every reference to it ambiguous:

    $ git rev-parse --short v0.2.0
    warning: refname 'v0.2.0' is ambiguous.

Harmless while both point at the same commit, and silently wrong the moment they diverge.
Develop on `main`, or on a branch named so it can never become a tag — `release/0.2`,
`work/clustering`.

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json`.
2. `python3 validate.py` — structure.
3. `claude plugin validate . --strict` **and**
   `claude plugin validate .claude-plugin/plugin.json --strict`. Both: the command
   validates one manifest chosen from the path, and because the plugin and marketplace
   share a root, plain `.` resolves to `marketplace.json` only.
4. `claude plugin tag --dry-run` — confirms the manifests agree on name and version.
5. Load it and run one real task: `claude --plugin-dir .` in a scratch repo.
6. Merge to `main` and push. **The default branch is what unpinned installs get** —
   `/plugin marketplace add <repo>` with no `@ref` clones `origin/HEAD`. A release that
   stops at a side branch has not shipped.
7. `git tag -a vX.Y.Z -m "coding-kit X.Y.Z"` on `main`, then `git push origin vX.Y.Z`.
8. Note breaking changes in the release notes, with the migration for any committed state.

Step 6 is the one that is easy to skip and invisible when skipped: everything looks
released, the tag exists, and every new user still gets the previous version.
