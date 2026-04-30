# JV Runner Core Design

## Product Definition

JV is Java middleware that turns hidden IDE and project state into one reliable action: build and run the latest code correctly.

The core product is `jv run`: an explainable runner that detects the Java project shape, resolves the latest source state, chooses the correct build/run path, and shows the user why. JV is not a Maven replacement and not another opaque project format. It is a transparent control plane over existing Java project truth.

Primary users:

- Java beginners who need the right code to run without understanding classpaths yet.
- Experienced developers who want one reliable command across simple or messy local Java projects.
- Coding agents that need a deterministic, inspectable contract for building and running Java code.

The v1 promise:

> `jv run` either runs the same code the project expects to run, from the latest source state, or explains exactly what state is missing or ambiguous.

## Supported Project Shapes

V1 supports two project families:

1. Plain Java projects
   - Source files under `src/`.
   - Optional JAR dependencies under `lib/`.
   - Package declarations mapped to fully qualified class names.
   - One or more `public static void main(String[] args)` entrypoints.

2. Maven projects
   - Detected by `pom.xml`.
   - JV delegates build and classpath behavior to Maven instead of reimplementing Maven.
   - JV may still scan `src/main/java` to detect main class candidates.

Existing `jv.json` should not remain the normal project standard. It should be replaced by generated `.jv/` memory as described below.

## User Experience

JV is teachable by default. A successful run prints a short explanation trace before execution.

Example Maven run:

```text
JV detected: Maven project
Source roots: src/main/java
Main class: com.example.App
Build path: mvn compile
Run path: mvn exec:java -Dexec.mainClass=com.example.App
```

Example plain Java run:

```text
JV detected: plain Java project
Source roots: src
Libraries: 2 jars from lib/
Main class: Main
Build path: javac -d bin ...
Run path: java -cp bin:lib/* Main
```

If JV cannot prove the correct action, it stops with a useful explanation rather than guessing silently.

## Commands

Initial command surface:

```text
jv run [MainClass] [-- args...]
jv explain [MainClass]
jv doctor
jv compile
jv remember main <MainClass>
jv forget main
```

`jv run` and `jv explain` use the same planner. `jv explain` prints the plan and exits without executing it.

`jv doctor` inspects the project and reports detected shape, source roots, available tools, main class candidates, dependency inputs, and any ambiguity.

`jv remember main` persists an explicit user choice in generated JV memory. `jv forget main` removes that choice.

## Architecture

The runner core is split into small units with clear boundaries.

### ProjectDetector

Detects the project shape from the current directory. For v1, it returns one of:

- `maven`
- `plain-java`
- `unknown`

Detection is side-effect free.

### ProjectModel

A normalized description of what JV knows about the project:

- project shape
- source roots
- output directory
- library inputs
- available Java tools
- main class candidates
- remembered user choices
- selected main class, if known

### RunnerPlanner

Chooses the build/run strategy from the project model.

- Maven project: delegate compilation and execution to Maven.
- Plain Java project: compile with `javac`, run with `java`.
- Ambiguous project: return a diagnostic plan instead of executing.

Planning is side-effect free.

### Explainer

Converts the project model and runner plan into human-readable output. This keeps teachable behavior separate from execution logic.

### Executor

Runs commands and streams output without hiding compiler or runtime errors. The executor is the only component that mutates state by compiling classes, creating output directories, invoking Maven, or writing run history.

## Main Class Resolution

For plain Java, JV scans source roots for `public static void main(String[] args)` and maps each candidate to its fully qualified class name using the `package` declaration plus file name.

If exactly one main class exists, JV uses it.

If multiple main classes exist, JV lists them and asks the user to pass one explicitly:

```text
jv run com.example.App
```

For Maven, JV detects `pom.xml`, delegates build behavior to Maven, and scans `src/main/java` for main class candidates. If the Maven exec plugin is not configured, JV uses an explicit Maven invocation rather than requiring the user to edit `pom.xml`.

## Agent-Friendly State

JV should not use `jv.json` as a normal project config file. A required project config recreates the hidden-state problem in another place.

Authoritative truth:

```text
pom.xml
src/**/*.java
lib/*.jar
package declarations
available local tools: java, javac, mvn
```

Generated JV memory:

```text
.jv/
  state.json
  runs.jsonl
```

`state.json` stores the latest known project model and explicit user choices, but it is non-authoritative. JV can regenerate it if source files or build files change.

Example:

```json
{
  "schemaVersion": 1,
  "projectShape": "maven",
  "lastSuccessfulMainClass": "com.example.App",
  "lastPlan": {
    "build": ["mvn", "compile"],
    "run": ["mvn", "exec:java", "-Dexec.mainClass=com.example.App"]
  }
}
```

`runs.jsonl` stores an append-only trace of explain/run attempts:

```json
{"event":"detected_project","shape":"maven","reason":"pom.xml found"}
{"event":"selected_main_class","value":"com.example.App","reason":"only detected main class"}
{"event":"executed","command":["mvn","compile"],"exitCode":0}
```

Rule:

> Source files and build tools are truth. `.jv/` is memory.

This gives coding agents an inspectable trail of what JV saw, what it decided, what command it ran, and what failed last time, without making users maintain another dependency-style file.

## Failure Behavior

JV should fail explicitly and explain the missing or ambiguous state.

- No Java found: explain that a JDK is required, not just a JRE.
- No source roots found: show which directories JV checked.
- Multiple main classes: list candidates and ask for an explicit class.
- Stale or missing build output: rebuild.
- Maven project but Maven unavailable: explain that `pom.xml` was detected but `mvn` is not installed.
- Compiler failure: stream `javac` or Maven output directly, then summarize the failed action.
- Remembered main class missing from source: warn that `.jv/state.json` is stale, show detected candidates, and do not silently trust memory.

## Non-Goals For V1

- Gradle support.
- IntelliJ, Eclipse, or VS Code project metadata support.
- Dependency resolution beyond Maven delegation and plain `lib/*.jar`.
- A required hand-authored JV config file.
- Reimplementing Maven lifecycle behavior.

## Success Criteria

- `jv run` works for a plain Java project with one main class.
- `jv run` detects multiple plain Java main classes and refuses to guess.
- `jv run <MainClass>` works for plain Java projects with packages and `lib/*.jar`.
- `jv run` detects Maven projects and delegates build/run behavior to Maven.
- `jv explain` prints the same plan `jv run` would execute without mutating project state.
- `.jv/state.json` and `.jv/runs.jsonl` are generated memory only and are never required for a normal first run.
- Failure messages identify what JV detected, what it tried to prove, and what the user can do next.
