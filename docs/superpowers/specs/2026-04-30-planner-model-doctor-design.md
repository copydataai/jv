# JV Milestone 1: Planner Model + Better Doctor Design

## Product Goal

JV should make its internal decision explicit, inspectable, and shared across `run`, `explain`, `doctor`, and `.jv` memory.

The current runner core proves the first product promise: Java and Maven projects can be detected, explained, remembered, and run. This milestone turns that behavior into a single planner model that every command reads from and reports on consistently.

The user-facing promise:

> JV can show the exact plan it selected, why it selected it, what would block execution, and whether local memory still matches the project.

Primary users:

- Java beginners who need understandable feedback when JV cannot run their project.
- Experienced developers who want a clear audit trail for build/run decisions.
- Coding agents that need one structured contract for project state, command selection, and failures.

## Non-Goals

- Adding Gradle support.
- Changing the supported project shapes beyond plain Java and Maven.
- Replacing Maven lifecycle behavior or dependency resolution.
- Adding a required hand-authored JV config file.
- Building an interactive TUI or long-form diagnostics UI.
- Persisting `.jv` memory as authoritative project configuration.
- Implementing automatic source edits or dependency installation.

## User-Facing Behavior

All planner-backed commands should describe the same selected plan in different levels of detail.

### `jv run`

`jv run` builds a planner model, prints the short selected plan, stops on blockers, and executes only when the plan is runnable.

Example:

```text
JV detected: Maven project
Source roots: src/main/java
Main class: com.example.App
Build path: mvn compile
Run path: mvn exec:java -Dexec.mainClass=com.example.App
Reason: pom.xml found; one main class detected
```

If the plan has blockers, `jv run` does not execute partial commands.

### `jv explain`

`jv explain` builds the same planner model as `jv run`, prints the selected build/run plan plus reasons, warnings, and blockers, then exits without compiling, running, or appending a successful execution record.

For this milestone, `jv explain` should remain side-effect free: it must not create build outputs, invoke Maven, update `.jv/state.json`, or append run history. A later agent-events milestone may add explicit diagnostic event logging for `explain`, but that logging must be clearly separated from successful execution memory.

### `jv doctor`

`jv doctor` builds the same planner model and presents a fuller diagnostic view:

```text
JV doctor

Project
  Shape: Maven
  Source roots: src/main/java
  Tools: java 21.0.2, javac 21.0.2, mvn 3.9.6

Selected plan
  Main class: com.example.App
  Build: mvn compile
  Run: mvn exec:java -Dexec.mainClass=com.example.App

Reasons
  - pom.xml found in project root
  - src/main/java exists
  - exactly one main method found

Memory
  Remembered main: com.example.App
  State: fresh
  Last run: success, 2026-04-30T10:24:11Z

Warnings
  - none

Blockers
  - none
```

When the project is not runnable, doctor should be the most useful command for understanding why.

### `.jv` Memory

`.jv` remains generated memory only. It stores the latest planner snapshot and run history so humans and agents can inspect what JV saw and decided last time.

Authoritative truth remains:

```text
pom.xml
src/**/*.java
lib/*.jar
package declarations
available local tools: java, javac, mvn
explicit command arguments
```

Generated memory remains:

```text
.jv/
  state.json
  runs.jsonl
```

Rule:

> The planner model may use `.jv` memory as evidence, but source files and build tools always win.

## Planner Model

The planner model is the single normalized object produced before command execution. It should be side-effect free to construct except for allowed memory reads.

Every command should use this same model rather than reconstructing its own partial view.

### Required Fields

#### Project Shape

Identifies what kind of project JV detected.

Values:

- `maven`
- `plain-java`
- `unknown`

The field includes a reason, such as `pom.xml found`, `src directory found`, or `no recognized Java project markers found`.

#### Source Roots

Lists source directories JV considered and their status.

Each source root includes:

- path
- exists or missing
- role, such as Maven main source or plain Java source
- reason it was included

Example roots:

- `src/main/java`
- `src`

#### Tools

Lists local tools relevant to the selected project shape.

Each tool includes:

- name
- resolved path, if found
- version, if available
- availability
- whether the tool is required for the selected plan

Minimum tools:

- `java`
- `javac`
- `mvn`

For Maven projects, `mvn` and `java` are required. For plain Java projects, `javac` and `java` are required.

#### Main Candidates

Lists detected Java entrypoints.

Each candidate includes:

- fully qualified class name
- source file path
- package name, if present
- detection reason
- whether it matches remembered memory
- whether it matches an explicit user argument

#### Selected Main

The chosen entrypoint, if JV can choose one.

Selection precedence:

1. Explicit command argument, if it matches a detected main candidate.
2. Remembered main from `.jv/state.json`, if it still matches a detected candidate.
3. Only detected main candidate.
4. No selection when candidates are missing, ambiguous, or stale.

The selected main field includes:

- value
- source of selection: `explicit`, `remembered`, `only-candidate`, or `none`
- reason
- confidence: `certain`, `blocked`, or `warning`

#### Build Command

The command JV would use to build or compile the project.

The field includes:

- argv array
- display string
- working directory
- whether execution is allowed
- reason

Examples:

```json
["mvn", "compile"]
["javac", "-d", "bin", "..."]
```

#### Run Command

The command JV would use to run the selected main class.

The field includes:

- argv array
- display string
- working directory
- whether execution is allowed
- reason

Examples:

```json
["mvn", "exec:java", "-Dexec.mainClass=com.example.App"]
["java", "-cp", "bin:lib/*", "com.example.App"]
```

#### Reasons

Ordered list of why JV made each major decision.

Reasons should be short, stable, and useful in `explain`, `doctor`, `.jv/state.json`, and tests.

Examples:

- `pom.xml found in project root`
- `src/main/java exists`
- `exactly one main method found`
- `remembered main still exists in source`
- `plain Java project uses javac and java`

#### Blockers

Ordered list of conditions that prevent execution.

Each blocker includes:

- code
- human message
- affected field
- suggested next action, when possible

Examples:

- `jdk_missing`: `javac was not found; install a JDK and try again.`
- `maven_missing`: `pom.xml was found, but mvn is not available.`
- `main_ambiguous`: `Multiple main classes were found; pass one explicitly or remember one.`
- `main_missing`: `No public static void main(String[] args) method was found.`
- `remembered_main_stale`: `The remembered main class is no longer present in source.`

#### Warnings

Ordered list of non-blocking conditions that the user may want to fix.

Warnings include:

- code
- human message
- affected field
- suggested next action, when possible

Examples:

- stale `.jv/state.json` snapshot was regenerated
- remembered main differs from explicit argument
- `lib/` exists but contains no JAR files
- previous run failed
- Maven version could not be parsed

#### Memory State

Summarizes `.jv` memory as evidence.

Fields:

- `.jv/state.json` exists or missing
- `.jv/runs.jsonl` exists or missing
- remembered main value, if any
- remembered main freshness: `fresh`, `stale`, `unknown`, or `none`
- last planner snapshot timestamp, if any
- last run command, if any
- last run exit code, if any
- last run status: `success`, `failed`, `blocked`, or `none`

Memory state should never override current source truth.

## Better Doctor

`jv doctor` should become the command users run when JV surprises them.

Doctor should show:

- selected plan, including project shape, selected main, build command, and run command
- reasons for shape detection, source root detection, main selection, and command selection
- blockers that prevent `jv run` from executing
- warnings that do not block execution
- stale memory, especially remembered main values no longer present in source
- tool versions and availability for `java`, `javac`, and `mvn`
- last run status from `.jv/runs.jsonl`

Doctor output should be deterministic enough for tests while still readable for humans.

### Doctor Status

Doctor should end with one clear status:

- `OK`: runnable plan with no warnings
- `WARN`: runnable plan with warnings
- `BLOCKED`: no runnable plan

Example blocked status:

```text
Status: BLOCKED
Next action: pass one main class explicitly, for example `jv run com.example.App`
```

Doctor should return a non-zero exit code only when JV cannot produce a valid diagnostic because of an internal error. Project blockers are product diagnostics, not doctor command failures.

## Shared Model Across Commands

`run`, `explain`, `doctor`, and `.jv` should share this flow:

```text
detect project inputs
read .jv memory
scan source roots
resolve tools
build planner model
derive selected plan
render command-specific output
execute only for run
write updated memory when appropriate
```

Command-specific behavior:

- `run`: render short plan, stop on blockers, execute build/run commands, append run history.
- `explain`: render plan and diagnostics, do not execute commands.
- `doctor`: render full diagnostics, do not execute commands.
- `.jv/state.json`: store latest planner snapshot and remembered choices.
- `.jv/runs.jsonl`: append run/explain/blocked events that help reconstruct what happened.

No command should maintain its own separate detection logic.

## Error Behavior

JV should separate project blockers from internal errors.

### Project Blockers

Project blockers are expected product states. JV should explain them without a stack trace.

Examples:

- no JDK available
- Maven project without Maven installed
- no source roots found
- no main class found
- multiple main classes without explicit or remembered selection
- remembered main no longer exists
- selected explicit main is not detected in source

For `jv run`, blockers prevent execution and return a non-zero exit code.

For `jv explain` and `jv doctor`, blockers are printed as diagnostics. `jv explain` may return non-zero if the user asked for a runnable plan and none exists. `jv doctor` should usually return zero because it successfully diagnosed the project.

### Execution Failures

Compiler, Maven, or runtime failures should stream the underlying tool output directly. JV should then summarize:

- which planner step failed
- command that failed
- exit code
- whether `.jv/runs.jsonl` recorded the failure

### Internal Errors

Internal errors are bugs in JV itself. They may show a concise internal error message and should return non-zero for all commands.

The user-facing message should still say what JV was doing when it failed, such as `while scanning source roots` or `while reading .jv/state.json`.

## Testing And Success Criteria

### Model Tests

- Planner model detects `maven`, `plain-java`, and `unknown` shapes.
- Source roots include checked paths and reasons.
- Tool availability records required tools and versions when available.
- Main candidates include fully qualified class names and source paths.
- Selected main precedence is explicit argument, fresh memory, only candidate, then blocked.
- Stale remembered main creates a warning or blocker and does not override source truth.
- Build and run commands are derived from the same selected plan.

### Command Tests

- `jv run` and `jv explain` produce the same selected main, build command, run command, reasons, warnings, and blockers for the same inputs.
- `jv doctor` reports the same selected plan as `jv explain`.
- `jv doctor` reports `OK`, `WARN`, or `BLOCKED` correctly.
- `jv doctor` shows versions for available `java`, `javac`, and `mvn`.
- `jv doctor` shows last run status when `.jv/runs.jsonl` exists.
- `jv doctor` clearly reports stale remembered main state.
- Blocked `jv run` does not execute build or run commands.
- `jv explain` and `jv doctor` do not compile or run code.

### Memory Tests

- `.jv/state.json` stores the latest non-authoritative planner snapshot.
- `.jv/runs.jsonl` records successful, failed, and blocked run attempts.
- Missing `.jv` memory does not prevent first run.
- Corrupt `.jv/state.json` is reported as memory warning and does not prevent source-based planning when possible.
- Source changes can make remembered memory stale, and JV reports that staleness.

### Product Success Criteria

- A user can understand why JV selected a main class without reading source code.
- A user can understand why JV refused to run when the project is ambiguous or incomplete.
- `run`, `explain`, and `doctor` never disagree about the selected plan for the same project state.
- `.jv` gives agents an inspectable record of decisions without becoming required config.
- Doctor output is useful enough that a bug report can include it as the first diagnostic artifact.
