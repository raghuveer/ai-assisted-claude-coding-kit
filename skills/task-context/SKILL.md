---
name: task-context
description: Assemble the minimal context for a task — its spec, current state, and blast radius — before any work begins. Use when starting or resuming work on a task ID, or when asked what to work on next. Replaces reading directories or status files by hand.
---

# task-context

Load the least context that can support the work. Reading a directory to "get oriented"
is the failure this skill exists to prevent.

## Procedure

1. Refresh the derived index. It is rebuilt from text, never edited:

   `bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-index.sh --if-stale`

   `--if-stale` skips the rebuild when no task file, event, commit or profile has changed
   since the index was built. Drop the flag to force a full rebuild.

   Silent exit means the repository has not adopted the kit. Say so and stop; do not
   create state in a repository that did not opt in.

2. If no task ID was given, ask the index rather than the user:

   ```sh
   sqlite3 .project/index.db "
     SELECT t.id, n.title, t.state, t.tier
       FROM task t JOIN node n ON n.id=t.id
      WHERE t.state NOT IN ('done','abandoned') ORDER BY t.state, t.id;"
   ```

3. Read **only** the task's own file — the path is in `node.path`. It holds the intent
   and acceptance criteria. Do not read sibling task files.

4. Load the cluster pack, if this task is in a plan. Tasks are grouped by what they are
   about — a shared epic, a shared source file, a declared dependency — and the pack holds
   what every session in that group needs: the sibling tasks, the files the group touches,
   and defect classes already confirmed in those files.

   ```sh
   sqlite3 -separator ' ' .project/index.db "
     SELECT goal_id, cluster FROM plan_item WHERE task_id='<TASK-ID>' LIMIT 1;"
   # -> read .project/packs/<goal_id>/c<cluster>.md
   ```

   Place it **early and verbatim**, before the task spec. It is frozen for the life of the
   plan and byte-identical across every session in the cluster, so an unmodified copy sits
   in the cached prefix and costs a fraction of a fresh read. Reformatting or summarising
   it breaks that and you pay full price in every sibling session.

   No row means no plan covers this task — skip the pack, do not invent one. A pack is
   derived: never edit it, and re-run `kit-plan.sh` if it looks stale.

5. Compute blast radius. This is the input to `tier-classify`, and the reason the
   index carries an edge table at all:

   ```sh
   sqlite3 .project/index.db "
     WITH RECURSIVE reach(id,depth) AS (
       SELECT dst,1 FROM edge WHERE src='<TASK-ID>' AND rel='touches'
       UNION
       SELECT e.dst, r.depth+1 FROM edge e JOIN reach r ON e.src=r.id
        WHERE e.rel IN ('depends_on','covers','constrained_by') AND r.depth<3)
     SELECT n.type, n.path, MIN(r.depth) FROM reach r JOIN node n ON n.id=r.id
      GROUP BY n.id ORDER BY 3;"
   ```

6. Read source files only from that result, and only those the acceptance criteria
   require. The pack already named the cluster's files — do not re-derive them. Report
   which you skipped and why.

## Reporting

State the task, its tier if already assigned, the files you loaded, and anything the
index could not tell you. If `depends_on` edges are absent for this stack, the blast
radius is **unknown, not small** — say so, and let `tier-classify` treat it as unknown.
