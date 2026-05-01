# JV Next Product Sequencing

## Recommended Order

1. Agent-Grade JV Events
2. Agent-Friendly Failure UX
3. JV History / Events Command
4. Gradle Delegation

## Rationale

Agent-Grade JV Events should come first because it creates the stable append-only event envelope that the next two slices can reuse. Failure UX should follow so blocked and failed runs emit useful structured events as well as stable terminal sections.

`jv history` should come after those two because it becomes more valuable when it can read real plan, blocker, failure, execution, and memory events instead of mostly legacy run records. Gradle should come after the observability and failure surfaces are solid, because Gradle adds a new project shape and new delegated failure modes; those decisions should immediately flow through the shared event and failure contracts.

## Parallel Design Outputs

- Design: `docs/superpowers/specs/2026-05-01-agent-grade-events-design.md`
- Plan: `docs/superpowers/plans/2026-05-01-agent-grade-events.md`
- Design: `docs/superpowers/specs/2026-05-01-agent-friendly-failures-design.md`
- Plan: `docs/superpowers/plans/2026-05-01-agent-friendly-failures.md`
- Design: `docs/superpowers/specs/2026-05-01-jv-history-events-command-design.md`
- Plan: `docs/superpowers/plans/2026-05-01-jv-history-events-command.md`
- Design: `docs/superpowers/specs/2026-05-01-gradle-delegation-design.md`
- Plan: `docs/superpowers/plans/2026-05-01-gradle-delegation.md`

## Implementation Guidance

Use subagent-driven execution one milestone at a time. The four plans are designed independently, but the implementation should not run them all at once because they overlap in `jv.sh` and `tests/run-tests.sh`.

Events and failure UX are tightly related: implement events first, then adapt the failure plan to use the event writer rather than adding a second writer. History can be implemented after either events alone or after events plus failures, but the product value is higher after failures. Gradle should reuse all prior planner, event, history, and failure primitives rather than inventing Gradle-specific output paths.
