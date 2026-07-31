---
id: T-20260731-exercise-the-kit-once-on-macos-or-linux
title: Exercise the kit once on macOS or Linux
epic: validation
tier: T1
state: open
---

## Intent

Every release through 0.5.0 was built and tested on Windows with git-bash.

The portability work is real -- exec bits set in the git index because git on Windows
cannot read the msys bit, CRLF stripped from sqlite output, paths passed through ENVIRON
rather than awk -v because -v applies escape processing -- but all of it is reasoning
about a platform nobody has run.

## Acceptance criteria

- [x] `kit-init.sh` generates an executable hook from a fresh clone
- [x] `kit-index.sh` builds an index whose dump matches the Windows dump for the same repo
- [x] the co-change guard reports the same average degree on the same history
- [x] `validate.py` reports 6 ok / 0 warnings

## Notes

Run on Debian stable-slim under Rancher Desktop containerd: bash 5.2, git 2.47.3,
sqlite 3.46.1, and **mawk** rather than gawk -- so the awk is portable across
implementations, which was an untested assumption.

13/13 checks passed on both platforms. A deterministic fixture (fixed author and committer
dates) produced the identical head commit 42cf211d on both, and after the timestamp fix the
filtered index dumps are byte-identical at 160 lines.

The raw `.dump` still differs by three lines -- sqlite 3.46 and 3.53 disagree about emitting
`sqlite_sequence` and `PRAGMA writable_schema=OFF`. That is sqlite's dump format, not kit
state.

macOS remains untested; the acceptance criteria said macOS OR Linux.

