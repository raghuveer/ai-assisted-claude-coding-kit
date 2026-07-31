# CLAUDE.md

<!-- Append to the target repo's CLAUDE.md. Keep it this short: every line here is
     paid on every request of every session. If deleting a line does not change
     behaviour, leave it deleted. -->

## Working agreement

- Declare a tier (T0-T3) before spawning any reviewer. Untiered work is either
  overspend or a missing control, and afterwards you cannot tell which.
- Truth lives in task files and git trailers. `STATUS.generated.md` and
  `.project/index.db` are derived — never edit them, and never treat them as input
  that outranks the text they came from.
- Never write outside the project root.
- Commits carrying real change carry `Task-Id:` and `Tier:` trailers.
