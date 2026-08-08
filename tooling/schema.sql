
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE node (
  id    TEXT PRIMARY KEY,
  type  TEXT NOT NULL,              -- task | module | file | adr | test | finding | incident
  path  TEXT,
  title TEXT
);

CREATE TABLE task (
  id         TEXT PRIMARY KEY REFERENCES node(id),
  epic       TEXT,
  state      TEXT NOT NULL DEFAULT 'open',
  tier       TEXT,
  lang       TEXT,
  created_at TEXT,
  closed_at  TEXT,
  blocked_by TEXT,
  -- Derived, never authored. The highest tier.rule floor that matches this task, from the
  -- paths it declares and from the files it has actually touched. NULL means no basis to
  -- judge -- which must read differently from "meets its floor", because silence on an
  -- unjudgeable task is how under-tiering stays invisible.
  tier_floor TEXT,
  -- HOW the work was done: kit | agent | manual | unknown, defined once in kit-lib.sh.
  -- Never NULL -- an unrecorded task is `unknown`, which is a real value that reports as
  -- unknown rather than a silent third meaning for one of the others.
  --
  -- Escape rate by tier is the reason this exists. It was computed over EVERY task regardless
  -- of whether the review pipeline had ever run on one, so on a brownfield adoption -- where
  -- most of the backlog is pre-existing or hand-done -- the headline metric was diluted from
  -- the first day, in the direction that makes tiering look ineffective. A metric that cannot
  -- tell "reviewed, nothing escaped" from "never reviewed" is the open-circuit failure the
  -- findings loop had.
  --
  -- It PARTITIONS that metric and never filters it. Filtering was tried and was worse than the
  -- dilution it cured: anything that moves a task out of `kit` -- a command writing the column,
  -- a later chore: commit, a value nobody recorded -- took its escapes out of the only report
  -- that shows escapes, and the row stayed in `event` saying otherwise. Both populations are
  -- reported side by side so this column can change what a number means and never whether an
  -- escape is visible.
  via TEXT NOT NULL DEFAULT 'unknown'
);

CREATE TABLE edge (
  src TEXT NOT NULL,
  dst TEXT NOT NULL,
  rel TEXT NOT NULL,                -- touches|depends_on|constrained_by|covers|blocks|regressed
  PRIMARY KEY (src, dst, rel)
);

-- Files that historically change together, from raw history. Deliberately NOT a row in
-- edge: it is weighted, symmetric, and dense enough that folding it into the generic
-- traversal would let a depth-3 walk reach most of the repository. It also carries no
-- semantics -- co-change is correlation, not dependency.
--
-- Measured at recall@10 0.24, 2.4x a popularity baseline (docs/DESIGN-NOTES.md), which
-- means roughly three quarters of genuinely related files are NOT here. Consume it as
-- "and at least these", never as the boundary of a change.
CREATE TABLE cochange (
  src    TEXT NOT NULL,             -- f:<path>, both directions stored
  dst    TEXT NOT NULL,
  weight INTEGER NOT NULL,          -- commits in which both changed
  PRIMARY KEY (src, dst)
);
CREATE INDEX cochange_src ON cochange(src, weight DESC);

CREATE TABLE event (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id    TEXT,
  kind       TEXT NOT NULL,
  at         TEXT NOT NULL,
  commit_sha TEXT,
  payload    TEXT
);

CREATE TABLE finding (
  id         TEXT PRIMARY KEY,
  task_id    TEXT,
  agent      TEXT NOT NULL,
  model      TEXT,
  tier       TEXT,
  lang       TEXT,                  -- seeds the technology accelerator
  class      TEXT,                  -- kit-finding.sh --vocab is authoritative; do not restate it here
  domain     TEXT,                  -- seeds the industry accelerator (bfsi, govtech, health)
  pattern    TEXT,                  -- seeds the PATTERN accelerator: the reusable design
                                    -- this finding is about, independent of language and
                                    -- of industry (cache-port, adapter-boundary, retry,
                                    -- idempotent-consumer). Added because reviewers kept
                                    -- putting exactly this in `domain`, which is the
                                    -- taxonomy reporting a missing axis rather than the
                                    -- reviewers being careless.
  severity   TEXT,
  at         TEXT,
  vindicated INTEGER                -- NULL unknown | 1 real | 0 false positive
);

-- What a unit of work actually cost. One row per transcript -- the session's for the main
-- loop, one per subagent for everything spawned. Totals are cumulative for a transcript, so
-- the LAST record wins rather than the sum; summing distinct transcripts is then correct.
--
-- The four counters are stored RAW and unweighted, because they are not interchangeable: a
-- cache read is billed at a tenth of fresh input and output at five times it. Adding them
-- up produces a number seven times the truth. kit-status.sh holds the multipliers, in one
-- place, so a committed log never freezes a price list.
--
-- `scope` says which entity the row measures and is the guard against the defect this table
-- was rebuilt for -- `subagent` rows come from that agent's own transcript, `main` rows from
-- the session's, and `legacy` marks rows written before 0.8.0, whose agent label named an
-- agent while the numbers came from the main loop. Never join agent identity to a row that
-- is not `subagent`.
--
-- `context` is the final context-window size, which is what the harness reports as
-- subagent_tokens. It is NOT cost and must never be summed as one -- it matched the harness
-- figure to 0.012% across 105 agents while the actual output work differed by up to 215x. It
-- is kept as a context-pressure signal, and because reproducing the harness number is how a
-- future reader checks the transcripts are still being read correctly.
--
-- task_id is derived, not recorded. The hook that fires when an agent finishes has no idea
-- which task it was serving, so spend is attributed afterwards to the next task-status
-- transition -- which is a heuristic, and is why unattributed spend is reported rather than
-- dropped.
CREATE TABLE spend (
  transcript  TEXT PRIMARY KEY,     -- agent id, or a hash of the session transcript path
  task_id     TEXT,
  scope       TEXT,                 -- main | subagent | legacy
  agent       TEXT,                 -- role, and only when the row came from that agent's file
  agent_id    TEXT,
  session     TEXT,
  model       TEXT,
  at          TEXT,
  turns       INTEGER,
  tok_in      INTEGER,
  tok_out     INTEGER,
  cache_read  INTEGER,
  cache_write INTEGER,
  context     INTEGER
);
CREATE INDEX idx_spend_task ON spend(task_id);

CREATE INDEX idx_edge_src ON edge(src, rel);
CREATE INDEX idx_edge_dst ON edge(dst, rel);
CREATE INDEX idx_event_task ON event(task_id, at);
CREATE INDEX idx_finding_task ON finding(task_id);
CREATE INDEX idx_finding_lang ON finding(lang, class);
CREATE INDEX idx_finding_pattern ON finding(pattern, class);

-- ---------------------------------------------------------------------------
-- Dependency grouping, priority ordering, accelerator provenance. Part of 0.2.0 like
-- everything above it: this file is applied whole to a freshly created database, so the
-- sections below are organisation, not migrations from an earlier release.
-- ---------------------------------------------------------------------------

-- A goal is a named batch of work. The PLAN IS STATE, NOT CONTEXT: /goal computes
-- an ordering once, persists it, and each task session reads only its next row.
-- This is what stops an orchestrator window from growing across a multi-task goal.
CREATE TABLE goal (
  id         TEXT PRIMARY KEY,
  title      TEXT,
  state      TEXT NOT NULL DEFAULT 'open',
  created_at TEXT
);

CREATE TABLE plan_item (
  goal_id  TEXT NOT NULL,
  task_id  TEXT NOT NULL,
  layer    INTEGER NOT NULL,     -- topological layer: 0 has no unmet dependency
  rank     INTEGER NOT NULL,     -- position within the layer, by score
  score    REAL,
  cluster  INTEGER,              -- connected component over the dependency graph
  PRIMARY KEY (goal_id, task_id)
);

-- Accelerator lines carry provenance so a seeded guess is never mistaken for an
-- earned finding. Contribution back to a shared accelerator is a PROPOSAL, never
-- an automatic write: auto-accumulation compounds one project's mistake across all.
CREATE TABLE accelerator (
  id        TEXT PRIMARY KEY,    -- e.g. technology/go, industry/bfsi
  kind      TEXT NOT NULL,       -- technology | industry | pattern
  version   TEXT,
  loaded_by TEXT                 -- comma-separated agents that receive it
);

CREATE TABLE accel_candidate (
  accel_id   TEXT NOT NULL,
  class      TEXT NOT NULL,
  lang       TEXT,
  domain     TEXT,
  pattern    TEXT,
  occurrences INTEGER NOT NULL,
  vindicated  INTEGER NOT NULL,
  first_at   TEXT,
  last_at    TEXT,
  PRIMARY KEY (accel_id, class, lang, domain, pattern)
);

CREATE INDEX idx_plan_goal ON plan_item(goal_id, layer, rank);

-- Team use. Who has a task in flight is derivable from the commit author of its latest
-- 'started' event -- no separate assignment field to keep in sync.
ALTER TABLE event ADD COLUMN actor TEXT;
ALTER TABLE task  ADD COLUMN owner TEXT;
