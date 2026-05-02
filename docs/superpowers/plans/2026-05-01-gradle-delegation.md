# Gradle Delegation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conservative Gradle project support to JV by detecting Gradle markers, selecting a Gradle command, delegating compile/run to Gradle, and exposing all decisions through the existing planner, doctor, explain, run, and `.jv` memory surfaces.

**Architecture:** Extend the current Bash planner in `jv.sh`; do not add new production files. `build_plan` remains the single side-effect-free source for project shape, source roots, required tools, main selection, Gradle command choice, reasons, blockers, and display commands. `run_java`, `compile_java`, `explain_project`, `doctor_project`, and memory writes consume the planner instead of duplicating Gradle detection.

**Tech Stack:** Bash, shell integration tests in `tests/run-tests.sh`, Gradle wrapper shell scripts in temporary test projects, optional global `gradle`, existing `.jv/state.json` and `.jv/runs.jsonl` memory.

---

## File Structure

- Modify `jv.sh`: add Gradle detection helpers, planner globals, command selection, application-plugin detection, Gradle build/run execution, doctor rendering, and help text.
- Modify `tests/run-tests.sh`: add Gradle fixtures and integration tests for detection, wrappers, blockers, application-plugin runs, compile delegation, doctor output, and memory.
- Modify `README.md`: only if existing command examples need a short Gradle mention after behavior changes.
- Modify `EXAMPLES.md`: only if examples exist and need a small Gradle troubleshooting example.

Do not modify unrelated implementation files. Do not touch the pre-existing untracked `cli/` directory.

## Commit Strategy

Commit after each task:

```bash
git add jv.sh tests/run-tests.sh README.md EXAMPLES.md
git commit -m "<message from task>"
```

If a task does not modify docs, omit doc files from `git add`. Keep commits small enough that each one can be reverted independently.

## Verification Commands

Run after each task that changes behavior:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

If `shellcheck` is not installed, record that it could not be run and continue after `tests/run-tests.sh` and `bash -n` pass.

## Task 1: Add Gradle Marker Detection And Ambiguous Build-System Blocker

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing detection tests**

Add these tests before `main()` in `tests/run-tests.sh`:

```bash
test_explain_detects_gradle_build_file() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example" "$TMP_ROOT/app/fake-bin"
    cd "$TMP_ROOT/app"
    cat > build.gradle.kts <<'GRADLE'
plugins {
    application
}
GRADLE
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("gradle app");
    }
}
JAVA
    cat > "$TMP_ROOT/app/fake-bin/gradle" <<'SH'
#!/usr/bin/env bash
echo "fake gradle $*"
SH
    chmod +x "$TMP_ROOT/app/fake-bin/gradle"

    local output
    output="$(PATH="$TMP_ROOT/app/fake-bin:$PATH" "$JV" explain)"

    assert_contains "$output" "JV detected: Gradle project"
    assert_contains "$output" "Source roots: src/main/java"
    assert_contains "$output" "Gradle command: gradle"
    assert_contains "$output" "Build path: gradle classes"
    assert_contains "$output" "Run path: gradle run -PmainClass=com.example.App"
    assert_contains "$output" "Reason: build.gradle.kts found in project root"
}

test_explain_blocks_ambiguous_maven_and_gradle() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java"
    cd "$TMP_ROOT/app"
    cat > pom.xml <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>ambiguous</artifactId>
  <version>1.0.0</version>
</project>
XML
    : > build.gradle

    set +e
    local output
    output="$("$JV" explain 2>&1)"
    local status=$?
    set -e

    assert_status "$status" 1
    assert_contains "$output" "JV detected: ambiguous project"
    assert_contains "$output" "Reason: multiple build system files found: pom.xml, build.gradle"
    assert_contains "$output" "Blocker: JV will not choose between Maven and Gradle automatically."
}
```

Add both tests to `main()` before Maven tests.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: `test_explain_detects_gradle_build_file` fails because Gradle is not detected yet.

- [ ] **Step 3: Add Gradle marker helpers**

In `jv.sh`, add near `detect_project_shape`:

```bash
gradle_markers() {
    local markers=()
    local marker
    for marker in settings.gradle settings.gradle.kts build.gradle build.gradle.kts gradlew; do
        [[ -e "$marker" ]] && markers+=("$marker")
    done
    printf '%s\n' "${markers[@]}"
}

gradle_build_files() {
    local files=()
    local file
    for file in build.gradle build.gradle.kts; do
        [[ -f "$file" ]] && files+=("$file")
    done
    printf '%s\n' "${files[@]}"
}

join_csv() {
    local joined=""
    local item
    for item in "$@"; do
        [[ -n "$joined" ]] && joined="$joined, "
        joined="$joined$item"
    done
    printf '%s' "$joined"
}
```

- [ ] **Step 4: Extend project shape detection**

Replace `detect_project_shape` with:

```bash
detect_project_shape() {
    local gradle=0
    if [[ -n "$(gradle_markers)" ]]; then
        gradle=1
    fi

    if [[ -f "pom.xml" && "$gradle" -eq 1 ]]; then
        echo "ambiguous"
    elif [[ "$gradle" -eq 1 ]]; then
        echo "gradle"
    elif [[ -f "pom.xml" ]]; then
        echo "maven"
    elif [[ -d "$SRC_DIR" ]]; then
        echo "plain-java"
    else
        echo "unknown"
    fi
}
```

- [ ] **Step 5: Add Gradle and ambiguous shape handling to planner summary**

In `build_plan`, add cases before `maven`:

```bash
ambiguous)
    local markers=()
    while IFS= read -r marker; do
        [[ -n "$marker" ]] && markers+=("$marker")
    done < <(gradle_markers)
    PLAN_SHAPE_REASON="multiple build system files found: $(join_csv pom.xml "${markers[@]}")"
    plan_add_reason "$PLAN_SHAPE_REASON"
    plan_add_blocker "JV will not choose between Maven and Gradle automatically."
    return 0
    ;;
gradle)
    local build_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && build_files+=("$file")
    done < <(gradle_build_files)
    if [[ ${#build_files[@]} -gt 0 ]]; then
        PLAN_SHAPE_REASON="${build_files[0]} found in project root"
    else
        PLAN_SHAPE_REASON="$(gradle_markers | head -n 1) found in project root"
    fi
    PLAN_REQUIRED_TOOLS=("java")
    ;;
```

In `source_root_for_shape`, add:

```bash
gradle) echo "src/main/java" ;;
```

In `print_plan_summary`, add:

```bash
gradle) echo "JV detected: Gradle project" ;;
ambiguous) echo "JV detected: ambiguous project" ;;
```

- [ ] **Step 6: Run tests**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
```

Expected: all tests pass except Gradle command/run path assertions may still fail until Task 2. If they fail, proceed directly to Task 2 before committing.

- [ ] **Step 7: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: detect Gradle projects"
```

## Task 2: Select Gradle Command And Wrapper Blockers

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing wrapper tests**

Add:

```bash
test_gradle_prefers_executable_wrapper() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example" "$TMP_ROOT/app/fake-bin"
    cd "$TMP_ROOT/app"
    cat > build.gradle <<'GRADLE'
plugins {
    id 'application'
}
GRADLE
    cat > gradlew <<'SH'
#!/usr/bin/env bash
echo "wrapper $*"
SH
    chmod +x gradlew
    cat > "$TMP_ROOT/app/fake-bin/gradle" <<'SH'
#!/usr/bin/env bash
echo "global $*"
SH
    chmod +x "$TMP_ROOT/app/fake-bin/gradle"
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("wrapper app");
    }
}
JAVA

    local output
    output="$(PATH="$TMP_ROOT/app/fake-bin:$PATH" "$JV" explain)"

    assert_contains "$output" "Gradle command: ./gradlew"
    assert_contains "$output" "Reason: gradlew found and executable"
    assert_contains "$output" "Build path: ./gradlew classes"
}

test_gradle_blocks_non_executable_wrapper() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    : > build.gradle
    : > gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    set +e
    local output
    output="$("$JV" explain 2>&1)"
    local status=$?
    set -e

    assert_status "$status" 1
    assert_contains "$output" "Gradle command: none"
    assert_contains "$output" "Blocker: Gradle wrapper found but is not executable: ./gradlew. Next: chmod +x gradlew"
}
```

Add both tests to `main()`.

- [ ] **Step 2: Add planner globals**

Near existing `PLAN_` globals in `jv.sh`, add:

```bash
PLAN_GRADLE_COMMAND=""
PLAN_GRADLE_COMMAND_SOURCE=""
PLAN_GRADLE_HAS_APPLICATION_PLUGIN=""
```

Reset them in `reset_plan`.

- [ ] **Step 3: Add command selector**

Add:

```bash
select_gradle_command() {
    if [[ -e "gradlew" ]]; then
        if [[ -x "gradlew" ]]; then
            PLAN_GRADLE_COMMAND="./gradlew"
            PLAN_GRADLE_COMMAND_SOURCE="wrapper"
            plan_add_reason "gradlew found and executable"
        else
            PLAN_GRADLE_COMMAND=""
            PLAN_GRADLE_COMMAND_SOURCE="blocked-wrapper"
            plan_add_blocker "Gradle wrapper found but is not executable: ./gradlew. Next: chmod +x gradlew"
        fi
        return 0
    fi

    if command -v gradle >/dev/null 2>&1; then
        PLAN_GRADLE_COMMAND="gradle"
        PLAN_GRADLE_COMMAND_SOURCE="path"
        plan_add_reason "gradle found on PATH"
    else
        PLAN_GRADLE_COMMAND=""
        PLAN_GRADLE_COMMAND_SOURCE="missing"
        plan_add_blocker "Gradle project detected, but no usable Gradle command was found. Checked: ./gradlew, gradle on PATH"
    fi
}
```

Call `select_gradle_command` inside the `gradle)` branch of `build_plan` after `plan_add_reason "$PLAN_SHAPE_REASON"`.

- [ ] **Step 4: Render Gradle command**

In `print_plan_summary`, after source roots:

```bash
if [[ "$PLAN_SHAPE" == "gradle" ]]; then
    echo "Gradle command: ${PLAN_GRADLE_COMMAND:-none}"
fi
```

In `print_doctor_report`, include `gradle` in the tools loop and render wrapper specially:

```bash
for item in java javac mvn gradle; do
    if [[ "$item" == "gradle" && "$PLAN_GRADLE_COMMAND_SOURCE" == "wrapper" ]]; then
        echo "    gradle: wrapper $PLAN_GRADLE_COMMAND (required)"
        continue
    fi
    ...
done
```

- [ ] **Step 5: Run verification**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: all tests pass, or only `shellcheck` is skipped because it is not installed.

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: select Gradle command"
```

## Task 3: Plan Application-Plugin Gradle Runs Conservatively

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing application-plugin and no-run-task tests**

Add:

```bash
test_gradle_application_plugin_run_with_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    cat > build.gradle.kts <<'GRADLE'
plugins {
    application
}
GRADLE
    cat > gradlew <<'SH'
#!/usr/bin/env bash
echo "gradlew-called:$*"
SH
    chmod +x gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    local output
    output="$("$JV" explain com.example.App one two)"

    assert_contains "$output" "Run path: ./gradlew run -PmainClass=com.example.App --args=\"one two\""
    assert_contains "$output" "Reason: application plugin detected in build.gradle.kts"
}

test_gradle_without_application_plugin_blocks_run() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    cat > build.gradle <<'GRADLE'
plugins {
    id 'java'
}
GRADLE
    cat > gradlew <<'SH'
#!/usr/bin/env bash
echo "gradlew-called:$*"
SH
    chmod +x gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    set +e
    local output
    output="$("$JV" explain 2>&1)"
    local status=$?
    set -e

    assert_status "$status" 1
    assert_contains "$output" "Build path: ./gradlew classes"
    assert_contains "$output" "Reason: no application plugin detected"
    assert_contains "$output" "Blocker: JV can build this Gradle project, but no safe Gradle run plan was detected. Next: add the application plugin or run Gradle directly."
    assert_not_contains "$output" "Run path:"
}
```

Add both tests to `main()`.

- [ ] **Step 2: Add application plugin detection**

Add:

```bash
gradle_has_application_plugin() {
    local file
    for file in build.gradle build.gradle.kts; do
        [[ -f "$file" ]] || continue
        if grep -Eq "id[[:space:]]+['\"]application['\"]|id\\([[:space:]]*['\"]application['\"][[:space:]]*\\)|apply[[:space:]]+plugin:[[:space:]]*['\"]application['\"]|apply\\([[:space:]]*plugin[[:space:]]*=[[:space:]]*['\"]application['\"][[:space:]]*\\)" "$file"; then
            printf '%s\n' "$file"
            return 0
        fi
    done
    return 1
}
```

- [ ] **Step 3: Add Gradle command planning**

In the final `case "$PLAN_SHAPE"` block inside `build_plan`, add:

```bash
gradle)
    PLAN_BUILD_KIND="gradle"
    PLAN_RUN_KIND="gradle"
    if [[ -n "$PLAN_GRADLE_COMMAND" ]]; then
        PLAN_BUILD_DISPLAY="$PLAN_GRADLE_COMMAND classes"
    fi
    local plugin_file
    plugin_file="$(gradle_has_application_plugin || true)"
    if [[ -n "$plugin_file" ]]; then
        PLAN_GRADLE_HAS_APPLICATION_PLUGIN="yes"
        plan_add_reason "application plugin detected in $plugin_file"
        if [[ -n "$PLAN_GRADLE_COMMAND" ]]; then
            PLAN_RUN_DISPLAY="$PLAN_GRADLE_COMMAND run -PmainClass=$class_name"
            [[ -n "$run_args" ]] && PLAN_RUN_DISPLAY="$PLAN_RUN_DISPLAY --args=\"$run_args\""
        fi
    else
        PLAN_GRADLE_HAS_APPLICATION_PLUGIN="no"
        plan_add_reason "no application plugin detected"
        plan_add_blocker "JV can build this Gradle project, but no safe Gradle run plan was detected. Next: add the application plugin or run Gradle directly."
    fi
    ;;
```

Keep existing `plain-java` and `maven` behavior unchanged.

- [ ] **Step 4: Run verification**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: all tests pass, or only `shellcheck` is skipped because it is not installed.

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: plan Gradle application runs"
```

## Task 4: Execute Gradle Compile And Run Through The Planner

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing execution tests**

Add:

```bash
test_gradle_run_delegates_to_wrapper_and_writes_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    cat > build.gradle <<'GRADLE'
plugins {
    id 'application'
}
GRADLE
    cat > gradlew <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> gradle.calls
if [[ "$1" == "run" ]]; then
    echo "fake gradle run"
fi
SH
    chmod +x gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    local output
    output="$("$JV" run com.example.App one two)"

    assert_contains "$output" "fake gradle run"
    assert_contains "$(cat gradle.calls)" "classes"
    assert_contains "$(cat gradle.calls)" "run -PmainClass=com.example.App --args=one two"
    assert_contains "$(cat .jv/state.json)" '"projectShape": "gradle"'
    assert_contains "$(cat .jv/runs.jsonl)" '"event":"executed"'
}

test_gradle_compile_delegates_to_classes() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    : > build.gradle
    cat > gradlew <<'SH'
#!/usr/bin/env bash
echo "$*" >> gradle.calls
SH
    chmod +x gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    "$JV" compile

    assert_contains "$(cat gradle.calls)" "classes"
}
```

Add both tests to `main()`.

- [ ] **Step 2: Route `compile` through planner for Gradle**

At the top of `compile_java`, before `check_java`, add:

```bash
build_plan "$@"
if [[ "$PLAN_SHAPE" == "gradle" ]]; then
    if [[ -z "$PLAN_BUILD_DISPLAY" || -z "$PLAN_GRADLE_COMMAND" ]]; then
        print_plan_summary >&2
        return 1
    fi
    print_plan_summary
    set +e
    "$PLAN_GRADLE_COMMAND" classes
    local gradle_status=$?
    set -e
    return "$gradle_status"
fi
```

- [ ] **Step 3: Route `run` through Gradle execution**

In `run_java`, add a Gradle branch before Maven:

```bash
if [[ "$shape" == "gradle" ]]; then
    set +e
    "$PLAN_GRADLE_COMMAND" classes
    local gradle_status=$?
    set -e
    if [[ $gradle_status -ne 0 ]]; then
        return "$gradle_status"
    fi

    set +e
    if [[ ${#args[@]} -gt 0 ]]; then
        local gradle_args
        gradle_args="$(join_maven_args "${args[@]}")"
        "$PLAN_GRADLE_COMMAND" run "-PmainClass=$class_name" "--args=$gradle_args"
    else
        "$PLAN_GRADLE_COMMAND" run "-PmainClass=$class_name"
    fi
    gradle_status=$?
    set -e
    if [[ $gradle_status -ne 0 ]]; then
        return "$gradle_status"
    fi

    if ! write_success_memory_from_plan; then
        warn "Could not write JV memory to $JV_DIR/"
    fi
    return 0
fi
```

- [ ] **Step 4: Run verification**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: all tests pass, or only `shellcheck` is skipped because it is not installed.

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: delegate Gradle execution"
```

## Task 5: Improve Doctor Output For Gradle

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing doctor tests**

Add:

```bash
test_doctor_reports_gradle_details() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    : > settings.gradle.kts
    cat > build.gradle.kts <<'GRADLE'
plugins {
    application
}
GRADLE
    cat > gradlew <<'SH'
#!/usr/bin/env bash
echo "wrapper $*"
SH
    chmod +x gradlew
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {}
}
JAVA

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "Shape: gradle"
    assert_contains "$output" "Gradle build files: build.gradle.kts"
    assert_contains "$output" "Gradle settings files: settings.gradle.kts"
    assert_contains "$output" "gradle: wrapper ./gradlew (required)"
    assert_contains "$output" "Run: ./gradlew run -PmainClass=com.example.App"
    assert_contains "$output" "application plugin detected in build.gradle.kts"
}
```

Add it to `main()`.

- [ ] **Step 2: Track build and settings files**

Add globals:

```bash
PLAN_GRADLE_BUILD_FILES=()
PLAN_GRADLE_SETTINGS_FILES=()
```

Reset them in `reset_plan`.

Add:

```bash
collect_gradle_files_for_plan() {
    local file
    for file in build.gradle build.gradle.kts; do
        [[ -f "$file" ]] && PLAN_GRADLE_BUILD_FILES+=("$file")
    done
    for file in settings.gradle settings.gradle.kts; do
        [[ -f "$file" ]] && PLAN_GRADLE_SETTINGS_FILES+=("$file")
    done
}
```

Call it in the `gradle)` branch before setting `PLAN_SHAPE_REASON`.

- [ ] **Step 3: Render Gradle doctor details**

In `print_doctor_report`, after source roots:

```bash
if [[ "$PLAN_SHAPE" == "gradle" ]]; then
    echo "  Gradle build files: $(join_csv "${PLAN_GRADLE_BUILD_FILES[@]}")"
    echo "  Gradle settings files: $(join_csv "${PLAN_GRADLE_SETTINGS_FILES[@]}")"
fi
```

When no settings files are present, `join_csv` returns empty; accept that for MVP or print `none` with:

```bash
local settings_display
settings_display="$(join_csv "${PLAN_GRADLE_SETTINGS_FILES[@]}")"
[[ -z "$settings_display" ]] && settings_display="none"
```

- [ ] **Step 4: Run verification**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: all tests pass, or only `shellcheck` is skipped because it is not installed.

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: report Gradle doctor details"
```

## Task 6: Update Help And Optional Docs

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`
- Modify: `README.md` if needed
- Modify: `EXAMPLES.md` if needed

- [ ] **Step 1: Write failing help test**

Extend `test_help_lists_diagnostics_commands`:

```bash
assert_contains "$output" "Gradle projects delegate to ./gradlew or gradle when detected"
```

- [ ] **Step 2: Update help text**

In `show_help`, under project structure or learn-more text, add:

```bash
echo -e "  Gradle projects delegate to ./gradlew or gradle when detected"
```

- [ ] **Step 3: Update docs only if examples changed**

If `README.md` or `EXAMPLES.md` has a supported-project list, add:

```markdown
- Gradle projects: JV delegates to `./gradlew` when present, otherwise `gradle`, and only runs projects with a safe Gradle `run` plan.
```

Do not rewrite unrelated documentation.

- [ ] **Step 4: Run final verification**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected:

```text
All tests passed
```

If `shellcheck` is missing:

```text
shellcheck not installed; skipped shellcheck verification
```

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh README.md EXAMPLES.md
git commit -m "docs: mention Gradle delegation"
```

## Final Review Checklist

- [ ] `jv explain` and `jv run` show the same Gradle plan for the same inputs.
- [ ] Blocked Gradle runs do not invoke Gradle.
- [ ] `jv compile` invokes only `<gradle-command> classes` for Gradle projects.
- [ ] Gradle execution never builds a classpath in JV.
- [ ] Non-executable wrapper blocks even when global `gradle` exists.
- [ ] No implementation files outside `jv.sh`, `tests/run-tests.sh`, and optional docs were changed.
- [ ] The pre-existing untracked `cli/` directory was not touched.
- [ ] Verification commands were run and results recorded in the final implementation response.
