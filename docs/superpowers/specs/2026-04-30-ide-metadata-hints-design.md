# JV Milestone 4: IDE Metadata Hints Design

## Product Goal

JV should read common Java IDE metadata as supporting evidence when planning `jv run`, `jv explain`, and `jv doctor`.

The milestone extends the runner-core rule:

> Source files and build tools are truth. `.jv/` is memory. IDE metadata is hints.

IDE metadata often contains the state beginners expect the IDE to know: source folders, library jars, output directories, selected SDKs, and launch targets. JV should use that state to make plain Java projects work more often and to explain why Maven, Gradle, or source scanning still wins when there is a conflict.

The user-facing promise:

> If an IDE can help JV prove the right build/run path, JV uses that evidence. If IDE metadata is stale, partial, or conflicts with source/build truth, JV surfaces the conflict instead of silently trusting it.

## Non-Goals

- Replacing Maven, Gradle, or the Java compiler's own model.
- Treating IDE files as authoritative project configuration.
- Writing or repairing `.idea/`, `.classpath`, `.project`, `.vscode/`, or IDE workspace files.
- Implementing full IntelliJ, Eclipse, or VS Code project import semantics.
- Resolving remote dependencies declared only through IDE metadata.
- Supporting every IDE plugin-specific format or generated workspace cache.
- Making `.jv/` depend on IDE metadata for normal operation.

## Supported Hint Sources

Milestone 4 supports project-local metadata only. User-global IDE settings are out of scope because they are hard to make portable and explainable.

### IntelliJ IDEA

Supported files:

```text
.idea/modules.xml
.idea/modules/*.iml
*.iml
```

Hints JV may read:

- Source roots from module `content` entries.
- Test source roots as non-run source roots, useful for diagnostics but not normal main-class selection.
- Excluded roots so generated or build directories are not scanned as source.
- Module output and test output directories.
- Module library jar paths and project library jar references when they resolve to local files.
- SDK or language level names as notes, not as selected Java executables.

### Eclipse

Supported files:

```text
.project
.classpath
```

Hints JV may read:

- Java project identity from `.project` natures.
- Source roots from `.classpath` entries with `kind="src"`.
- Local library jars from `.classpath` entries with `kind="lib"`.
- Output directory from `.classpath` entries with `kind="output"`.
- JRE container names as SDK/toolchain notes.
- Linked resources only when they resolve inside the project or to an existing local path.

### VS Code

Supported files:

```text
.vscode/settings.json
.vscode/tasks.json
.vscode/launch.json
```

Hints JV may read:

- Java source paths and referenced libraries from `java.project.sourcePaths` and `java.project.referencedLibraries`.
- Java output path from `java.project.outputPath`.
- Java configuration runtimes from `java.configuration.runtimes` as SDK/toolchain notes.
- Task labels and commands as evidence that a project has an expected build command.
- Launch configuration `mainClass`, `projectName`, `classPaths`, and `modulePaths` as main-class and classpath hints.

VS Code tasks are hints only. JV should not execute arbitrary task commands as the default run path in this milestone.

## Hint Precedence

JV builds a normalized `ProjectModel` from evidence ordered by authority.

1. Explicit user input for this invocation, such as `jv run com.example.App`.
2. Authoritative build tools: Maven `pom.xml`, Gradle build files, and their delegated classpath/build behavior.
3. Source truth: existing `src/**/*.java`, package declarations, `public static void main(String[] args)`, and local `lib/*.jar`.
4. Generated `.jv/` memory, limited to explicit user choices and previous successful observations.
5. IDE metadata hints from IntelliJ, Eclipse, and VS Code.
6. Generic fallbacks, such as conventional `src/`, `bin/`, and `out/` directories.

Rules:

- Maven and Gradle projects keep their build-tool run path. IDE metadata may add explanation and diagnostics, but it must not replace delegated build behavior.
- Plain Java projects may use IDE hints to expand source roots, include local jars, pick an output directory, and rank main-class candidates.
- `.jv/` memory can remember an explicit user choice, but stale memory does not beat current source files.
- IDE metadata cannot override a source root, jar, output directory, or main class that no longer exists.

## What Hints Can Influence

### Source Roots

IDE metadata can add source roots when JV would otherwise only scan conventional directories. A hinted source root is usable only if:

- The path exists.
- The path is inside the project root or is an explicitly linked local path.
- It is not also marked excluded by the same IDE source.
- It contains Java files or is needed to explain an empty source state.

If a build tool declares source roots, IDE source roots are diagnostic evidence only unless they match the build-tool model.

### Classpath Jars

IDE metadata can add local jar files to a plain Java classpath when:

- The jar path resolves to an existing file.
- The jar is local and readable.
- The jar is not inside a known output directory.

IDE jar hints should be merged with `lib/*.jar` and de-duplicated by resolved path. Missing jars are reported by `doctor` and ignored by `run` unless a selected main class requires compilation that then fails.

### Output Directories

IDE metadata can suggest output directories for plain Java compilation, such as `bin`, `out/production/<module>`, or an Eclipse output path.

JV may use a hinted output directory only when it is:

- Inside the project root.
- Not a source root.
- Not an IDE metadata directory.
- Not ambiguous across multiple active hint sources.

If there is no safe single IDE output hint, JV keeps its existing default output directory.

### SDK And Toolchain Notes

IDE metadata can explain expected SDK names, language levels, or configured runtime labels. These are notes, not commands.

JV still selects actual tools from the local environment:

```text
java
javac
mvn
gradle
```

If IDE metadata says the project expects Java 21 but `java -version` reports Java 17, `doctor` should warn with confidence based on the evidence source. `jv run` should only fail early when the mismatch can be proven to make compilation impossible; otherwise compiler output remains the final authority.

### Main Class Candidates

IDE launch metadata can rank main class candidates but should not skip source validation.

Allowed influence:

- If `launch.json` names `com.example.App` and source scanning finds that same main class, JV may prefer it over other detected candidates and explain why.
- If an IntelliJ or Eclipse run configuration is later supported, it follows the same rule.
- If IDE metadata names a main class that is not found in source or build output, JV reports a stale hint and refuses to run it silently.

Main class selection order:

1. Main class passed to `jv run` or `jv explain`.
2. Explicit `.jv/` remembered main class that still exists in source.
3. Single source-scanned main class.
4. IDE launch main class that matches a source-scanned candidate.
5. Ambiguous candidates: stop and ask for an explicit class.

## Evidence And Confidence

Each hint should be stored internally as evidence with:

- source type: `intellij`, `eclipse`, `vscode`, `source`, `build-tool`, `.jv`, or `fallback`
- file path
- extracted value
- whether the referenced path or class currently exists
- confidence: `authoritative`, `high`, `medium`, `low`, or `stale`
- reason

Suggested confidence levels:

- `authoritative`: Maven or Gradle build model, explicit CLI argument, current source scan.
- `high`: IDE hint that matches source/build truth.
- `medium`: IDE hint that fills a gap in a plain Java project and resolves to existing files.
- `low`: IDE hint from partial metadata or a task/launch command JV cannot safely execute.
- `stale`: IDE hint that points to missing files, missing classes, excluded paths, or paths outside the project without an explicit linked-resource rule.

## Explain And Doctor UX

`jv explain` should show the final plan plus the evidence that affected it.

Example:

```text
JV detected: plain Java project
Source roots:
  src
  app/src/main/java    hint: Eclipse .classpath, confidence: medium
Libraries:
  lib/json.jar         source: lib/*.jar
  vendor/junit.jar     hint: VS Code settings, confidence: medium
Main class: com.example.App
  reason: VS Code launch.json matched detected source main
Build path: javac -d bin -cp ...
Run path: java -cp ... com.example.App
```

`jv doctor` should include all relevant evidence, including ignored hints.

Example:

```text
IDE hints:
  IntelliJ .idea/modules/app.iml
    source root: src/main/java                 matches Maven, ignored for planning
    output dir: out/production/app             ignored because Maven is authoritative
  VS Code .vscode/launch.json
    main class: com.old.App                    stale, class not found in source
```

Doctor should make confidence visible without making users learn an internal scoring system. Phrases like `matched source`, `fills gap`, `ignored because Maven is authoritative`, and `stale: missing path` are more useful than numeric scores.

## Safety Rules

- Never silently trust IDE metadata over Maven, Gradle, current source files, package declarations, or explicit CLI input.
- Never execute arbitrary IDE task commands as the default run path in this milestone.
- Never add missing jar paths to the runtime classpath.
- Never compile into a directory that is also a source root or IDE metadata directory.
- Never treat a launch main class as valid unless source scanning or build-tool evidence confirms it.
- Never persist IDE hints into `.jv/state.json` as if they were explicit user choices.
- Never hide conflicts. If a hint is ignored because stronger evidence disagrees, `doctor` should say so.
- Never fail solely because optional IDE metadata is malformed when source/build truth is sufficient. Report the parse issue in `doctor`.

## Error Behavior And Conflicts

JV should classify IDE metadata problems as warnings unless they block a chosen plan.

Failure cases:

- Multiple source root sets from IDE metadata and no source/build truth to choose between: stop and ask for an explicit root or show the conflicting evidence in `doctor`.
- IDE output directory is unsafe: ignore it and use the default output directory; fail only if no safe output directory can be selected.
- IDE launch main class is missing from source: treat it as stale and continue candidate resolution; if no valid main remains, fail with a stale-hint explanation.
- Hinted jar is missing: warn in `doctor`; for `run`, omit it and let `javac` expose any resulting missing dependency errors.
- Malformed XML or JSON: ignore that file for planning, report parse errors in `doctor`, and continue with other evidence.
- Build tool and IDE source roots disagree: build tool wins; `doctor` reports the mismatch.
- Two IDEs disagree in a plain Java project: prefer hints that match current source files; otherwise do not guess.

Conflict messages should name the files involved and the decision JV made.

## Architecture Changes

Add an `IdeHintCollector` layer between project detection and planning.

Responsibilities:

- Discover supported IDE metadata files.
- Parse metadata with structured XML and JSON parsing.
- Normalize paths relative to the project root.
- Emit evidence records without mutating project state.
- Never choose the final plan directly.

The existing planner consumes a `ProjectModel` enriched with evidence:

```text
ProjectDetector -> SourceScanner -> BuildToolDetector
                -> IdeHintCollector -> ProjectModel -> RunnerPlanner
```

The planner keeps precedence logic centralized. IDE collectors should not know whether a hint will be used, only whether it was found and whether it resolves safely.

## Testing And Success Criteria

Automated tests should use small fixture projects with real metadata files.

Required test coverage:

- IntelliJ `.iml` source root is used for a plain Java project with no conventional `src/`.
- Eclipse `.classpath` adds a source root, local jar, and output directory when all paths exist.
- VS Code `settings.json` source paths and referenced libraries are merged into a plain Java plan.
- VS Code `launch.json` main class ranks a candidate only when it matches a scanned source main.
- Maven project with conflicting IntelliJ source root still delegates to Maven and reports the hint as ignored.
- Stale IDE main class is reported and not run.
- Missing hinted jar is reported by `doctor` and omitted from the classpath.
- Malformed IDE metadata does not break `jv run` when source/build truth is enough.
- Conflicting IDE output directories fall back to the safe default.
- `jv explain` and `jv doctor` display evidence source, file path, decision, and confidence language.

Success criteria:

- Plain Java projects exported from IntelliJ, Eclipse, and VS Code can run when their metadata points to existing source roots and local jars.
- Build-tool projects remain governed by Maven or Gradle even when IDE metadata disagrees.
- Users can see exactly which IDE hints affected a plan and which were ignored.
- Stale IDE metadata never causes JV to run an old or missing main class silently.
- Optional IDE metadata parse failures are diagnosable and do not make valid projects unusable.
- `.jv/` remains generated memory and does not become a second source of IDE-derived truth.
