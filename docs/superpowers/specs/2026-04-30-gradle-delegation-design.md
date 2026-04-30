# JV Milestone 3: Gradle Delegation Design

## Product Goal

JV should support Gradle projects with the same product promise as plain Java and Maven projects:

> `jv run` either runs the same code the Gradle project expects to run, from the latest source state, or explains exactly what state is missing or ambiguous.

The goal of this milestone is not to become a Gradle implementation. The goal is to make Gradle projects first-class in JV's explainable runner core by detecting the project shape, selecting an entrypoint when possible, planning a delegated Gradle build/run command, and preserving the resulting decision trail in `.jv/` memory.

User-facing outcome:

```text
JV detected: Gradle project
Build files: build.gradle.kts
Gradle command: ./gradlew
Source roots: src/main/java
Main class: com.example.App
Build path: ./gradlew classes
Run path: ./gradlew run --args="one two"
```

If JV cannot prove the correct Gradle action, it should stop and explain the missing project state rather than guessing silently.

## Non-Goals

- Reimplementing Gradle dependency resolution, task graph behavior, source set modeling, plugin behavior, or classpath calculation.
- Parsing arbitrary Groovy or Kotlin Gradle build logic as a source of truth.
- Generating or modifying `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts`, wrapper files, or Gradle plugin configuration.
- Supporting multi-project Gradle execution beyond clear root-project delegation in this milestone.
- Supporting Android Gradle Plugin, Kotlin/JVM-specific execution, Scala, Groovy, or custom JVM language source roots beyond Java scanning.
- Guessing a run class when Gradle has no `application` plugin configuration and JV cannot identify exactly one Java main candidate.
- Making `.jv/` authoritative. Source files, Gradle files, and local tools remain truth.

## Detection

Gradle detection should extend `ProjectDetector` with a new `gradle` project shape.

JV detects a Gradle project when the current project root contains either:

- `build.gradle`
- `build.gradle.kts`

Wrapper detection is separate from project detection. JV should inspect the project root for:

- Unix wrapper: `gradlew`
- Windows wrapper: `gradlew.bat`

On Unix-like systems, `./gradlew` is usable only when the file exists and is executable. If `gradlew` exists but is not executable, JV should report that specifically and suggest `chmod +x gradlew`.

If both Maven and Gradle build files are present, JV should treat the project as ambiguous unless a future explicit override exists. The diagnostic should list the detected build files and explain that JV will not choose a build system silently.

Detection precedence:

1. Ambiguous build-tool project when multiple build system roots are detected, such as `pom.xml` plus `build.gradle`.
2. Gradle when `build.gradle` or `build.gradle.kts` exists and no conflicting build-tool root exists.
3. Maven when `pom.xml` exists and no conflicting build-tool root exists.
4. Plain Java when source roots exist without a recognized build-tool root.
5. Unknown when no supported project shape can be proven.

## Delegation Strategy

JV delegates Gradle behavior to Gradle. It should not calculate Gradle classpaths itself and should not compile Gradle projects with direct `javac` commands.

Command selection:

1. Prefer `./gradlew` from the detected project root.
2. Fall back to `gradle` from `PATH` only when no usable wrapper exists.
3. If neither a usable wrapper nor `gradle` is available, fail with a Gradle-specific diagnostic.

The wrapper is preferred because it encodes the project's expected Gradle version and distribution. The global `gradle` fallback is convenience, not truth.

For `gradlew.bat`, Unix JV should only report its presence as diagnostic context. Native Windows support can use it later, but this milestone should not pretend a `.bat` wrapper is executable from Unix shells.

## Source Roots And Main Candidate Scanning

JV should keep Java main discovery simple and conservative.

Default Gradle Java source roots:

- `src/main/java`

Optional fallback roots for scanning only:

- `src`

`src/main/java` is the canonical Gradle Java source root. JV may scan `src` only when `src/main/java` does not exist and the project still looks like a simple Java Gradle project.

Main candidate scanning should match runner-core behavior:

- Find Java files under the selected source roots.
- Detect `public static void main(String[] args)` entrypoints using the existing scanner rules.
- Map candidates to fully qualified class names from `package` declarations plus file names.
- Use a user-supplied class when provided and present in scanned sources.
- Use a remembered main class only if it still exists in scanned sources.
- Use the only detected main class when exactly one candidate exists.
- Refuse to choose when multiple candidates exist and no explicit or remembered main class resolves the ambiguity.

JV should not rely on `.gradle/`, `build/`, IDE indexes, or generated Gradle metadata for main candidate discovery.

## Build And Run Planning

Gradle command planning should produce explicit, explainable plans before execution. `jv run` and `jv explain` must share the same planner.

### Preferred Plan: Application Plugin

When a Gradle project appears to use the `application` plugin, JV should prefer Gradle's native run task:

```text
Build path: ./gradlew classes
Run path: ./gradlew run
```

Application plugin detection should be conservative. JV may identify obvious declarations in `build.gradle` or `build.gradle.kts`, such as:

- `id 'application'`
- `id("application")`
- `apply plugin: 'application'`

If a main class is selected and Gradle supports an override, JV may plan:

```text
./gradlew run --args="..."
```

JV should avoid modifying the build file to add the application plugin or `mainClass`.

### Fallback Plan: JavaExec Task Override

When no application plugin is detected but exactly one main class can be selected, JV may use a delegated Gradle Java execution plan only if it can do so without owning the classpath.

Acceptable fallback options, in order of preference:

1. A project-defined task that is clearly intended to run Java, if future detection can prove it.
2. A Gradle command-line init script or temporary task that asks Gradle for `sourceSets.main.runtimeClasspath` and runs `JavaExec`.

The fallback must still delegate dependency and classpath resolution to Gradle. JV should not build a classpath from Gradle caches or dependency declarations.

If this fallback is too brittle for the first Gradle milestone, the product may ship build-only delegation plus an actionable error:

```text
JV detected a Gradle project and can build it, but no Gradle run task was detected.
Add the application plugin or run with an explicit Gradle task.
```

This is preferable to a direct `javac/java` workaround that bypasses Gradle.

### Build-Only Behavior

`jv compile` for Gradle projects should delegate to Gradle:

```text
./gradlew classes
```

If `classes` is unavailable for a custom project, Gradle's own error output should be streamed. JV should summarize that the delegated Gradle build task failed.

### Limitations

Gradle is highly programmable. JV should be honest about what it can prove:

- JV does not parse arbitrary Gradle build logic.
- JV does not infer custom source sets.
- JV does not choose among multiple subprojects.
- JV does not know whether `run` exists unless it detects the application plugin or Gradle confirms the task.
- JV does not pass JVM args, system properties, environment variables, or Gradle project properties through a special JV abstraction in this milestone.

## Args Handling

Command shape remains:

```text
jv run [MainClass] [-- args...]
```

Program args after `--` are forwarded to the Java application, not to Gradle.

For application-plugin runs, JV should pass args using Gradle's `--args` option:

```text
./gradlew run --args="hello world"
```

Argument handling rules:

- Preserve argument boundaries, spaces, and empty strings where the shell implementation can do so safely.
- Do not treat program args as Gradle flags.
- If Gradle task flags are needed later, they should require a separate explicit syntax rather than being mixed with program args.
- `jv explain` should display the planned program args without executing them.
- `.jv/runs.jsonl` should record the structured program args array, not only a joined string.

If JV cannot safely represent a program argument through Gradle's `--args` string in the current implementation, it should fail with an explanation rather than lossy quoting.

## Explain, Doctor, And `.jv` Memory Integration

Gradle should use the same agent-friendly state model as runner-core.

`jv explain` should print:

- detected project shape: `Gradle project`
- detection reason: `build.gradle` or `build.gradle.kts`
- detected wrapper and selected Gradle command
- source roots scanned
- main candidates and selected main class, if any
- whether the application plugin or a run task was detected
- planned build command
- planned run command, or the reason no run command is safe

`jv doctor` should include:

- Gradle build files present
- wrapper files present and whether `gradlew` is executable
- global `gradle` availability when wrapper is missing
- Java/JDK availability
- scanned source roots
- main class candidates
- remembered main class status
- ambiguity or unsupported Gradle features detected

`.jv/state.json` should accept `projectShape: "gradle"` and record Gradle-specific plan metadata without becoming source of truth:

```json
{
  "schemaVersion": 1,
  "projectShape": "gradle",
  "buildFiles": ["build.gradle.kts"],
  "gradleCommand": "./gradlew",
  "sourceRoots": ["src/main/java"],
  "lastSuccessfulMainClass": "com.example.App",
  "lastPlan": {
    "build": ["./gradlew", "classes"],
    "run": ["./gradlew", "run", "--args=hello world"]
  }
}
```

`.jv/runs.jsonl` should record Gradle detection and delegation events:

```json
{"event":"detected_project","shape":"gradle","reason":"build.gradle.kts found"}
{"event":"selected_gradle_command","value":"./gradlew","reason":"wrapper found and executable"}
{"event":"selected_main_class","value":"com.example.App","reason":"only detected main class"}
{"event":"executed","command":["./gradlew","run","--args=hello world"],"exitCode":0}
```

Rule:

> Gradle files, source files, and local tools are truth. `.jv/` is memory.

## Error Behavior

JV should fail explicitly and make the next action clear.

Missing Gradle:

```text
Gradle project detected from build.gradle.kts, but no usable Gradle command was found.
Checked: ./gradlew, gradle on PATH
Next: run ./gradlew from the project root, make gradlew executable, or install Gradle.
```

Non-executable wrapper:

```text
Gradle wrapper found but is not executable: ./gradlew
Next: chmod +x gradlew
```

Ambiguous build system:

```text
JV found multiple build system files: pom.xml, build.gradle
JV will not choose between Maven and Gradle automatically.
Next: run the build tool directly or remove the stale build file.
```

Multiple main classes:

```text
JV found multiple main classes:
- com.example.App
- com.example.Tools

Run one explicitly:
jv run com.example.App
```

No safe run task:

```text
JV can build this Gradle project, but no safe Gradle run plan was detected.
Detected: build.gradle
Build path: ./gradlew classes
Next: add the application plugin, define a run task, or run Gradle directly.
```

Gradle execution failure:

- Stream Gradle output directly.
- Preserve Gradle's exit code.
- Summarize the failed delegated action.
- Append a failed execution event to `.jv/runs.jsonl` when the project model could be built.

Stale remembered main class:

- Warn that `.jv/state.json` refers to a main class that was not found in current source.
- List current candidates.
- Do not run the stale class.

## Testing And Success Criteria

The milestone is successful when Gradle support is covered by integration tests and manual behavior matches the design.

Core tests:

- Detect `build.gradle` as a Gradle project.
- Detect `build.gradle.kts` as a Gradle project.
- Prefer executable `./gradlew` over global `gradle`.
- Fall back to `gradle` when no wrapper exists and `gradle` is available.
- Fail clearly when a Gradle build file exists but no usable Gradle command exists.
- Fail clearly when `gradlew` exists but is not executable.
- Scan `src/main/java` and select the only Java main class.
- Refuse to choose among multiple main classes.
- Honor explicit `jv run com.example.App`.
- Reject a remembered main class that no longer exists.
- `jv explain` prints the Gradle plan without running Gradle.
- `jv doctor` reports build files, wrapper state, selected command, source roots, candidates, and ambiguity.
- `.jv/state.json` records `projectShape: "gradle"` after a successful run.
- `.jv/runs.jsonl` records structured Gradle detection, planning, and execution events.
- Program args after `--` are forwarded as application args for application-plugin projects.
- Maven plus Gradle build files produce an ambiguous-project error.

End-to-end success criteria:

- A simple Gradle Java application with `application` plugin runs through `jv run`.
- The same project can be inspected through `jv explain` without compiling or executing.
- A Gradle Java project without a safe run task builds through `jv compile` and produces an actionable no-run-task diagnostic for `jv run`.
- JV never constructs a Gradle classpath itself.
- JV never edits Gradle files.
- Failure messages identify what JV detected, what it delegated or refused to delegate, and what the user can do next.
