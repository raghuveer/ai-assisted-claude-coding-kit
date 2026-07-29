---
tier.rule: internal/auth/** T3
ladder.rung3: fault injection at each boundary plus `go test -race ./...` under load
ladder.rung5: independent reviewer, second pass
commands.test: go test ./...
commands.lint: golangci-lint run
commands.build: go build ./...
---

# Go — technology accelerator (seed draft)

## Ladder note

Go has no mature mutation-testing story. Rung 3 is therefore satisfied by fault
injection rather than mutation, and `verify-ladder` should treat the substitute as
declared, not absent — no tier bump on this rung alone.

## Candidate failure shapes

Hypotheses for adversarial review. Confirm or delete against the findings table.

- `errgroup` returning only the first error while later goroutines fail silently.
- `err` checked but the zero value used anyway on the error path — a fail-open that
  passes every test asserting on the happy path.
- `context` created but never threaded through, so cancellation and timeout are
  decorative.
- Slice aliasing after `append` when capacity was preallocated.
- `defer` inside a loop, deferring resource release until function exit.
- A mutex guarding the read but not the write, or vice versa. Green under normal test
  load, fails under `-race`.
