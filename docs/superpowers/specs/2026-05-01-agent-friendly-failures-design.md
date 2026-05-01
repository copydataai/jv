# Agent-Friendly Failure UX Design

## Product Goal

JV should make every failed `jv run` actionable for both humans and coding agents without hiding the underlying Java, Maven, or filesystem error.

The current runner-core milestone gives JV a shared planner model, plan summaries, blockers, generated `.jv/` memory, and `doctor`. This slice turns failures into a stable contract:

- a small structured reason code
- one concise human explanation
- a suggested next action
- a retry command when JV can derive one
- stable text sections
- matching `.jv/runs.jsonl` events when memory can be written

The promise:

> When JV cannot run the program, an agent can read one stable failure block and know what happened, what to try next, and which command failed.

## Users

- Coding agents that need deterministic failure surfaces for repair loops.
- Java beginners who need concise next steps instead of raw compiler output alone.
- Experienced developers who want JV to stay transparent and not wrap tool failures in mystery.

## MVP Decision

The MVP should add stable text sections and `.jv/runs.jsonl` failure events. It should not add `jv run --json` or `jv doctor --json` yet.

Reasons:

- Stable text sections are immediately useful in terminals, tests, logs, and agent transcripts.
- Existing `.jv/runs.jsonl` is already the structured agent surface; extending it for blocked and failed attempts fits the current architecture.
- `--json` for `run` is awkward because JV streams compiler, Maven, and Java output. A JSON-only mode would need decisions about stdout/stderr framing, event streaming, and whether user program output is escaped or separated.
- `doctor --json` is valuable later, but this slice is about failed actions. The current `doctor` text output already exposes project state; failure envelopes close the bigger agent loop first.

Deferred:

- `jv doctor --json` for a complete planner snapshot.
- `jv run --json` or `jv run --events` for machine-readable streaming.
- Full namespaced error-code taxonomy.

## Stable Failure Output

When `jv run` cannot execute because of planner blockers, or when build/run execution fails, JV prints the existing plan summary and raw tool output as appropriate, then prints one stable failure block.

Format:

```text
JV failure
Reason: <reason_code>
Action: <planner|compile|maven|runtime|memory>
Message: <one concise sentence>
Next action: <one concrete next step>
Retry command: <shell command, or unavailable>
Exit code: <integer, when a process failed>
```

Rules:

- Section labels are stable and exact.
- `Reason:` value is a stable lowercase snake_case code.
- `Message:` is human-readable and may evolve, but stays one line.
- `Next action:` is the agent instruction.
- `Retry command:` is the command to copy after fixing the issue. Use `unavailable` only when JV cannot derive a useful retry.
- `Exit code:` appears for process failures and blocked `jv run`; memory warnings do not use this block unless the main action failed.

Warnings use a smaller stable block:

```text
JV warning
Reason: memory_write_failed
Message: Could not write JV memory to .jv/.
Next action: Check that .jv/ is a writable directory.
```

## Small Reason Code Set

Use a small stable set and add only when a new action class needs a distinct repair path.

Planner blockers:

- `project_unknown`
- `source_root_missing`
- `main_missing`
- `main_ambiguous`
- `explicit_main_missing`
- `remembered_main_stale`
- `tool_missing`

Execution failures:

- `compile_failed`
- `maven_compile_failed`
- `maven_run_failed`
- `runtime_failed`

Memory warnings:

- `memory_write_failed`

Do not create separate codes for every compiler diagnostic, Maven plugin message, Java exception type, or filesystem errno. JV should preserve raw tool output for detailed diagnosis and provide a stable wrapper for agent control flow.

## Event Contract

When JV can write `.jv/runs.jsonl`, every blocked or failed `jv run` appends one event.

Blocked run:

```json
{"event":"blocked","action":"run","reason":"main_ambiguous","message":"Multiple main classes found: App, Tool.","nextAction":"Pass one main class explicitly.","retryCommand":"jv run App","exitCode":1}
```

Failed process:

```json
{"event":"failed","action":"compile","reason":"compile_failed","command":"javac -d bin -cp bin <sources>","message":"Compilation failed.","nextAction":"Fix the compiler errors above, then retry.","retryCommand":"jv run","exitCode":1}
```

Warning when the run itself succeeded:

```json
{"event":"warning","action":"memory","reason":"memory_write_failed","message":"Could not write JV memory to .jv/.","nextAction":"Check that .jv/ is a writable directory.","retryCommand":"jv run"}
```

Event fields are stable enough for agents. New optional fields may be added later, but existing fields should not be renamed without a compatibility plan.

## Failure Class Examples

### Planner Blocker: Ambiguous Main

Input:

```bash
jv run
```

Output:

```text
JV detected: plain Java project
Source roots: src
Reason: src directory found
Blocker: Multiple main classes found: App, Tool. Pass one explicitly: jv run <MainClass>

JV failure
Reason: main_ambiguous
Action: planner
Message: Multiple main classes were found.
Next action: Pass one main class explicitly, for example `jv run App`.
Retry command: jv run App
Exit code: 1
```

Event:

```json
{"event":"blocked","action":"run","reason":"main_ambiguous","message":"Multiple main classes were found.","nextAction":"Pass one main class explicitly, for example `jv run App`.","retryCommand":"jv run App","exitCode":1}
```

### Compile Failure: Plain Java `javac`

Input:

```bash
jv run
```

Tool output remains visible:

```text
src/Main.java:3: error: cannot find symbol
        System.out.println(message);
                           ^
  symbol:   variable message
  location: class Main
1 error
```

JV failure block:

```text
JV failure
Reason: compile_failed
Action: compile
Message: javac failed while compiling the selected plain Java project.
Next action: Fix the compiler errors above, then retry the same JV command.
Retry command: jv run
Exit code: 1
```

Event:

```json
{"event":"failed","action":"compile","reason":"compile_failed","command":"javac -d bin -cp bin <sources>","message":"javac failed while compiling the selected plain Java project.","nextAction":"Fix the compiler errors above, then retry the same JV command.","retryCommand":"jv run","exitCode":1}
```

### Maven Failure: `mvn compile`

Input:

```bash
jv run
```

Tool output remains visible:

```text
[ERROR] COMPILATION ERROR :
[ERROR] /tmp/app/src/main/java/com/example/App.java:[5,20] cannot find symbol
```

JV failure block:

```text
JV failure
Reason: maven_compile_failed
Action: maven
Message: Maven failed during `mvn compile`.
Next action: Fix the Maven compilation errors above, then retry the same JV command.
Retry command: jv run
Exit code: 1
```

Event:

```json
{"event":"failed","action":"maven","reason":"maven_compile_failed","command":"mvn compile","message":"Maven failed during `mvn compile`.","nextAction":"Fix the Maven compilation errors above, then retry the same JV command.","retryCommand":"jv run","exitCode":1}
```

### Maven Failure: `mvn exec:java`

Input:

```bash
jv run com.example.App demo
```

JV failure block:

```text
JV failure
Reason: maven_run_failed
Action: maven
Message: Maven failed while running com.example.App.
Next action: Inspect the Maven exec output above, then retry the same JV command.
Retry command: jv run com.example.App demo
Exit code: 1
```

Event:

```json
{"event":"failed","action":"maven","reason":"maven_run_failed","command":"mvn -q exec:java -Dexec.mainClass=com.example.App -Dexec.args=\"demo\"","message":"Maven failed while running com.example.App.","nextAction":"Inspect the Maven exec output above, then retry the same JV command.","retryCommand":"jv run com.example.App demo","exitCode":1}
```

### Java Runtime Failure

Input:

```bash
jv run Main alpha
```

Program output remains visible:

```text
Exception in thread "main" java.lang.IllegalStateException: missing config
        at Main.main(Main.java:3)
```

JV failure block:

```text
JV failure
Reason: runtime_failed
Action: runtime
Message: Java exited with a non-zero status while running Main.
Next action: Fix the runtime error above, then retry the same JV command.
Retry command: jv run Main alpha
Exit code: 7
```

Event:

```json
{"event":"failed","action":"runtime","reason":"runtime_failed","command":"java -cp bin Main alpha","message":"Java exited with a non-zero status while running Main.","nextAction":"Fix the runtime error above, then retry the same JV command.","retryCommand":"jv run Main alpha","exitCode":7}
```

### Memory-Write Warning

Input:

```bash
jv run
```

Program succeeds, but `.jv` is not writable:

```text
Hello

JV warning
Reason: memory_write_failed
Message: Could not write JV memory to .jv/.
Next action: Check that .jv/ is a writable directory.
```

Exit status remains `0` because the user program succeeded. If `.jv/runs.jsonl` is writable but `.jv/state.json` is not, append a warning event. If no memory path can be written, the warning block is the only durable record.

## Exit Status

- Planner blockers in `jv run`: exit `1`.
- Plain Java compile failure: exit with the `javac` status.
- Maven compile failure: exit with the `mvn compile` status.
- Maven run failure: exit with the `mvn exec:java` status.
- Java runtime failure: exit with the Java process status.
- Memory-write warning after successful program execution: preserve success exit `0`.

## Command Rendering

`Retry command:` should reconstruct the user's `jv run` invocation, not the underlying `java`, `javac`, or `mvn` command.

Examples:

- `jv run`
- `jv run Main`
- `jv run Main alpha beta`
- `jv run com.example.App demo`

For ambiguous planner blockers, use the first sorted candidate as an example. This keeps the retry command deterministic while the message makes clear that any listed candidate may be valid.

## Non-Goals

- No full JSON output mode.
- No stack traces from JV internals for expected project states.
- No automatic source edits.
- No Maven dependency diagnosis beyond preserving Maven output and adding the failure wrapper.
- No taxonomy for individual Java compiler errors.

## Success Criteria

- Each requested failure surface has a stable `JV failure` or `JV warning` block.
- Existing raw `javac`, Maven, and Java output remains visible.
- `jv run` appends blocked and failed events when `.jv/runs.jsonl` can be written.
- Memory-write failure never turns a successful user program into a failed `jv run`.
- Tests assert stable labels and reason codes, not brittle raw tool diagnostics.
