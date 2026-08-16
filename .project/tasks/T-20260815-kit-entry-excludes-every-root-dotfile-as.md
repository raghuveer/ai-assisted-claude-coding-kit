---
id: T-20260815-kit-entry-excludes-every-root-dotfile-as
title: kit-entry excludes every root dotfile as kit-owned
tier: T2
lang: bash
paths: tooling/kit-entry.sh, tests
state: open
---

## Intent

`kit-entry.sh` excludes any top-level dotfile as "kit-owned". That is right for `.gitignore` and
`.gitattributes`, which `kit-init.sh` writes, and wrong for everything else a real subject keeps at
its root: `.eslintrc`, `.golangci.yml`, `.dockerignore`, `.editorconfig`, `.nvmrc`. Those are the
subject's own configuration and they leave the census counted under the kit's label, so a reader
sees `skipped kit-owned 5` with no way to know two of them were theirs.

Found by the final implementation review, 2026-08-15. It also noted that no fixture can show this
today, because every fixture repo is adopted by `kit-init.sh` and has no other dotfiles.

## Acceptance criteria

- [ ] The exclusion names the files the kit actually owns rather than matching a shape. A subject
      dotfile appears in the census, or is excluded under a label that is not "kit-owned".
- [ ] A fixture repo carries a subject dotfile and asserts which side of the line it falls on, and
      fails if the rule reverts.

## Notes

Filed 2026-08-15. Careful with the obvious fix: enumerating kit-owned names here couples this
script to `kit-init.sh` and the two will drift. One list, read from one place.
