# Agent-Friendly Failure UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stable, agent-friendly failure and warning blocks to `jv run`, with matching `.jv/runs.jsonl` events for planner blockers, compile failures, Maven failures, Java runtime failures, and memory-write warnings.

**Architecture:** Keep the MVP in the existing Bash CLI. Add a small failure-rendering layer around the current planner and executor paths, map existing blocker messages to a small stable reason-code set, and append structured run-history events when memory is writable. Preserve raw `javac`, Maven, and Java output; JV adds an actionable wrapper after the underlying tool output.

**Tech Stack:** Bash, shell integration tests in `tests/run-tests.sh`, `javac`/`java`, optional `mvn`, existing `.jv/state.json` and `.jv/runs.jsonl` generated memory.

---

## File Structure

- Modify `jv.sh`: add reason-code helpers, retry-command rendering, stable `JV failure` / `JV warning` renderers, blocked/failed/warning event writers, and calls from `run_java()` / `compile_java()`.
- Modify `tests/run-tests.sh`: add integration tests for planner blockers, plain Java compile failures, Maven compile/run failures, Java runtime failures, and memory-write warnings.
- Modify `README.md`: document the stable failure block and `.jv/runs.jsonl` failure events.

No new production files are required for this slice.

## Dependency Note

Preferred implementation order is Agent-Grade JV Events first, then this failure UX slice. When the event writer from `docs/superpowers/plans/2026-05-01-agent-grade-events.md` exists, use that writer for blocked, failed, and warning records instead of adding a parallel ad hoc event writer. If this plan is implemented first, keep the event helper small and compatible so the later event-envelope work can replace it without changing the stable `JV failure` / `JV warning` text contract.

## Stable Output Contract

Failure block:

```text
JV failure
Reason: <reason_code>
Action: <planner|compile|maven|runtime>
Message: <one-line summary>
Next action: <one concrete next step>
Retry command: <jv run command or unavailable>
Exit code: <status>
```

Warning block:

```text
JV warning
Reason: memory_write_failed
Message: Could not write JV memory to .jv/.
Next action: Check that .jv/ is a writable directory.
```

Reason codes for this slice:

- `project_unknown`
- `source_root_missing`
- `main_missing`
- `main_ambiguous`
- `explicit_main_missing`
- `remembered_main_stale`
- `tool_missing`
- `compile_failed`
- `maven_compile_failed`
- `maven_run_failed`
- `runtime_failed`
- `memory_write_failed`

## Task 1: Add Stable Failure Test Helpers

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failure assertions**

Add these helpers after `assert_status()`:

```bash
assert_failure_block() {
    local output="$1"
    local reason="$2"
    local action="$3"
    local retry="$4"

    assert_contains "$output" "JV failure"
    assert_contains "$output" "Reason: $reason"
    assert_contains "$output" "Action: $action"
    assert_contains "$output" "Next action:"
    assert_contains "$output" "Retry command: $retry"
    assert_contains "$output" "Exit code:"
}

assert_warning_block() {
    local output="$1"
    local reason="$2"

    assert_contains "$output" "JV warning"
    assert_contains "$output" "Reason: $reason"
    assert_contains "$output" "Message:"
    assert_contains "$output" "Next action:"
}
```

- [ ] **Step 2: Run the existing test suite**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add failure ux assertions"
```

## Task 2: Add Planner Blocker Failure UX

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing planner blocker test**

Add this test before `test_explain_shows_reasons_and_no_side_effects()`:

```bash
test_run_prints_agent_failure_for_ambiguous_main() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/App.java <<'JAVA'
public class App {
    public static void main(String[] args) {
        System.out.println("app");
    }
}
JAVA
    cat > src/Tool.java <<'JAVA'
public class Tool {
    public static void main(String[] args) {
        System.out.println("tool");
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    assert_status "$status" 1
    assert_failure_block "$output" "main_ambiguous" "planner" "jv run App"
    assert_contains "$output" "Message: Multiple main classes were found."
    assert_contains "$output" "Next action: Pass one main class explicitly, for example \`jv run App\`."
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"blocked"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"main_ambiguous"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"retryCommand":"jv run App"'
}
```

Add it to `main()` after `test_run_refuses_multiple_plain_main_classes`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because blocked `jv run` prints `Blocker:` lines but no `JV failure` block or blocked event.

- [ ] **Step 3: Add failure helpers**

In `jv.sh`, add these helpers after `plan_add_blocker()`:

```bash
command_display_from_args() {
    local display="jv run"
    local arg

    for arg in "$@"; do
        display="$display $arg"
    done

    printf '%s' "$display"
}

first_main_candidate() {
    if [[ ${#PLAN_MAIN_CANDIDATES[@]} -gt 0 ]]; then
        printf '%s' "${PLAN_MAIN_CANDIDATES[0]}"
    fi
}

retry_command_for_current_run() {
    local fallback_main

    if [[ "$#" -gt 0 ]]; then
        command_display_from_args "$@"
        return 0
    fi

    fallback_main="$(first_main_candidate)"
    if [[ -n "$fallback_main" && "${#PLAN_MAIN_CANDIDATES[@]}" -gt 1 ]]; then
        command_display_from_args "$fallback_main"
        return 0
    fi

    command_display_from_args
}

failure_reason_for_blocker() {
    local blocker="$1"

    case "$blocker" in
        "No Java project detected."*) echo "project_unknown" ;;
        "Source root not found:"*) echo "source_root_missing" ;;
        "No main class found"*) echo "main_missing" ;;
        "Multiple main classes found:"*) echo "main_ambiguous" ;;
        "Requested main class not found"*) echo "explicit_main_missing" ;;
        "Remembered main class"*"stale:"*) echo "remembered_main_stale" ;;
        "Required tool missing:"*) echo "tool_missing" ;;
        *) echo "project_unknown" ;;
    esac
}

failure_message_for_reason() {
    local reason="$1"

    case "$reason" in
        project_unknown) echo "No supported Java project was detected." ;;
        source_root_missing) echo "The expected source root was not found." ;;
        main_missing) echo "No Java main method was detected." ;;
        main_ambiguous) echo "Multiple main classes were found." ;;
        explicit_main_missing) echo "The requested main class was not found in source." ;;
        remembered_main_stale) echo "The remembered main class is no longer present in source." ;;
        tool_missing) echo "A required local tool is missing." ;;
        compile_failed) echo "javac failed while compiling the selected plain Java project." ;;
        maven_compile_failed) echo "Maven failed during \`mvn compile\`." ;;
        maven_run_failed) echo "Maven failed while running $PLAN_SELECTED_MAIN." ;;
        runtime_failed) echo "Java exited with a non-zero status while running $PLAN_SELECTED_MAIN." ;;
        memory_write_failed) echo "Could not write JV memory to $JV_DIR/." ;;
        *) echo "JV could not complete the requested action." ;;
    esac
}

next_action_for_reason() {
    local reason="$1"
    local retry="$2"

    case "$reason" in
        project_unknown) echo "Run from a directory with pom.xml or src/." ;;
        source_root_missing) echo "Create the expected source root or run JV from the project root." ;;
        main_missing) echo "Add a public static void main(String[] args) method, then retry." ;;
        main_ambiguous) echo "Pass one main class explicitly, for example \`$retry\`." ;;
        explicit_main_missing) echo "Use one of the detected main classes or update the source file." ;;
        remembered_main_stale) echo "Run \`jv forget main\` or remember a main class that still exists." ;;
        tool_missing) echo "Install the missing required tool, then retry." ;;
        compile_failed) echo "Fix the compiler errors above, then retry the same JV command." ;;
        maven_compile_failed) echo "Fix the Maven compilation errors above, then retry the same JV command." ;;
        maven_run_failed) echo "Inspect the Maven exec output above, then retry the same JV command." ;;
        runtime_failed) echo "Fix the runtime error above, then retry the same JV command." ;;
        memory_write_failed) echo "Check that $JV_DIR/ is a writable directory." ;;
        *) echo "Inspect the output above, then retry." ;;
    esac
}

print_failure_block() {
    local reason="$1"
    local action="$2"
    local retry="$3"
    local exit_code="$4"
    local message
    local next_action

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "$retry")"

    echo ""
    echo "JV failure"
    echo "Reason: $reason"
    echo "Action: $action"
    echo "Message: $message"
    echo "Next action: $next_action"
    echo "Retry command: $retry"
    echo "Exit code: $exit_code"
}

print_warning_block() {
    local reason="$1"
    local message
    local next_action

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "jv run")"

    echo ""
    echo "JV warning"
    echo "Reason: $reason"
    echo "Message: $message"
    echo "Next action: $next_action"
}
```

- [ ] **Step 4: Add event writers**

Add these helpers after `append_run_event()`:

```bash
append_structured_event() {
    local event="$1"
    local action="$2"
    local reason="$3"
    local command="$4"
    local message="$5"
    local next_action="$6"
    local retry="$7"
    local exit_code="${8:-}"

    ensure_jv_dir || return
    if [[ -n "$exit_code" ]]; then
        printf '{"event":"%s","action":"%s","reason":"%s","command":"%s","message":"%s","nextAction":"%s","retryCommand":"%s","exitCode":%s}\n' \
            "$(json_escape "$event")" "$(json_escape "$action")" "$(json_escape "$reason")" "$(json_escape "$command")" \
            "$(json_escape "$message")" "$(json_escape "$next_action")" "$(json_escape "$retry")" "$exit_code" >> "$JV_RUNS"
    else
        printf '{"event":"%s","action":"%s","reason":"%s","command":"%s","message":"%s","nextAction":"%s","retryCommand":"%s"}\n' \
            "$(json_escape "$event")" "$(json_escape "$action")" "$(json_escape "$reason")" "$(json_escape "$command")" \
            "$(json_escape "$message")" "$(json_escape "$next_action")" "$(json_escape "$retry")" >> "$JV_RUNS"
    fi
}

append_failure_event() {
    local event="$1"
    local action="$2"
    local reason="$3"
    local command="$4"
    local retry="$5"
    local exit_code="$6"
    local message
    local next_action

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "$retry")"
    append_structured_event "$event" "$action" "$reason" "$command" "$message" "$next_action" "$retry" "$exit_code"
}

append_warning_event() {
    local reason="$1"
    local retry="$2"
    local message
    local next_action

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "$retry")"
    append_structured_event "warning" "memory" "$reason" "" "$message" "$next_action" "$retry"
}
```

- [ ] **Step 5: Render blocked run failures**

In `run_java()`, replace the blocker branch:

```bash
if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
    print_plan_summary >&2
    return 1
fi
```

with:

```bash
if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
    local blocker="${PLAN_BLOCKERS[0]}"
    local reason
    local retry

    reason="$(failure_reason_for_blocker "$blocker")"
    retry="$(retry_command_for_current_run "$@")"
    print_plan_summary >&2
    print_failure_block "$reason" "planner" "$retry" 1 >&2
    append_failure_event "blocked" "run" "$reason" "$retry" "$retry" 1 || true
    return 1
fi
```

- [ ] **Step 6: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 7: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add planner failure blocks"
```

## Task 3: Add Plain Java Compile Failure UX

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing compile failure test**

Add this test before `test_run_failure_does_not_write_success_memory()`:

```bash
test_run_prints_agent_failure_for_plain_compile_error() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println(message);
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected compile failure"
    fi
    assert_contains "$output" "cannot find symbol"
    assert_failure_block "$output" "compile_failed" "compile" "jv run"
    assert_contains "$output" "Message: javac failed while compiling the selected plain Java project."
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"failed"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"compile_failed"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}
```

Add it to `main()` before `test_run_failure_does_not_write_success_memory`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `javac` output is visible but no `compile_failed` block or event is written.

- [ ] **Step 3: Add compile command status helper**

Replace `compile_java()` with:

```bash
compile_java() {
    check_java

    if [[ ! -d "$SRC_DIR" ]]; then
        error "Source directory '$SRC_DIR' not found. Run 'jv init' first."
    fi

    local java_files=()
    while IFS= read -r -d '' file; do
        java_files+=("$file")
    done < <(find "$SRC_DIR" -name "*.java" -print0 2>/dev/null)

    if [[ ${#java_files[@]} -eq 0 ]]; then
        error "No .java files found in $SRC_DIR"
    fi

    info "Compiling ${#java_files[@]} Java file(s)..."
    mkdir -p "$BIN_DIR"

    local classpath
    classpath=$(build_classpath)

    javac -d "$BIN_DIR" -cp "$classpath" "${java_files[@]}"
}
```

This keeps raw `javac` output visible and lets callers decide whether to render a JV failure block.

- [ ] **Step 4: Wrap compile calls in `run_java()`**

In `run_java()`, replace both direct `compile_java` calls with this pattern:

```bash
set +e
compile_java
local compile_status=$?
set -e
if [[ $compile_status -ne 0 ]]; then
    local retry
    retry="$(retry_command_for_current_run "$@")"
    print_failure_block "compile_failed" "compile" "$retry" "$compile_status" >&2
    append_failure_event "failed" "compile" "compile_failed" "$PLAN_BUILD_DISPLAY" "$retry" "$compile_status" || true
    return "$compile_status"
fi
```

Apply the same replacement in the branch for missing `bin/` and the branch for missing selected class file.

- [ ] **Step 5: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add compile failure blocks"
```

## Task 4: Add Maven Failure UX

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing Maven compile failure test**

Add this test near `test_maven_explain_and_run()`:

```bash
test_run_prints_agent_failure_for_maven_compile_error() {
    if ! command -v mvn >/dev/null 2>&1; then
        echo "Skipping Maven failure test; mvn not installed"
        return 0
    fi

    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    cat > pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>1.0.0</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
XML
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println(message);
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected Maven compile failure"
    fi
    assert_failure_block "$output" "maven_compile_failed" "maven" "jv run"
    assert_contains "$output" "Message: Maven failed during \`mvn compile\`."
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"maven_compile_failed"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}
```

Add it to `main()` after `test_maven_explain_and_run`.

- [ ] **Step 2: Add failing Maven run failure test**

Add this test after the Maven compile failure test:

```bash
test_run_prints_agent_failure_for_maven_runtime_error() {
    if ! command -v mvn >/dev/null 2>&1; then
        echo "Skipping Maven runtime failure test; mvn not installed"
        return 0
    fi

    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/main/java/com/example"
    cd "$TMP_ROOT/app"
    cat > pom.xml <<'XML'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>1.0.0</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
XML
    cat > src/main/java/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        throw new IllegalStateException("maven runtime failure");
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run com.example.App demo 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected Maven runtime failure"
    fi
    assert_contains "$output" "maven runtime failure"
    assert_failure_block "$output" "maven_run_failed" "maven" "jv run com.example.App demo"
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"maven_run_failed"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}
```

Add it to `main()` after `test_run_prints_agent_failure_for_maven_compile_error`.

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because Maven failures return the Maven exit status without a JV failure block or failed event.

- [ ] **Step 4: Wrap Maven compile and run failures**

In the Maven branch of `run_java()`, replace:

```bash
if [[ $maven_status -ne 0 ]]; then
    return "$maven_status"
fi
```

after `mvn compile` with:

```bash
if [[ $maven_status -ne 0 ]]; then
    local retry
    retry="$(retry_command_for_current_run "$@")"
    print_failure_block "maven_compile_failed" "maven" "$retry" "$maven_status" >&2
    append_failure_event "failed" "maven" "maven_compile_failed" "$PLAN_BUILD_DISPLAY" "$retry" "$maven_status" || true
    return "$maven_status"
fi
```

Replace the same status check after `mvn -q exec:java ...` with:

```bash
if [[ $maven_status -ne 0 ]]; then
    local retry
    retry="$(retry_command_for_current_run "$@")"
    print_failure_block "maven_run_failed" "maven" "$retry" "$maven_status" >&2
    append_failure_event "failed" "maven" "maven_run_failed" "$PLAN_RUN_DISPLAY" "$retry" "$maven_status" || true
    return "$maven_status"
fi
```

- [ ] **Step 5: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add maven failure blocks"
```

## Task 5: Add Java Runtime Failure UX

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Update runtime failure test**

Replace `test_run_failure_does_not_write_success_memory()` with:

```bash
test_run_failure_does_not_write_success_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("failing main");
        System.exit(7);
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run Main alpha 2>&1)"
    local status=$?
    set -e

    assert_status "$status" 7
    assert_contains "$output" "failing main"
    assert_failure_block "$output" "runtime_failed" "runtime" "jv run Main alpha"
    assert_contains "$output" "Message: Java exited with a non-zero status while running Main."
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"failed"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"runtime_failed"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because Java runtime failures do not yet print `runtime_failed` or append a failed event.

- [ ] **Step 3: Wrap Java process failure**

In `run_java()`, replace:

```bash
if [[ $java_status -eq 0 ]]; then
    if ! write_success_memory_from_plan; then
        warn "Could not write JV memory to $JV_DIR/"
    fi
fi

return "$java_status"
```

with:

```bash
if [[ $java_status -eq 0 ]]; then
    if ! write_success_memory_from_plan; then
        print_warning_block "memory_write_failed" >&2
        append_warning_event "memory_write_failed" "$(retry_command_for_current_run "$@")" || true
    fi
    return 0
fi

local retry
retry="$(retry_command_for_current_run "$@")"
print_failure_block "runtime_failed" "runtime" "$retry" "$java_status" >&2
append_failure_event "failed" "runtime" "runtime_failed" "$PLAN_RUN_DISPLAY" "$retry" "$java_status" || true
return "$java_status"
```

- [ ] **Step 4: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add runtime failure blocks"
```

## Task 6: Add Memory-Write Warning UX

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Update existing memory warning tests**

In `test_run_memory_write_failure_preserves_success_exit()`, replace:

```bash
assert_contains "$output" "Warning:"
```

with:

```bash
assert_warning_block "$output" "memory_write_failed"
assert_contains "$output" "Message: Could not write JV memory to .jv/."
assert_contains "$output" "Next action: Check that .jv/ is a writable directory."
```

In `test_run_state_write_failure_warns_even_when_run_log_can_append()`, replace:

```bash
assert_contains "$output" "Warning: Could not write JV memory"
```

with:

```bash
assert_warning_block "$output" "memory_write_failed"
assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"warning"'
assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"memory_write_failed"'
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL if any memory-write path still uses the old `Warning:` line.

- [ ] **Step 3: Replace remaining memory warning calls**

In the Maven success branch of `run_java()`, replace:

```bash
if ! write_success_memory_from_plan; then
    warn "Could not write JV memory to $JV_DIR/"
fi
```

with:

```bash
if ! write_success_memory_from_plan; then
    print_warning_block "memory_write_failed" >&2
    append_warning_event "memory_write_failed" "$(retry_command_for_current_run "$@")" || true
fi
```

The plain Java success branch was updated in Task 5; verify there are no remaining `warn "Could not write JV memory` calls:

```bash
rg 'Could not write JV memory|warn "Could not write' jv.sh
```

Expected: no output.

- [ ] **Step 4: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 5: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add memory warning blocks"
```

## Task 7: Document Failure UX

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add README section**

Add this section after `Generated JV Memory`:

````markdown
### Agent-Friendly Failures

When `jv run` is blocked or a build/run step fails, JV keeps the original tool output visible and adds a stable failure block:

```text
JV failure
Reason: compile_failed
Action: compile
Message: javac failed while compiling the selected plain Java project.
Next action: Fix the compiler errors above, then retry the same JV command.
Retry command: jv run
Exit code: 1
```

Agents can use the stable `Reason`, `Next action`, and `Retry command` lines for repair loops. JV also records blocked and failed run attempts in `.jv/runs.jsonl` when the memory directory is writable.
````

- [ ] **Step 2: Run docs grep**

Run:

```bash
rg -n "Agent-Friendly Failures|Reason: compile_failed|runs.jsonl" README.md
```

Expected output includes:

```text
README.md:...:### Agent-Friendly Failures
README.md:...:Reason: compile_failed
README.md:...:.jv/runs.jsonl
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document agent-friendly failures"
```

## Task 8: Final Verification

**Files:**
- Verify only.

- [ ] **Step 1: Run shell tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 2: Run Bash syntax checks**

Run:

```bash
bash -n jv.sh tests/run-tests.sh install.sh
```

Expected: no output and exit `0`.

- [ ] **Step 3: Run shellcheck**

Run:

```bash
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: no output and exit `0`.

If `shellcheck` is not installed, install it before landing this slice or record the missing local tool in the handoff. Do not skip this verification silently.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD
git diff -- jv.sh tests/run-tests.sh README.md
```

Expected: only `jv.sh`, `tests/run-tests.sh`, and `README.md` have implementation-slice changes.

- [ ] **Step 5: Final commit if needed**

If verification requires small fixes, commit them:

```bash
git add jv.sh tests/run-tests.sh README.md
git commit -m "fix: stabilize failure ux verification"
```

## Self-Review

- Spec coverage: The plan covers planner blockers, plain Java compile failures, Maven compile failures, Maven run failures, Java runtime failures, memory-write warnings, stable text sections, retry commands, next actions, small reason codes, and `.jv/runs.jsonl` events.
- Placeholder scan: No steps rely on vague future-work markers or unspecified tests. Every task includes exact files, code snippets, commands, and expected outcomes.
- Type and naming consistency: Bash helper names are consistent across tasks: `retry_command_for_current_run`, `failure_reason_for_blocker`, `print_failure_block`, `print_warning_block`, `append_failure_event`, and `append_warning_event`.
