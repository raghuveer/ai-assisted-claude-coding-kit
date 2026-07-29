# Accelerators

Accelerators are **imported per project, never installed globally.** They are reference
files read on demand by an existing skill — not new skills. That distinction is the
whole point: a skill costs roughly 100 tokens of resident metadata in every project on
the machine, whether or not it is used, while a reference file costs nothing until read.
If accelerators arrive as skills, resident cost grows linearly with the catalogue and
eventually eats the advantage the baseline was built to get.

To import one, copy it into the target repo and point at it:

```
accelerator.technology: .claude/accelerators/go.md
accelerator.industry:   .claude/accelerators/bfsi.md
```

## Status of these seeds

They are **drafts**, not earned content. The failure shapes listed in each are plausible
rather than observed, and should be treated as hypotheses until the findings table says
otherwise. The real content arrives from:

```sh
sqlite3 .project/index.db "SELECT lang, class, COUNT(*) FROM finding
                            GROUP BY lang, class ORDER BY 3 DESC;"
```

A seeded entry that never appears in findings across several projects is scar tissue for
a wound nobody has — delete it. An entry that appears often and is not listed is the
next line to add.
