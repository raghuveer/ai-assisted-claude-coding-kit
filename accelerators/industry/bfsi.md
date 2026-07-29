---
tier.rule: **/ledger/** T3
tier.rule: **/kyc/** T3
tier.rule: **/reporting/** T3
---

# BFSI — industry accelerator (seed draft)

## Tier floors

Anything touching ledger, KYC, or regulatory reporting is irreversible in the sense that
matters: the record of what was computed persists even after the code is fixed.

## Obligations for the compliance reader

Read alongside rung 4. These are obligations, not a checklist to tick — record each as a
finding with `class: compliance`.

- **Auditability.** Can the decision this code made be reconstructed from what it
  persisted, months later, without the code? If the only record is a log line, no.
- **Determinism of monetary arithmetic.** Floating point anywhere in a money path is a
  finding regardless of observed behaviour.
- **Fail-closed on authorisation.** An unavailable authorisation service that results in
  permitted access is the single highest-severity shape in this domain.
- **Data residency and retention.** Does this path move regulated data across a boundary
  the project profile declares, and is the retention clock started?
- **Segregation of duties.** Can one actor both initiate and approve? Test the path, not
  the intent expressed in comments.

## Note

Seed content. Real obligations vary by jurisdiction and by client, and belong in the
project overlay when they do. Anything here that a project contradicts, the project wins.
