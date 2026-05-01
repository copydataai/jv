# JV Product Roadmap Design

## Roadmap Goal

JV is Java middleware that turns hidden IDE and project state into one reliable action: build and run the latest code correctly.

The runner-core implementation establishes the first working loop. The next product phase should expand that loop through five focused milestones, each with its own spec and implementation plan.

## Milestone Order

1. [Planner Model + Better Doctor](2026-04-30-planner-model-doctor-design.md)
   - Make JV produce one normalized planner model shared by `run`, `explain`, `doctor`, and `.jv`.
   - Improve `doctor` into the trust surface for humans and agents.

2. [Agent-Grade `.jv` Events](2026-04-30-agent-grade-jv-events-design.md)
   - Turn `.jv/` into a structured local feedback loop.
   - Add plan/result/diagnostic/memory events that agents can inspect without scraping prose.

3. [Gradle Delegation](2026-04-30-gradle-delegation-design.md)
   - Add Gradle as a first-class project shape.
   - Delegate to Gradle instead of reimplementing its classpath or task model.

4. [IDE Metadata Hints](2026-04-30-ide-metadata-hints-design.md)
   - Read IntelliJ, Eclipse, and VS Code metadata as hints.
   - Keep source files and build tools authoritative.

5. [Packaging And Implementation Strategy](2026-04-30-packaging-implementation-strategy-design.md)
   - Decide whether Bash remains the v1 product or becomes the reference prototype for a binary.
   - Define release channels, CI, versioning, checksums, and compatibility.

## Sequencing Rationale

The planner model should come first because every later milestone depends on a shared representation of what JV detected, why it selected a plan, and what blocked execution.

Agent-grade events should come second because `.jv/` should record the planner model before more project shapes and hint sources multiply the possible decisions.

Gradle should come before IDE hints because Gradle is authoritative project truth. IDE metadata is useful only after JV can distinguish build-tool truth from supporting evidence.

Packaging should come after the product shape stabilizes enough to judge whether Bash is still the right implementation vehicle.

## Cross-Milestone Rules

- Source files and build tools are truth.
- `.jv/` is generated memory.
- IDE metadata is hints.
- `run`, `explain`, and `doctor` must not drift into separate detection logic.
- JV should delegate to Maven and Gradle instead of reimplementing them.
- When JV cannot prove a safe action, it should stop and explain the blocker.

## Next Implementation Recommendation

Start with Milestone 1 only: Planner Model + Better Doctor.

That milestone creates the structure that makes the other four cheaper and less risky. Once the planner model exists, Milestone 2 can persist it, Milestone 3 can add Gradle as another project shape, Milestone 4 can add IDE evidence, and Milestone 5 can decide how to package a stable command contract.
