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

- [ ] `kit-init.sh` generates an executable hook from a fresh clone
- [ ] `kit-index.sh` builds an index whose dump matches the Windows dump for the same repo
- [ ] the co-change guard reports the same average degree on the same history
- [ ] `validate.py` reports 6 ok / 0 warnings

## Notes

