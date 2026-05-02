# JV Gradle Delegation Design

## Product Goal

JV should support Gradle projects by delegating build and run behavior to Gradle while preserving the runner-core promise:

> `jv run` either runs the same code the Gradle project expects to run, from the latest source state, or explains exactly what state is missing or ambiguous.

This slice extends the current Bash planner architecture. `build_plan` remains the shared source for `run`, `explain`, `doctor`, and `.jv` memory. Gradle support adds a new project shape, tool requirements, command selection, Gradle-specific blockers, and conservative run planning.

Product principle:

> Gradle support should delegate to Gradle, not emulate it.

JV must not parse dependencies, synthesize Gradle classpaths, model custom source sets, or compile Gradle projects with direct `javac` commands.

## MVP Scope

Detect Gradle from root-level markers:

- `settings.gradle`
- `settings.gradle.kts`
- `build.gradle`
- `build.gradle.kts`
- `gradlew`

Command selection:

1. Prefer executable `./gradlew`.
2. If `gradlew` exists but is not executable, block and say `chmod +x gradlew`.
3. If no wrapper exists, use `gradle` from `PATH`.
4. If neither usable wrapper nor `gradle` exists, block.

Run strategy:

1. If the root build file obviously applies the Gradle `application` plugin, plan `run`.
2. If the user passes or JV selects a main class, pass it as `-PmainClass=<ClassName>` for builds that already opt into that property.
3. Do not discover or synthesize arbitrary `JavaExec` tasks in the MVP.
4. If no application plugin is detected, `jv compile` may delegate to `classes`, but `jv run` blocks with a clear no-safe-run-task diagnostic.

This MVP deliberately chooses the blocker over brittle JavaExec discovery because a shell implementation cannot prove a custom task's classpath or semantics without asking Gradle to own that behavior.

## Non-Goals

- Dependency parsing from `build.gradle` or `build.gradle.kts`.
- Gradle source-set emulation beyond scanning `src/main/java` for Java main candidates.
- Multi-project task selection.
- Android, Kotlin/JVM, Scala, Groovy, generated sources, or custom JVM source roots.
- Editing Gradle files, wrapper files, or `.jv` memory by hand.
- Inferring a classpath from `.gradle/`, `build/`, dependency declarations, or local caches.
- Running a direct `javac` or `java -cp ...` path for Gradle projects.

## Planner Integration

`detect_project_shape` should return a new `gradle` shape when Gradle markers exist and no conflicting build-tool root is present.

Detection precedence:

1. Ambiguous build-tool project when Maven and Gradle markers both exist.
2. Gradle when any Gradle marker exists and Maven is absent.
3. Maven when `pom.xml` exists and Gradle markers are absent.
4. Plain Java when `src/` exists and no build-tool marker exists.
5. Unknown.

Add planner fields as Bash globals, following the existing runner-core style:

```bash
PLAN_GRADLE_BUILD_FILES=()
PLAN_GRADLE_SETTINGS_FILES=()
PLAN_GRADLE_WRAPPER=""
PLAN_GRADLE_WRAPPER_STATUS=""
PLAN_GRADLE_COMMAND=""
PLAN_GRADLE_COMMAND_SOURCE=""
PLAN_GRADLE_HAS_APPLICATION_PLUGIN=""
PLAN_GRADLE_MAIN_PROPERTY=""
```

Required tools:

- Gradle project with executable wrapper: `java`; wrapper is the Gradle command.
- Gradle project without wrapper: `java`, `gradle`.
- `javac` is not required for Gradle project execution because Gradle owns compilation.

Source roots:

- Scan `src/main/java` for main candidates.
- If `src/main/java` is missing but `src/` exists, report `src/` as an inspected fallback for diagnostics only.
- Do not treat fallback scanning as source-set support.

Planning rules:

- Build command: `<gradle-command> classes`
- Run command with application plugin and no selected main: `<gradle-command> run`
- Run command with application plugin and selected main: `<gradle-command> run -PmainClass=<ClassName>`
- Run command with application plugin and args: `<gradle-command> run -PmainClass=<ClassName> --args="<joined args>"`
- No application plugin: blocker for `jv run`, build-only plan remains available for `jv compile`.

`jv run`, `jv explain`, and `jv doctor` must render the same selected Gradle command, source roots, main selection, reasons, warnings, and blockers from the shared planner.

## Conservative Application Plugin Detection

JV may identify only obvious root build file declarations:

```text
id 'application'
id("application")
apply plugin: 'application'
apply(plugin = "application")
```

If both `build.gradle` and `build.gradle.kts` exist, list both as build files and scan both for these simple markers. This is diagnostic, not a full Gradle parser.

JV should not run `gradle tasks` in `explain` or `doctor`; those commands must remain side-effect free. A later slice can add explicit Gradle introspection if it is clearly separated from planning.

## Argument Handling

The current CLI shape is `jv run [MainClass] [args...]`. Gradle MVP should keep that shape for consistency with plain Java and Maven.

For application-plugin projects, program args are forwarded through Gradle `--args`:

```text
./gradlew run -PmainClass=com.example.App --args="one two"
```

JV should join args only for display and Gradle invocation. If an arg contains a newline or cannot be safely represented in the current Bash implementation, block with:

```text
Blocker: Gradle --args cannot safely represent one or more program arguments yet.
```

## Command Examples

Successful wrapper-backed application project:

```text
$ jv explain one two
JV detected: Gradle project
Source roots: src/main/java
Gradle command: ./gradlew
Gradle command reason: wrapper found and executable
Main class: com.example.App
Build path: ./gradlew classes
Run path: ./gradlew run -PmainClass=com.example.App --args="one two"
Reason: build.gradle.kts found in project root
Reason: gradlew found and executable
Reason: src/main/java exists
Reason: application plugin detected in build.gradle.kts
Reason: exactly one main class detected
```

Fallback to global Gradle:

```text
$ jv explain
JV detected: Gradle project
Source roots: src/main/java
Gradle command: gradle
Gradle command reason: no wrapper found; gradle found on PATH
Main class: com.example.App
Build path: gradle classes
Run path: gradle run -PmainClass=com.example.App
Reason: settings.gradle found in project root
Reason: gradle found on PATH
Reason: application plugin detected in build.gradle
Reason: exactly one main class detected
```

Non-executable wrapper:

```text
$ jv run
JV detected: Gradle project
Source roots: src/main/java
Gradle command: none
Reason: build.gradle found in project root
Blocker: Gradle wrapper found but is not executable: ./gradlew. Next: chmod +x gradlew
```

Missing Gradle command:

```text
$ jv run
JV detected: Gradle project
Source roots: src/main/java
Reason: build.gradle.kts found in project root
Blocker: Gradle project detected, but no usable Gradle command was found. Checked: ./gradlew, gradle on PATH
```

No safe run task:

```text
$ jv run
JV detected: Gradle project
Source roots: src/main/java
Gradle command: ./gradlew
Main class: com.example.App
Build path: ./gradlew classes
Reason: build.gradle found in project root
Reason: gradlew found and executable
Reason: no application plugin detected
Reason: exactly one main class detected
Blocker: JV can build this Gradle project, but no safe Gradle run plan was detected. Next: add the application plugin or run Gradle directly.
```

Ambiguous Maven plus Gradle:

```text
$ jv explain
JV detected: ambiguous project
Reason: multiple build system files found: pom.xml, build.gradle
Blocker: JV will not choose between Maven and Gradle automatically.
```

Doctor:

```text
$ jv doctor
JV doctor

Project
  Shape: gradle
  Shape reason: build.gradle.kts found in project root
  Gradle build files: build.gradle.kts
  Gradle settings files: settings.gradle.kts
  Source roots: src/main/java
  Tools:
    java: /usr/bin/java (required) - openjdk version "21.0.2"
    javac: /usr/bin/javac (optional) - javac 21.0.2
    mvn: missing (optional)
    gradle: wrapper ./gradlew (required)

Selected plan
  Main class: com.example.App
  Main source: only-candidate
  Build: ./gradlew classes
  Run: ./gradlew run -PmainClass=com.example.App

Reasons
  - build.gradle.kts found in project root
  - gradlew found and executable
  - src/main/java exists
  - application plugin detected in build.gradle.kts
  - exactly one main class detected

Blockers
  none
```

State after a successful run:

```json
{
  "schemaVersion": 1,
  "projectShape": "gradle",
  "lastSuccessfulMainClass": "com.example.App",
  "lastPlan": {
    "build": "./gradlew classes",
    "run": "./gradlew run -PmainClass=com.example.App --args=\"one two\""
  },
  "planner": {
    "shapeReason": "build.gradle.kts found in project root",
    "sourceRoot": "src/main/java",
    "selectedMainSource": "only-candidate",
    "reasons": ["build.gradle.kts found in project root", "gradlew found and executable", "application plugin detected in build.gradle.kts"],
    "warnings": [],
    "blockers": []
  }
}
```

Run history after a successful run:

```json
{"event":"executed","detail":"./gradlew run -PmainClass=com.example.App --args=\"one two\""}
```

## Error Behavior

- Blocked `jv run` prints the plan summary and returns non-zero without invoking Gradle.
- `jv explain` prints blockers and returns non-zero for non-runnable Gradle plans.
- `jv doctor` reports blockers as diagnostics and should return zero unless doctor itself fails.
- Gradle build/run failures stream Gradle output and preserve Gradle's exit code.
- JV summarizes the failed delegated command but does not hide Gradle output.
- Successful Gradle runs update `.jv/state.json` and `.jv/runs.jsonl` through the existing memory writer.

## Success Criteria

- `jv explain` detects `settings.gradle`, `settings.gradle.kts`, `build.gradle`, `build.gradle.kts`, and `gradlew` as Gradle markers.
- Executable `./gradlew` is preferred over global `gradle`.
- Non-executable `gradlew` blocks with `chmod +x gradlew`.
- Global `gradle` is used only when no wrapper exists.
- `jv compile` delegates Gradle projects to `<gradle-command> classes`.
- `jv run` delegates application-plugin projects to `<gradle-command> run`.
- `jv run` blocks, rather than emulates, when no safe Gradle run task is detected.
- `jv doctor` reports Gradle build files, wrapper state, selected command, source roots, candidates, reasons, and blockers.
- `.jv/state.json` records `projectShape: "gradle"` after a successful run.
- JV never constructs a Gradle classpath itself.
