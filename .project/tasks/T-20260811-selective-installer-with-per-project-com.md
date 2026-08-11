---
id: T-20260811-selective-installer-with-per-project-com
title: Selective installer with per-project component choice
epic: components
tier: T2
lang: bash
paths: tooling/kit-init.sh
state: open
---

## Intent

`kit-init.sh` installs the kit. It cannot express *"this project gets the BFSI accelerator and
the PHP technology pack, and nothing else"* — which is the requirement that stops accelerators
becoming a context tax paid by every project regardless of relevance.

Without per-project selection, every accelerator added to the library is added to everyone's
always-loaded surface, and the kit becomes the bloat it was built as a reaction to.

## The change

A plan/apply installer: named profiles, per-component selection, a recorded install state, and
`doctor` / `repair` / `uninstall --dry-run`. The install state is what makes `doctor` possible —
without a record of what was installed, "is this checkout correct" is unanswerable.

Keep the component catalogue **small**. The engineering pattern is worth copying from ECC; its
200-plus catalogue is exactly what this kit exists to avoid.

## Acceptance criteria

- [ ] Two projects on the same machine hold different accelerator sets, from the same kit
      checkout.
- [ ] Nothing is loaded that the project profile did not request — asserted, not observed.
- [ ] `uninstall --dry-run` lists precisely what it would remove and removes nothing.
- [ ] `doctor` detects a hand-edited or partially applied install and says which component.
- [ ] Re-running apply on an unchanged project is a no-op, byte for byte.

## Notes

Filed 2026-08-11 from R-03, **scoped down on review**. R-03 also asked for "a POSIX shell path
alongside PowerShell" — that half is already satisfied and was dropped: `ls tooling/*.ps1
templates/*.ps1` returns nothing, the installer is bash, and the PowerShell overlay/sync model
was retired in 0.2.0 (`docs/agents-overlay-README.md` carries a do-not-follow banner).

Prerequisite for the accelerator promotion ladder being meaningful: a shared library nobody can
selectively install is a library everybody pays for.
