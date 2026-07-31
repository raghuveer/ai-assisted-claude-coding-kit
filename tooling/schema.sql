
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
  blocked_by TEXT
);

CREATE TABLE edge (
  src TEXT NOT NULL,
  dst TEXT NOT NULL,
  rel TEXT NOT NULL,                -- touches|depends_on|constrained_by|covers|blocks|regressed
  PRIMARY KEY (src, dst, rel)
);

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
  severity   TEXT,
  at         TEXT,
  vindicated INTEGER                -- NULL unknown | 1 real | 0 false positive
);

CREATE INDEX idx_edge_src ON edge(src, rel);
CREATE INDEX idx_edge_dst ON edge(dst, rel);
CREATE INDEX idx_event_task ON event(task_id, at);
CREATE INDEX idx_finding_task ON finding(task_id);
CREATE INDEX idx_finding_lang ON finding(lang, class);

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
  kind      TEXT NOT NULL,       -- technology | industry
  version   TEXT,
  loaded_by TEXT                 -- comma-separated agents that receive it
);

CREATE TABLE accel_candidate (
  accel_id   TEXT NOT NULL,
  class      TEXT NOT NULL,
  lang       TEXT,
  domain     TEXT,
  occurrences INTEGER NOT NULL,
  vindicated  INTEGER NOT NULL,
  first_at   TEXT,
  last_at    TEXT,
  PRIMARY KEY (accel_id, class, lang, domain)
);

CREATE INDEX idx_plan_goal ON plan_item(goal_id, layer, rank);

-- Team use. Who has a task in flight is derivable from the commit author of its latest
-- 'started' event -- no separate assignment field to keep in sync.
ALTER TABLE event ADD COLUMN actor TEXT;
ALTER TABLE task  ADD COLUMN owner TEXT;
