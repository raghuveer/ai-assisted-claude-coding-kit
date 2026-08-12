---
id: T-20260812-status-has-no-time-dimension-so-daily-ac
title: Status has no time dimension so daily activity is underivable
epic: reporting
tier: T2
lang: bash
paths: tooling/kit-status.sh, skills/status-report
state: open
---

## Intent

`STATUS.generated.md` has five sections — Open, Closed, Unresolved task ids, Escape rate by
tier, Below their tier floor — and **every one is a point-in-time snapshot**. A developer
working in the kit cannot ask "what moved today", "what did I close this week", or "what has
been sitting untouched", because status describes the present and never the interval.

Verified rather than assumed (2026-08-12): `kit-status.sh` matches *today / since / recent* four
times and **all four are prose inside comments**. There is no time-window code. This was not
lost in a migration; it was never built.

**The raw material is complete.** `event` holds every transition with a UTC timestamp and a
kind. On this repository that is 329 rows across 12 days, and this one query already answers
the question:

    SELECT substr(at,1,10) AS day,
           SUM(kind='done') AS closed, SUM(kind='started') AS started,
           SUM(kind='progress') AS progressed, SUM(kind='finding') AS findings,
           COUNT(DISTINCT task_id) AS tasks_touched
      FROM event WHERE at >= :since GROUP BY 1 ORDER BY 1;

     day        closed  started  progressed  findings  tasks_touched
     2026-08-08     12        1           7        46             28
     2026-08-09      1        0           7        56             14
     2026-08-10      2        1           2        12              3
     2026-08-11      0        1           9        61              3

So this is a **presentation gap, not a data-model gap** — which is what makes it cheap and what
decides the shape below.

## The change

A `--since <window>` mode on `kit-status.sh`. **Extend the existing reporter; do not add a
second one.** Two reporting paths over the same event table would duplicate the query surface
and drift, and the retro artefact
(`T-20260811-a-retro-artefact-that-closes-the-kaizen-`) should consume this window rather than
grow its own.

Scope is the **time view only**. A dependency view was considered in the same evaluation and
deliberately deferred: only **3 `depends_on` edges exist across 51 tasks** (against 136
`touches`), so it would render almost nothing today, and a brownfield subject importing an
existing roadmap will have fewer still. Revisit after the trial says whether imported backlogs
produce edges at all.

## The discipline this must not break

The predecessor of derived status was a hand-maintained `STATUS.md`: `checkpoint` wrote it,
`resume-context` read it, and it went stale exactly as designed to. It was replaced by state
derived from task files and trailers, which **cannot disagree with git**.

A daily summary is a legitimate addition to that model **only while it stays derived**:
regenerated on demand, never edited, no field a human is invited to correct. The moment it
carries a hand-written line it is `STATUS.md` again. Adding a time window does not reintroduce
a second source of truth; adding a maintained one would.

## Acceptance criteria

- [ ] `kit-status.sh --since <window>` reports activity per day over the window: closed,
      started, progressed, findings, distinct tasks touched. Accepts at least an ISO date and a
      relative form (`7d`).
- [ ] The window is honoured — a task transition outside it does not appear. Proved with a
      fixture holding events on both sides of the boundary, not by reading the SQL.
- [ ] **A window with no activity says so** and does not print an empty table that reads as a
      quiet period. Zero rows and "nothing happened" are the same picture and different facts —
      the same defect as `0 / 0 via:kit` printing in the shape of a rate.
- [ ] Nothing about the default (no `--since`) output changes. Byte-identical, asserted.
- [ ] The output carries the window it covers, in the output. A figure whose window lives in the
      invoking command gets quoted without it.
- [ ] No new file is generated and nothing is hand-editable: the view is printed, or written to
      the same derived path with the same do-not-edit header.
- [ ] `skills/status-report` mentions the window mode, so it is reachable without reading the
      script.

## Notes

Filed 2026-08-12 at the operator's direction, from an evaluation of what the move from
hand-maintained `STATUS.md` to derived state gained and cost. The gain — status cannot lie about
item state — is not in question and is not to be reopened. This is the one capability the trade
removed that has a developer asking for it back, and it is recoverable without giving the gain
up, because the events were being recorded the whole time.

Related: `T-20260811-a-retro-artefact-that-closes-the-kaizen-` is the management-facing,
periodic, cross-project artefact over the same data. Same query surface, different audience and
cadence; that one should call this window rather than reimplement it.
Also related: `T-20260811-restore-session-state-from-checkpoint-co`, which is the session
orientation half that the same migration dropped.
