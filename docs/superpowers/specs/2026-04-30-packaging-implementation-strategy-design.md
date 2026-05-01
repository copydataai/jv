# JV Milestone 5: Packaging and Implementation Strategy Design

## Product Goal

JV is Java middleware that turns hidden IDE and project state into one reliable action: build and run the latest code correctly.

Milestone 5 decides how JV should be implemented, packaged, installed, versioned, and released after runner-core behavior has grown inside the tracked Bash CLI. The goal is to choose an implementation path that preserves the current product promise while making JV practical to install, test, support, and evolve across developer machines and coding-agent environments.

The milestone should answer two product questions:

1. Is the Bash implementation the product, or is it the executable prototype for a binary implementation?
2. What release path makes `jv` easy to install, verify, upgrade, and trust?

The output of this milestone is a decision record plus the first packaging/release plan. It should not depend on the unrelated, untracked Java prototype under `cli/`; that code may inform a spike, but it is not assumed to be the product.

## Non-Goals

- Rewriting runner-core behavior during the decision phase.
- Expanding JV's project support beyond the current runner-core scope.
- Treating the untracked Java prototype in `cli/` as an accepted product direction.
- Changing the user-facing command contract without a migration plan.
- Introducing a required hand-authored project config file.
- Building a package registry, plugin system, or server-side update service.
- Solving dependency resolution beyond current Maven delegation and plain Java support.

## Current State

The product behavior lives in the Bash CLI. That implementation has become the runner-core surface: project detection, plan explanation, compile/run execution, and generated `.jv/` memory.

This has advantages:

- The current entrypoint is transparent and easy to inspect.
- It works naturally in Unix-like shells and coding-agent environments.
- It can delegate directly to `java`, `javac`, and `mvn`.
- It has low local build requirements.

It also has product risk:

- Cross-platform support, especially Windows, is weaker.
- Parser and state logic become harder to maintain as Bash grows.
- Structured tests are possible but more awkward than in a general-purpose language.
- Installer, upgrade, checksum, and release behavior need discipline to avoid becoming ad hoc.

## Options

### Option 1: Harden Bash As The Product

Keep `jv.sh` as the implementation and package it as the official CLI.

Expected shape:

- Install `jv` as a shell script wrapper or copied executable script.
- Keep logic in Bash with small, testable functions.
- Use integration tests as the primary confidence layer.
- Publish versioned script releases with checksums.
- Support macOS and Linux first; document Windows through WSL or Git Bash unless proven otherwise.

Strengths:

- Lowest migration cost from current runner-core behavior.
- Fastest path to a reliable public release.
- Easy for users and agents to inspect.
- Minimal toolchain burden for contributors.
- Natural fit for command orchestration around Java tools.

Risks:

- Windows support remains limited.
- Complex Java parsing and JSON handling are brittle in shell.
- Long-term maintainability may degrade if behavior expands.
- Rich unit testing requires discipline and may still be less ergonomic.

Best fit if:

- JV's near-term value is command orchestration, not deep static analysis.
- Windows native support is not a launch blocker.
- Parser needs can stay deliberately shallow and explainable.

### Option 2: Port To A Binary Implementation

Port the CLI to a compiled language such as Go, Rust, or Java and distribute native binaries.

Expected shape:

- Preserve the `jv` command interface.
- Implement project detection, planning, `.jv/` state, explanation, and execution in the binary.
- Build release artifacts per platform.
- Use the Bash implementation as behavioral reference during migration.

Candidate languages:

- Go: strong fit for single-file cross-platform CLI distribution, simple build pipeline, good JSON/process APIs.
- Rust: strong fit for robust parsing, error handling, and static binaries, with higher contributor and build complexity.
- Java: strong fit for the Java ecosystem and parser libraries, but requires bootstrapping a JVM to run the tool that helps users run Java.

Strengths:

- Better native Windows support.
- Cleaner structured parsing, state management, and unit testing.
- Easier long-term maintenance once behavior grows.
- Release artifacts can be checksummed and signed consistently.

Risks:

- Porting can stall product momentum.
- Behavior drift from the working Bash runner is likely unless golden tests are created first.
- Java implementation has a bootstrap problem: JV would require Java before it can diagnose Java setup well.
- Rust may be more engineering-heavy than the product currently needs.

Best fit if:

- Native Windows support is a near-term requirement.
- `.jv/` schemas and parser logic are expected to become central product surfaces.
- The team is ready to invest in a behavioral compatibility suite before porting.

### Option 3: Hybrid Bash Plus Binary

Keep Bash as the installer/bootstrap/compatibility layer while moving parser-heavy or platform-sensitive behavior into a binary.

Expected shape:

- `jv` remains the stable command.
- Bash handles install-time checks, legacy compatibility, or simple delegation.
- A binary handles detection, planning, JSON state, and execution.
- Releases include both script and binary assets, or the script downloads the right binary.

Strengths:

- Allows incremental migration.
- Keeps the inspectable shell workflow while reducing shell complexity.
- Can preserve Unix agent compatibility during a binary transition.
- Gives room for native Windows support through the binary.

Risks:

- Two runtimes can create confusing failure modes.
- Packaging becomes more complex than either pure approach.
- Users may not know whether they are debugging the wrapper or the binary.
- CI must test both paths.

Best fit if:

- The team wants to validate a binary core without breaking current users.
- Bash has clear remaining value as bootstrap glue.
- The split is small and explicit rather than a long-term mixed architecture.

## Decision Criteria

The implementation decision should be scored against the following criteria.

| Criterion | What To Evaluate |
| --- | --- |
| Install friction | How many commands, prerequisites, PATH changes, permissions, and platform-specific steps are required before `jv run` works? |
| Windows support | Can JV run natively on Windows without WSL, and can it handle paths, process execution, classpaths, and shells correctly? |
| Parser complexity | How safely can the implementation scan Java sources, packages, main methods, Maven files, and `.jv/` JSON without brittle text hacks? |
| Testability | Can detection, planning, execution boundaries, and migration behavior be unit-tested and integration-tested without excessive shell setup? |
| Maintenance | Will future contributors understand, debug, and extend the implementation without multiplying fragile edge cases? |
| Agent compatibility | Can coding agents install, inspect, run, explain, and debug JV in ephemeral workspaces with minimal hidden state? |

Additional practical checks:

- Startup time should feel instant for small projects.
- Failure messages must remain explainable and must not hide underlying Java/Maven output.
- The implementation must preserve command-line compatibility for current runner-core commands.
- Release artifacts must be reproducible enough to trust and verify.

## Recommended Next Decision Process

Milestone 5 should not choose a port based on preference alone. It should run a short, bounded spike against real runner-core behavior.

Recommended process:

1. Freeze the current user-facing command contract and `.jv/` schema expectations as compatibility fixtures.
2. Create a representative fixture suite covering plain Java, packaged Java, multiple mains, Maven, missing tools, stale memory, and argument passing.
3. Score the three options against the decision criteria using those fixtures.
4. Run one binary spike in the strongest candidate language, likely Go unless Windows-native Java ecosystem integration is judged more important than bootstrap simplicity.
5. Compare the spike against hardened Bash on behavior parity, test clarity, packaging complexity, and Windows feasibility.
6. Record the decision as either "Bash is product for v1", "Port to binary before v1", or "Hybrid migration with a fixed sunset point for Bash core logic".

The default recommendation is:

> Harden Bash as the v1 product unless a two-week binary spike proves materially better Windows support and maintainability without regressing install friction or agent compatibility.

This keeps momentum behind the existing runner-core while creating a clear off-ramp if Bash starts limiting the product.

## Spike Criteria

The spike should be time-boxed and judged by concrete outcomes.

Required spike scope:

- Implement `jv explain` and `jv run` planning for one plain Java fixture and one Maven fixture.
- Read and write `.jv/state.json` with the current schema version.
- Append `.jv/runs.jsonl` events for detection, selection, and execution.
- Preserve argument passing after `--`.
- Produce explanation output compatible with runner-core expectations.
- Build installable artifacts for macOS, Linux, and Windows, or explain exactly why not.

Pass criteria:

- The spike passes the same fixture tests as the Bash implementation for the scoped cases.
- The command UX is identical or has an explicit migration note.
- The release artifact can be installed without a language-specific toolchain.
- Windows native execution works for at least one plain Java project.
- The implementation has clearer tests for planner/model behavior than Bash.

Fail criteria:

- The spike requires Java, Go, Rust, Maven, or another compiler on the user's machine just to install JV.
- Behavior diverges from the current runner-core contract.
- Packaging is meaningfully more complex than the benefit justifies.
- Debuggability for agents gets worse because behavior moves into an opaque artifact without equivalent `jv explain` and trace output.

## Packaging Channels

JV should support a layered packaging strategy. Each channel should install the same versioned `jv` command and make verification possible.

### Curl Installer

The curl installer is the lowest-friction channel for docs and agent environments.

Requirements:

- Install with a command such as `curl -fsSL https://.../install.sh | sh`.
- Detect OS and architecture when installing binary builds.
- Install to a user-writable location by default, such as `$HOME/.local/bin`, unless overridden.
- Print the installed version and target path.
- Refuse unsafe partial installs.
- Support `JV_INSTALL_DIR` or similar for non-default locations.
- Verify downloaded artifacts against published checksums.
- Avoid requiring `sudo`.

If Bash remains the product, the installer can install a versioned script. If a binary is chosen, the installer should download the correct release asset.

### Homebrew

Homebrew should be the primary macOS package manager channel once releases stabilize.

Requirements:

- Provide a formula that installs `jv`.
- Use GitHub release tarballs or binaries, not an unversioned branch URL.
- Include SHA-256 checksums.
- Run a simple `jv --version` or `jv version` test in the formula.
- Keep formula updates tied to tagged releases.

### GitHub Releases

GitHub Releases should be the source of truth for versioned artifacts.

Requirements:

- Publish release notes with user-facing changes, migration notes, and known limitations.
- Attach checksums for every artifact.
- Attach platform binaries if JV moves to a binary implementation.
- Attach the install script or make it fetch a pinned release.
- Keep old releases available for rollback.

### Checksums

Every downloadable artifact should have a SHA-256 checksum.

Requirements:

- Generate `checksums.txt` during release.
- Verify checksums in the curl installer.
- Document manual verification.
- Treat checksum mismatches as hard failures.

Signing can be deferred unless users or distribution channels require it, but the release flow should leave room for future signing.

### Versioning

Use semantic versioning once public installation begins.

Recommended rules:

- `0.x`: pre-1.0 product iteration; breaking changes are allowed but must be documented.
- Patch version: bug fixes and packaging fixes that do not change command behavior.
- Minor version: new commands, new project support, new packaging channels, additive `.jv/` schema fields.
- Major version: breaking command changes, incompatible `.jv/` schema changes, or removal of a supported installation path.

The CLI should expose:

```text
jv version
jv --version
```

The version output should include implementation type when helpful:

```text
jv 0.5.0 (bash)
jv 0.6.0 (go darwin-arm64)
```

## CI And Release Requirements

CI must prove that a release artifact can run the product contract, not just that source files lint.

Required CI checks:

- Shell linting if Bash remains in the product path.
- Unit tests for planner/model/parser behavior if a binary implementation is introduced.
- Integration tests using temporary Java projects.
- Maven fixture tests when `mvn` is available.
- `.jv/state.json` and `.jv/runs.jsonl` schema compatibility tests.
- Command compatibility tests for `jv run`, `jv explain`, `jv doctor`, `jv compile`, `jv remember main`, and `jv forget main`.
- Installation smoke test from a packaged artifact, not only from the working tree.

Release pipeline requirements:

- Trigger releases from tags.
- Build artifacts in CI.
- Generate checksums in CI.
- Upload artifacts to GitHub Releases.
- Verify that the curl installer can install the tagged version into a temporary directory.
- Verify `jv version` reports the tagged version.
- Keep release notes close to the tag so users can see migration impact.

Platform matrix:

- Required for v1 Bash product: macOS and Linux.
- Required before claiming native Windows support: Windows runner with path, classpath, process, and Java invocation tests.
- Required for binary product: macOS arm64/x64, Linux x64, and Windows x64 at minimum.

## Migration Compatibility

The implementation strategy must preserve the runner-core product contract.

Commands to preserve:

```text
jv run [MainClass] [-- args...]
jv explain [MainClass]
jv doctor
jv compile
jv remember main <MainClass>
jv forget main
jv version
jv --version
```

Compatibility rules:

- Existing scripts that call `jv run` should continue to work.
- Argument passing after `--` must remain stable.
- Exit codes should remain predictable: successful run returns the child process result; planning/configuration errors return non-zero before execution.
- Explanation output can evolve, but the core facts should remain present: detected project shape, source roots, selected main class, build path, and run path.
- Any command rename must ship with an alias and deprecation warning for at least one minor release.

`.jv/` schema rules:

- `.jv/` remains generated memory, not authoritative project configuration.
- `schemaVersion` is required in JSON state files.
- Additive fields are allowed within the same schema version only when old implementations can ignore them.
- Breaking schema changes require a new `schemaVersion` and a migration path.
- JV must tolerate missing `.jv/` files by regenerating them.
- JV must tolerate stale `.jv/` state by re-detecting project truth from source files and build files.
- `runs.jsonl` should remain append-only trace data; invalid lines should not make the project unusable.

If a binary implementation is adopted, it must read state produced by the Bash implementation and either preserve it or migrate it explicitly.

## Testing And Success Criteria

Milestone 5 succeeds when the team has a documented decision and a release path that can be executed repeatedly.

Decision success criteria:

- The chosen implementation strategy is scored against install friction, Windows support, parser complexity, testability, maintenance, and agent compatibility.
- The decision states what happens to the Bash implementation: product, prototype, wrapper, or deprecated compatibility layer.
- Any binary direction includes spike results and migration requirements.
- The unrelated Java prototype is either explicitly excluded or separately evaluated through the same spike criteria.

Packaging success criteria:

- A user can install `jv` from a versioned release without cloning the repository.
- A coding agent can install `jv` in an ephemeral workspace without interactive prompts or `sudo`.
- Users can verify artifact integrity with checksums.
- `jv version` identifies the installed version.
- Release notes explain what changed and whether migration is needed.

Compatibility success criteria:

- Current runner-core command behavior is preserved through the packaging decision.
- `.jv/state.json` and `.jv/runs.jsonl` remain generated memory and do not become required project configuration.
- Existing fixtures pass from both the working tree and the packaged artifact.
- If implementation changes, Bash-produced `.jv/` state remains readable or is migrated safely.

Testing success criteria:

- Plain Java single-main project runs from a packaged install.
- Plain Java multiple-main project refuses to guess and explains the ambiguity.
- Packaged Java class names are resolved correctly.
- Maven project detection delegates build/run behavior to Maven.
- Missing Java, missing Maven, stale memory, and compiler failure produce explicit diagnostics.
- Argument passing after `--` is preserved.
- Installation smoke tests run in CI for every release candidate.

## Open Questions

- Is native Windows support required for v1, or is WSL/Git Bash acceptable initially?
- How much Java source parsing is needed before shallow scanning becomes a product liability?
- Should the first Homebrew formula live in a tap or wait for a broader public release?
- Should release signing be part of v1 packaging, or is SHA-256 verification enough for the first public channel?
- What is the minimum supported Bash version if Bash remains product?
- Which `.jv/` fields are part of a stable compatibility contract versus internal cache data?

## Recommended Milestone Output

Milestone 5 should end with:

- A short decision record choosing Bash, binary, or hybrid.
- A scored comparison table for the three options.
- Spike notes, if a binary spike is run.
- A packaging checklist for curl installer, Homebrew, GitHub Releases, checksums, and versioning.
- A CI/release checklist with platform expectations.
- A migration compatibility checklist for commands and `.jv/` schemas.

The decision should be reversible only through another explicit milestone. Until then, implementation and packaging work should follow the chosen path rather than splitting effort across multiple product candidates.
