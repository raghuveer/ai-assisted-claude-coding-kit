# Localiser measurement, 2026-08-15

Ground truth: 12 sites nominated by a read-only agent with no sight of any scanner output.
Scanner: union matcher, file selection by extension or '#!' first line.

## Recall against threshold, this repository

 min   runs  recall@40  recall@all  top-40 files max slots
   4    246       6/10        9/10            15        10
   5    182       6/10        9/10            15        10
   6    142       6/10        8/10            15        10
   7    124       6/10        8/10            15        10
   8    104       6/10        8/10            15        10
   9     91       6/10        8/10            15        10
  10     72       6/10        7/10            15        10
  12     47       6/10        6/10            15        10
  15     26       4/10        4/10            10         7

nominated sites and the longest run overlapping each:
  tooling/kit-index.sh:789-825  longest overlapping run = 14
  tooling/kit-index.sh:736-748  longest overlapping run = 5
  tooling/schema.sql:25-41  longest overlapping run = 17
  tooling/kit-status.sh:272-283  longest overlapping run = 25
  tooling/kit-index.sh:154-190  longest overlapping run = 38
  tooling/kit-lib.sh:17-24  longest overlapping run = 13
  tooling/kit-guard.sh:25-31  longest overlapping run = 3
  tooling/schema.sql:129-153  longest overlapping run = 25
  tooling/kit-trailers.sh:73-81  longest overlapping run = 9
  tooling/commit-msg:4-10  longest overlapping run = 11

## Volume on external subjects (slower sweep, completed after the table above)

Recall figures reproduced identically by an independent second pass, which is why these
volume numbers are trusted from the same run.

```
 min  kit runs  recall@40  recall@all  actix runs  prom runs
   5       182       6/10        9/10         477       1515
   6       142       6/10        8/10         419       1251
   7       124       6/10        8/10         357       1113
   8       104       6/10        8/10         325       1022
  10        72       6/10        7/10         287        921
  12        47       6/10        6/10         246        869
```

At min=10 prometheus yields 921 runs and the cap of 40 keeps **4.3%**; at min=5 it yields
1515 and the cap keeps **2.6%**. So on a large subject the artefact discards 96-97% of what
the scanner found, while on this 170-file repository recall into that same artefact is
already stuck at 60%. Both facts point at the cap rather than the threshold.

## Uncapped, unthresholded volume — the walkthrough decision

With no cap and no minimum length applied by the tool, every in-scope nominated site is
reachable (recall 10/10), because the two that no >=10 gate could return -- longest
overlapping runs of 3 and 5 lines -- are now emitted. The cost is file size:

```
this repo (170 files):        588 runs
actix-web (444 files):      6,301 runs
prometheus (1,665 files):  17,230 runs
```

Roughly 10 runs per tracked file across three subjects of very different size and language.
The registered budget of 50,000 lines therefore corresponds to about a 5,000-file subject
before the tool must apply a minimum length, state it, and count what it dropped. A 20,000-
file monorepo -- the case the design names -- would exceed it, so that path is real and not
theoretical. NOTE the scanner emitted "ignored null byte" warnings on prometheus: binary or
UTF-16 files reached the reader, so the real tool needs the binary skip its own spec already
requires, and 17,230 is an upper bound rather than an exact count.
