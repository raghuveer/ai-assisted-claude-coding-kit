---
id: T-20260822-process-creation-costs-one-second-on-the
title: Process creation costs one second on the dev machine and does not parallelise
epic: measurement
tier: T1
paths: docs/TRIAL-PROTOCOL.md, tooling/kit-index.sh
state: created
---

## Intent

**This is not a defect in the kit.** It is a property of the machine the kit is developed on, and
it is recorded because it distorts every local timing the kit produces — including any a trial
would report.

Measured 2026-08-22, elevated PowerShell, machine idle at 1% CPU across 16 logical processors:

    $sw=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt 50;$i++){ Start-Process cmd.exe -ArgumentList '/c','exit' -NoNewWindow -Wait }
    $sw.Stop(); "{0:N0} ms per spawn" -f ($sw.Elapsed.TotalMilliseconds/50)

    1,015 ms per spawn

A healthy Windows machine is **10–30 ms**. This one is 30–100× slower at the single operation a
shell-based kit performs most.

## What follows arithmetically

- A minimal 3-task fixture costs ~61 spawns and takes **25 s** to index.
- The conformance suite performs **90 index builds** — about an hour locally.
- The same suite takes **43 s on ubuntu-latest** and **~1 m 10 s on macos-latest** in CI.

`user` time is ~2 s against ~58 s of `sys` in every measurement. Nothing is computing; everything
is waiting.

## It does not parallelise, which rules out the obvious fix

| run | 160 spawns | throughput |
|---|---|---|
| sequential | 65 s | 2.46/sec |
| 8 concurrent workers | 56 s | 2.86/sec |

**1.16×, not 8×**, on sixteen idle cores, with `sys` time *rising*. Process creation is serialised
at roughly 2.5/sec regardless of how many ask. So `xargs -P` over the suite's 43 isolated fixtures
would turn an hour into ~52 minutes, and was abandoned on that evidence rather than built.

## Four causes tested and REFUTED, each by measurement

| hypothesis | result |
|---|---|
| Defender path exclusions on the Git install and temp tree | 80 s vs 79 s |
| Overwolf overlay process hooks (all processes stopped) | 76 s vs 79 s |
| msys `fork` emulation | PowerShell → `cmd.exe` is *slower* (1,015 ms) |
| Defender real-time protection **disabled** | **1,016 ms vs 1,015 ms** |

`fltmc filters` shows only Microsoft drivers — `bindflt`, `UCPD`, `WdFilter`, `storqosflt`,
`wcifs`, `gameflt`, `CldFlt`, `bfs`, `FileCrypt`, `luafv`, `UnionFS`, `npsvctrig`, `Wof`,
`FileInfo`. **No third-party endpoint, backup or sync filter exists on this machine.**

An early hypothesis was also wrong in method, not just conclusion: `cmd //c exit` run *from bash*
still pays bash's `fork`, so it could not distinguish msys from system-wide. The PowerShell
measurement is what settled it.

## Acceptance criteria

- [ ] The same benchmark is run on **one other machine**. If it reports 10–30 ms this is a fault
      worth pursuing; if it reports ~800 ms it is the hardware and the design-around is permanent.
      One data point cannot tell those apart, and everything below depends on which it is.
- [ ] Either a cause is identified, or this task records that the search was abandoned and why.
      An open investigation with no owner becomes folklore.
- [ ] Wall-clock figures produced on this machine carry the spawn latency beside them, or are
      marked UNAVAILABLE. Covered in `docs/TRIAL-PROTOCOL.md` §2 as of this task.
- [ ] IF the constraint is permanent: reduce process spawns in `kit-index.sh`, which has 55 `git`,
      38 `awk` and 17 `sqlite3` invocation sites. That helps on every machine, unlike parallelism.

## Notes

Found 2026-08-22 while investigating why the local suite takes an hour against CI's 43 seconds.

**Do not read this as an argument for rewriting the kit in a compiled language.** A rewrite would
help here — it eliminates spawns rather than parallelising them — but it would be rewriting a kit
whose design has not survived a single brownfield trial, to compensate for one machine's fault
that equally affects git, npm and every compiler on it. Revisit after the trial, if at all.

Not a blocker for `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`. The trial can run; its
wall-clock figures cannot be trusted, which §2 now says.
