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
