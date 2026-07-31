---
id: T-20260731-remove-hex-escapes-from-awk-programs-so-
title: Remove hex escapes from awk programs so macOS works
epic: portability
tier: T2
state: open
---

## Intent

macOS ships one-true-awk 20200816, which does not interpret \x escapes inside program
string literals. The kit uses \x27 to emit the single quotes around every SQL literal, so
on macOS kit-index.sh writes malformed SQL and the index build fails outright:

    Parse error near line 7: near "');   ...   unrecognized token: ""

The -F case was fixed separately: -F$'\x1f' lets the shell expand the byte before awk sees
it. That does not help here, because the shell cannot reach escapes inside the program.

Trap for whoever picks this up: original-awk 20250116 DOES support these escapes, so a
repro on current Debian passes and proves nothing. Only the older build macOS ships fails.

## Acceptance criteria

- [x] no hex escape remains inside any awk program text
- [x] tests/conformance.sh passes on macos-latest
- [x] continue-on-error is removed from the macOS matrix leg
- [x] Linux and Windows index fingerprints are unchanged

## Notes

232 occurrences: 185 x27, 9 x1f, 7 x01, 6 x1e, 4 x03, 4 x02 -- concentrated in
kit-index.sh (207) and kit-plan.sh (19).

Approach: pass the bytes in from the shell, where $'...' works everywhere, and reference
them as variables.

    KIT_Q=$'\x27' KIT_SOH=$'\x01' ... awk -F$'\x1f' '
      BEGIN { Q = ENVIRON["KIT_Q"]; SOH = ENVIRON["KIT_SOH"] }
      function sq(s) { gsub(Q, Q Q, s); return Q s Q }

then use printf "INSERT INTO task VALUES(%s,%s);\n", sq(a), sq(b) rather than embedding
quotes in the format string. That reads better than the current form as a side effect.

Anchored regexes like /^\x01/ become index($0, SOH) == 1; sub on \x03 becomes a substr on
index($0, ETX).

Use the conformance suite as the check. This is a refactor, so the Linux and Windows
fingerprints must NOT move. If they move, something else changed with it.
