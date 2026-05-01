# Planner Model + Better Doctor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor JV so `run`, `explain`, `doctor`, and `.jv` memory all use one side-effect-free planner model with shared reasons, blockers, warnings, selected commands, and memory status.

**Architecture:** Keep the implementation in the tracked Bash CLI for this milestone. Add a planner layer that writes a normalized model to shell globals and renders it through shared helper functions. Migrate `explain` first, then `doctor`, then `run`, so execution behavior stays stable while the internal model becomes the single source of command decisions.

**Tech Stack:** Bash, shell integration tests in `tests/run-tests.sh`, `javac`/`java`, optional `mvn`, existing `.jv/state.json` and `.jv/runs.jsonl` memory.

---

## Parallelization Strategy

This milestone has one central shared file, `jv.sh`, so most implementation tasks should run sequentially. Parallelization is still useful in two places:

- **Parallel-safe:** Task 1 test helpers, Task 8 documentation updates, and independent review can run in parallel with no conflicts if each worker owns disjoint files.
- **Sequential core:** Tasks 2-7 all modify planner state and command behavior in `jv.sh`; run these one at a time with review gates.
- **Recommended agent split:** one implementer per task, then spec review and code quality review after each task. Do not dispatch multiple workers that edit `jv.sh` concurrently.

## File Structure

- Modify `jv.sh`: add planner-model globals and helpers; migrate `explain`, `doctor`, `run`, and memory writes to the shared model.
- Modify `tests/run-tests.sh`: add planner-model, doctor, stale-memory, blocker, and no-side-effect regression tests.
- Modify `README.md`: update doctor/explain examples if output shape changes.
- Modify `EXAMPLES.md`: add a focused doctor/troubleshooting example if output shape changes.
- Create no new production files in this milestone. The Bash implementation remains the product surface.

## Planner Model Shape

The implementation should keep the first Bash planner model intentionally simple. Use arrays and scalar globals instead of introducing JSON generation inside the planner.

Add these globals near existing configuration/state globals:

```bash
PLAN_SHAPE=""
PLAN_SHAPE_REASON=""
PLAN_SOURCE_ROOT=""
PLAN_SOURCE_ROOT_REASON=""
PLAN_SELECTED_MAIN=""
PLAN_SELECTED_MAIN_SOURCE=""
PLAN_SELECTED_MAIN_REASON=""
PLAN_BUILD_DISPLAY=""
PLAN_RUN_DISPLAY=""
PLAN_BUILD_KIND=""
PLAN_RUN_KIND=""
PLAN_REQUIRED_TOOLS=()
PLAN_MAIN_CANDIDATES=()
PLAN_REASONS=()
PLAN_WARNINGS=()
PLAN_BLOCKERS=()
PLAN_REMEMBERED_MAIN=""
PLAN_MEMORY_STATE=""
PLAN_LAST_SUCCESSFUL_MAIN=""
PLAN_LAST_RUN_SUMMARY=""
PLAN_RUN_ARGS=()
```

The planner must be side-effect free. It can read `.jv/state.json`, source files, and tool availability. It must not compile, run Maven, create `bin/`, or write `.jv/`.

## Task 1: Add Planner Test Helpers

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add reusable assertions**

Add these helpers after existing assertion helpers:

```bash
assert_exists() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        fail "Expected path to exist: $path"
    fi
}

assert_status() {
    local actual="$1"
    local expected="$2"
    if [[ "$actual" -ne "$expected" ]]; then
        fail "Expected status $expected, got $actual"
    fi
}
```

- [ ] **Step 2: Run tests**

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
git commit -m "test: add planner assertion helpers"
```

## Task 2: Introduce Side-Effect-Free Planner Model

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing explain reasons test**

Append before `main()`:

```bash
test_explain_shows_reasons_and_no_side_effects() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("planner");
    }
}
JAVA

    local output
    output="$("$JV" explain)"

    assert_contains "$output" "Reason: src directory found"
    assert_contains "$output" "Reason: exactly one main class detected"
    assert_not_exists "$TMP_ROOT/app/bin"
    assert_not_exists "$TMP_ROOT/app/.jv"
}
```

Add it to `main()` before `test_run_writes_jv_memory`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because current `explain` output does not include the new reason lines.

- [ ] **Step 3: Add planner globals and reset/add helpers**

In `jv.sh`, add the planner globals listed in “Planner Model Shape”.

Add helper functions:

```bash
reset_plan() {
    PLAN_SHAPE=""
    PLAN_SHAPE_REASON=""
    PLAN_SOURCE_ROOT=""
    PLAN_SOURCE_ROOT_REASON=""
    PLAN_SELECTED_MAIN=""
    PLAN_SELECTED_MAIN_SOURCE=""
    PLAN_SELECTED_MAIN_REASON=""
    PLAN_BUILD_DISPLAY=""
    PLAN_RUN_DISPLAY=""
    PLAN_BUILD_KIND=""
    PLAN_RUN_KIND=""
    PLAN_REQUIRED_TOOLS=()
    PLAN_MAIN_CANDIDATES=()
    PLAN_REASONS=()
    PLAN_WARNINGS=()
    PLAN_BLOCKERS=()
    PLAN_REMEMBERED_MAIN=""
    PLAN_MEMORY_STATE="none"
    PLAN_LAST_SUCCESSFUL_MAIN=""
    PLAN_LAST_RUN_SUMMARY=""
    PLAN_RUN_ARGS=()
}

plan_add_reason() {
    PLAN_REASONS+=("$1")
}

plan_add_warning() {
    PLAN_WARNINGS+=("$1")
}

plan_add_blocker() {
    PLAN_BLOCKERS+=("$1")
}
```

- [ ] **Step 4: Add model readers**

Add:

```bash
read_last_successful_main() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"lastSuccessfulMainClass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}

read_last_plan_run() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"run"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}
```

- [ ] **Step 5: Add `build_plan()`**

Add:

```bash
build_plan() {
    local source_root
    local class_name
    local run_args
    local main_class

    reset_plan
    PLAN_SHAPE="$(detect_project_shape)"
    case "$PLAN_SHAPE" in
        maven)
            PLAN_SHAPE_REASON="pom.xml found in project root"
            PLAN_REQUIRED_TOOLS=("java" "mvn")
            ;;
        plain-java)
            PLAN_SHAPE_REASON="$SRC_DIR directory found"
            PLAN_REQUIRED_TOOLS=("java" "javac")
            ;;
        *)
            PLAN_SHAPE_REASON="no recognized Java project markers found"
            plan_add_blocker "No Java project detected. Checked for pom.xml and $SRC_DIR/."
            return 0
            ;;
    esac
    plan_add_reason "$PLAN_SHAPE_REASON"

    source_root="$(source_root_for_shape "$PLAN_SHAPE")"
    PLAN_SOURCE_ROOT="$source_root"
    if [[ -n "$source_root" && -d "$source_root" ]]; then
        PLAN_SOURCE_ROOT_REASON="$source_root exists"
        plan_add_reason "$PLAN_SOURCE_ROOT_REASON"
    else
        PLAN_SOURCE_ROOT_REASON="$source_root missing"
        plan_add_blocker "Source root not found: $source_root"
    fi

    PLAN_REMEMBERED_MAIN="$(remembered_main_class)"
    PLAN_LAST_SUCCESSFUL_MAIN="$(read_last_successful_main)"
    PLAN_LAST_RUN_SUMMARY="$(read_last_plan_run)"
    if [[ -f "$JV_STATE" ]]; then
        PLAN_MEMORY_STATE="present"
    fi

    if [[ -n "$source_root" && -d "$source_root" ]]; then
        while IFS= read -r main_class; do
            [[ -n "$main_class" ]] && PLAN_MAIN_CANDIDATES+=("$main_class")
        done < <(find_main_classes "$source_root")
    fi

    resolve_main_invocation "$source_root" "$@"
    class_name="$RESOLVED_MAIN_CLASS"
    PLAN_RUN_ARGS=("${RESOLVED_ARGS[@]}")
    run_args="$(join_maven_args "${PLAN_RUN_ARGS[@]}")"

    if [[ -n "$class_name" ]]; then
        PLAN_SELECTED_MAIN="$class_name"
        if [[ "$#" -gt 0 && "$1" == "$class_name" ]]; then
            PLAN_SELECTED_MAIN_SOURCE="explicit"
            PLAN_SELECTED_MAIN_REASON="explicit main class argument"
        elif [[ -n "$PLAN_REMEMBERED_MAIN" && "$PLAN_REMEMBERED_MAIN" == "$class_name" ]]; then
            PLAN_SELECTED_MAIN_SOURCE="remembered"
            PLAN_SELECTED_MAIN_REASON="remembered main still exists in source"
        else
            PLAN_SELECTED_MAIN_SOURCE="only-candidate"
            PLAN_SELECTED_MAIN_REASON="exactly one main class detected"
        fi
        plan_add_reason "$PLAN_SELECTED_MAIN_REASON"
    fi

    case "$PLAN_SHAPE" in
        plain-java)
            local classpath
            classpath="$(build_classpath)"
            PLAN_BUILD_KIND="javac"
            PLAN_RUN_KIND="java"
            PLAN_BUILD_DISPLAY="javac -d $BIN_DIR -cp $classpath <sources>"
            PLAN_RUN_DISPLAY="java -cp $classpath $class_name"
            [[ -n "$run_args" ]] && PLAN_RUN_DISPLAY="$PLAN_RUN_DISPLAY $run_args"
            ;;
        maven)
            PLAN_BUILD_KIND="maven"
            PLAN_RUN_KIND="maven"
            PLAN_BUILD_DISPLAY="mvn compile"
            PLAN_RUN_DISPLAY="mvn -q exec:java -Dexec.mainClass=$class_name"
            [[ -n "$run_args" ]] && PLAN_RUN_DISPLAY="$PLAN_RUN_DISPLAY -Dexec.args=\"$run_args\""
            ;;
    esac
}
```

If existing `resolve_main_invocation` exits on ambiguity, leave that behavior for this task. Later tasks will move ambiguity into blockers.

- [ ] **Step 6: Add plan renderer and migrate `explain_project()`**

Add:

```bash
print_plan_summary() {
    case "$PLAN_SHAPE" in
        maven) echo "JV detected: Maven project" ;;
        plain-java) echo "JV detected: plain Java project" ;;
        *) echo "JV detected: unknown project" ;;
    esac
    [[ -n "$PLAN_SOURCE_ROOT" ]] && echo "Source roots: $PLAN_SOURCE_ROOT"
    [[ -n "$PLAN_SELECTED_MAIN" ]] && echo "Main class: $PLAN_SELECTED_MAIN"
    [[ -n "$PLAN_BUILD_DISPLAY" ]] && echo "Build path: $PLAN_BUILD_DISPLAY"
    [[ -n "$PLAN_RUN_DISPLAY" ]] && echo "Run path: $PLAN_RUN_DISPLAY"
    if [[ ${#PLAN_REASONS[@]} -gt 0 ]]; then
        local reason
        for reason in "${PLAN_REASONS[@]}"; do
            echo "Reason: $reason"
        done
    fi
    if [[ ${#PLAN_WARNINGS[@]} -gt 0 ]]; then
        local warning
        for warning in "${PLAN_WARNINGS[@]}"; do
            echo "Warning: $warning"
        done
    fi
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        local blocker
        for blocker in "${PLAN_BLOCKERS[@]}"; do
            echo "Blocker: $blocker"
        done
    fi
}
```

Replace `explain_project()` with:

```bash
explain_project() {
    build_plan "$@"
    print_plan_summary
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        return 1
    fi
}
```

- [ ] **Step 7: Run tests**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: introduce JV planner model"
```

## Task 3: Render Better Doctor From Planner Model

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing doctor detail test**

Append before `main()`:

```bash
test_doctor_reports_plan_reasons_memory_and_blockers() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("doctor plan");
    }
}
JAVA

    "$JV" run >"$TMP_ROOT/doctor-run.out"

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "Selected plan"
    assert_contains "$output" "Main class: Main"
    assert_contains "$output" "Reasons"
    assert_contains "$output" "exactly one main class detected"
    assert_contains "$output" "Memory"
    assert_contains "$output" "Last successful main: Main"
    assert_contains "$output" "Warnings"
    assert_contains "$output" "Blockers"
}
```

Add it to `main()` after `test_doctor_reports_project_state`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because current doctor output does not include these sections.

- [ ] **Step 3: Add `print_doctor_report()`**

Add:

```bash
print_doctor_report() {
    local item

    echo "JV doctor"
    echo ""
    echo "Project"
    echo "  Shape: $PLAN_SHAPE"
    echo "  Shape reason: $PLAN_SHAPE_REASON"
    if [[ -n "$PLAN_SOURCE_ROOT" ]]; then
        echo "  Source roots: $PLAN_SOURCE_ROOT"
    else
        echo "  Source roots: none detected"
    fi
    echo "  Tools:"
    for item in java javac mvn; do
        if command -v "$item" >/dev/null 2>&1; then
            echo "    $item: $(command -v "$item")"
        else
            echo "    $item: missing"
        fi
    done

    echo ""
    echo "Selected plan"
    if [[ -n "$PLAN_SELECTED_MAIN" ]]; then
        echo "  Main class: $PLAN_SELECTED_MAIN"
        echo "  Main source: $PLAN_SELECTED_MAIN_SOURCE"
    else
        echo "  Main class: none"
    fi
    [[ -n "$PLAN_BUILD_DISPLAY" ]] && echo "  Build: $PLAN_BUILD_DISPLAY"
    [[ -n "$PLAN_RUN_DISPLAY" ]] && echo "  Run: $PLAN_RUN_DISPLAY"

    echo ""
    echo "Main class candidates:"
    if [[ ${#PLAN_MAIN_CANDIDATES[@]} -eq 0 ]]; then
        echo "  none"
    else
        for item in "${PLAN_MAIN_CANDIDATES[@]}"; do
            echo "  $item"
        done
    fi

    echo ""
    echo "Reasons"
    if [[ ${#PLAN_REASONS[@]} -eq 0 ]]; then
        echo "  none"
    else
        for item in "${PLAN_REASONS[@]}"; do
            echo "  - $item"
        done
    fi

    echo ""
    echo "Memory"
    echo "  State: $PLAN_MEMORY_STATE"
    if [[ -n "$PLAN_REMEMBERED_MAIN" ]]; then
        echo "  Remembered main: $PLAN_REMEMBERED_MAIN"
    else
        echo "  Remembered main: none"
    fi
    if [[ -n "$PLAN_LAST_SUCCESSFUL_MAIN" ]]; then
        echo "  Last successful main: $PLAN_LAST_SUCCESSFUL_MAIN"
    else
        echo "  Last successful main: none"
    fi
    if [[ -n "$PLAN_LAST_RUN_SUMMARY" ]]; then
        echo "  Last run: $PLAN_LAST_RUN_SUMMARY"
    else
        echo "  Last run: none"
    fi

    echo ""
    echo "Warnings"
    if [[ ${#PLAN_WARNINGS[@]} -eq 0 ]]; then
        echo "  none"
    else
        for item in "${PLAN_WARNINGS[@]}"; do
            echo "  - $item"
        done
    fi

    echo ""
    echo "Blockers"
    if [[ ${#PLAN_BLOCKERS[@]} -eq 0 ]]; then
        echo "  none"
    else
        for item in "${PLAN_BLOCKERS[@]}"; do
            echo "  - $item"
        done
    fi
}
```

- [ ] **Step 4: Migrate `doctor_project()`**

Replace `doctor_project()` with:

```bash
doctor_project() {
    build_plan
    print_doctor_report
}
```

`doctor` should return 0 even when the project has blockers, because it successfully diagnosed the project.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

Commit:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: render doctor from planner model"
```

## Task 4: Convert Ambiguity And Missing State Into Planner Blockers

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add failing doctor blocker tests**

Append before `main()`:

```bash
test_doctor_reports_ambiguous_main_as_blocker() {
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

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "Blockers"
    assert_contains "$output" "Multiple main classes found"
    assert_contains "$output" "App"
    assert_contains "$output" "Tool"
}

test_doctor_reports_unknown_project_as_blocker() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "Project"
    assert_contains "$output" "Shape: unknown"
    assert_contains "$output" "Blockers"
    assert_contains "$output" "No Java project detected"
}
```

Add both to `main()` near other doctor tests.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `build_plan` still exits through `select_main_class` for ambiguity/missing main.

- [ ] **Step 3: Add non-exiting main selection helper**

Add:

```bash
plan_select_main_class() {
    local requested="$1"
    local source_root="$2"
    local main_class

    if [[ -n "$requested" ]]; then
        for main_class in "${PLAN_MAIN_CANDIDATES[@]}"; do
            if [[ "$main_class" == "$requested" ]]; then
                PLAN_SELECTED_MAIN="$requested"
                PLAN_SELECTED_MAIN_SOURCE="explicit"
                PLAN_SELECTED_MAIN_REASON="explicit main class argument"
                plan_add_reason "$PLAN_SELECTED_MAIN_REASON"
                return 0
            fi
        done
        plan_add_blocker "Requested main class not found in source: $requested"
        return 0
    fi

    if [[ -n "$PLAN_REMEMBERED_MAIN" ]]; then
        for main_class in "${PLAN_MAIN_CANDIDATES[@]}"; do
            if [[ "$main_class" == "$PLAN_REMEMBERED_MAIN" ]]; then
                PLAN_SELECTED_MAIN="$PLAN_REMEMBERED_MAIN"
                PLAN_SELECTED_MAIN_SOURCE="remembered"
                PLAN_SELECTED_MAIN_REASON="remembered main still exists in source"
                plan_add_reason "$PLAN_SELECTED_MAIN_REASON"
                return 0
            fi
        done
        plan_add_blocker "Remembered main class in $JV_STATE is stale: $PLAN_REMEMBERED_MAIN"
        return 0
    fi

    case "${#PLAN_MAIN_CANDIDATES[@]}" in
        0)
            plan_add_blocker "No main class found in $source_root. Pass one explicitly: jv run <MainClass>"
            ;;
        1)
            PLAN_SELECTED_MAIN="${PLAN_MAIN_CANDIDATES[0]}"
            PLAN_SELECTED_MAIN_SOURCE="only-candidate"
            PLAN_SELECTED_MAIN_REASON="exactly one main class detected"
            plan_add_reason "$PLAN_SELECTED_MAIN_REASON"
            ;;
        *)
            plan_add_blocker "Multiple main classes found. Pass one explicitly: jv run <MainClass>"
            ;;
    esac
}
```

- [ ] **Step 4: Update `build_plan()` to use blocker selection**

Replace the `resolve_main_invocation` call inside `build_plan()` with logic that preserves the existing inferred-args heuristic while using `plan_select_main_class`.

Implementation guidance:

```bash
local requested_main=""
local first_token="${1:-}"
local remaining_args=()

if [[ "$#" -gt 0 ]]; then
    shift
    remaining_args=("$@")
    for main_class in "${PLAN_MAIN_CANDIDATES[@]}"; do
        if [[ "$first_token" == "$main_class" ]]; then
            requested_main="$first_token"
            PLAN_RUN_ARGS=("${remaining_args[@]}")
            break
        fi
    done
    if [[ -z "$requested_main" ]]; then
        if [[ ${#PLAN_MAIN_CANDIDATES[@]} -eq 1 ]]; then
            PLAN_RUN_ARGS=("$first_token" "${remaining_args[@]}")
        else
            PLAN_RUN_ARGS=("$first_token" "${remaining_args[@]}")
        fi
    fi
fi

plan_select_main_class "$requested_main" "$source_root"
```

Only populate build/run commands when `PLAN_SELECTED_MAIN` is non-empty.

- [ ] **Step 5: Update `run_java()` to use planner blockers**

At the start of `run_java()`:

```bash
build_plan "$@"
if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
    print_plan_summary >&2
    return 1
fi
```

Then use `PLAN_SHAPE`, `PLAN_SOURCE_ROOT`, `PLAN_SELECTED_MAIN`, and `PLAN_RUN_ARGS` for execution.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

Commit:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: report planner blockers without exiting"
```

## Task 5: Execute From Planner Model

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add plan consistency test**

Append before `main()`:

```bash
test_run_and_explain_share_plain_plan_output() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("same plan");
    }
}
JAVA

    local explain_output
    local run_output
    explain_output="$("$JV" explain one two)"
    run_output="$("$JV" run one two)"

    assert_contains "$explain_output" "Run path: java -cp bin Main one two"
    assert_contains "$run_output" "Run path: java -cp bin Main one two"
    assert_contains "$run_output" "same plan"
}
```

Add to `main()`.

- [ ] **Step 2: Run test**

Run:

```bash
tests/run-tests.sh
```

Expected: should pass if Task 4 already migrated run; if it fails, complete migration below.

- [ ] **Step 3: Add safe memory helper**

Add:

```bash
write_success_memory_from_plan() {
    if [[ -z "$PLAN_SELECTED_MAIN" || -z "$PLAN_BUILD_DISPLAY" || -z "$PLAN_RUN_DISPLAY" ]]; then
        return 1
    fi
    write_state "$PLAN_SHAPE" "$PLAN_SELECTED_MAIN" "$PLAN_BUILD_DISPLAY" "$PLAN_RUN_DISPLAY"
    append_run_event "executed" "$PLAN_RUN_DISPLAY"
}
```

- [ ] **Step 4: Replace manual memory strings**

In Maven and plain Java execution branches, replace locally rebuilt `build_command` and `run_command` strings with:

```bash
if ! write_success_memory_from_plan; then
    warn "Could not write JV memory to $JV_DIR/"
fi
```

- [ ] **Step 5: Remove duplicated plan rendering from run**

Ensure `run_java()` calls:

```bash
print_plan_summary
echo ""
```

and no longer calls `print_plain_java_plan` or `print_maven_plan` directly.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

Commit:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: execute from planner model"
```

## Task 6: Add Tool Versions And Required Tool Blockers

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add doctor tool version test**

Append before `main()`:

```bash
test_doctor_reports_tool_versions() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("versions");
    }
}
JAVA

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "java:"
    assert_contains "$output" "javac:"
    assert_contains "$output" "required"
}
```

Add to `main()`.

- [ ] **Step 2: Add tool helpers**

Add:

```bash
tool_version() {
    local tool="$1"
    case "$tool" in
        java|javac) "$tool" -version 2>&1 | head -n 1 ;;
        mvn) mvn -version 2>/dev/null | head -n 1 ;;
        *) echo "" ;;
    esac
}

tool_is_required() {
    local tool="$1"
    local required
    for required in "${PLAN_REQUIRED_TOOLS[@]}"; do
        [[ "$required" == "$tool" ]] && return 0
    done
    return 1
}
```

- [ ] **Step 3: Add missing required tool blockers**

In `build_plan()`, after setting required tools:

```bash
local tool
for tool in "${PLAN_REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        plan_add_blocker "Required tool missing: $tool"
    fi
done
```

- [ ] **Step 4: Update doctor tool rendering**

In `print_doctor_report()`, render:

```text
java: /path (required) - version line
javac: /path (required) - version line
mvn: missing (optional)
```

Use `tool_is_required` and `tool_version`.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

Commit:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: show planner tool requirements"
```

## Task 7: Persist Planner Snapshot In State

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add state snapshot test**

Append before `main()`:

```bash
test_run_state_contains_planner_reasons() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("state reasons");
    }
}
JAVA

    "$JV" run >"$TMP_ROOT/state-reasons.out"

    local state
    state="$(cat "$TMP_ROOT/app/.jv/state.json")"
    assert_contains "$state" '"planner":'
    assert_contains "$state" '"selectedMainSource": "only-candidate"'
    assert_contains "$state" '"reasons":'
    assert_contains "$state" 'exactly one main class detected'
}
```

Add to `main()`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because current state lacks `planner`.

- [ ] **Step 3: Add JSON array writer helper**

Add:

```bash
json_array_from_lines() {
    local item
    local first=1
    printf '['
    for item in "$@"; do
        if [[ $first -eq 0 ]]; then
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$item")"
        first=0
    done
    printf ']'
}
```

- [ ] **Step 4: Extend `write_state()`**

Add a `planner` object while preserving existing fields:

```json
"planner": {
  "shapeReason": "...",
  "sourceRoot": "...",
  "selectedMainSource": "...",
  "reasons": [...],
  "warnings": [...],
  "blockers": []
}
```

Use current planner globals inside `write_state()`. Since `write_state()` is called after successful runs, blockers should be empty in normal successful state.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh
shellcheck jv.sh tests/run-tests.sh
```

Expected: all pass.

Commit:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: persist planner snapshot in JV state"
```

## Task 8: Update Docs For Planner Doctor

**Files:**
- Modify: `README.md`
- Modify: `EXAMPLES.md`

- [ ] **Step 1: Update README doctor section**

Add or update a short doctor section:

```markdown
### Inspect The Plan

`jv doctor` shows the same planner model that powers `jv run` and `jv explain`: project shape, source roots, tool availability, selected main class, reasons, warnings, blockers, and `.jv/` memory status.
```

- [ ] **Step 2: Update EXAMPLES troubleshooting section**

Add:

````markdown
## Diagnose A Project

```bash
jv doctor
```

Use `jv doctor` when JV surprises you. It prints what JV detected, why it selected a main class, which command it would run, and what blocks execution.
````

- [ ] **Step 3: Run docs-free validation**

Run:

```bash
tests/run-tests.sh
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add README.md EXAMPLES.md
git commit -m "docs: document planner doctor output"
```

## Task 9: Final Verification

**Files:**
- No changes expected unless verification finds a bug.

- [ ] **Step 1: Run CLI tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 2: Run shell validation**

Run:

```bash
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

Expected: no output and exit 0.

- [ ] **Step 3: Run docs validation**

Run:

```bash
cd docs && pnpm lint && pnpm build
```

Expected: lint and build pass. The existing Next `metadataBase` warning may still appear during build.

- [ ] **Step 4: Check worktree**

Run:

```bash
git status --short --branch
```

Expected: only the pre-existing untracked `cli/` directory, or a clean tree if that has been handled separately.

- [ ] **Step 5: Commit verification fixes if needed**

If a bug is found, fix only the affected files and commit. For example, if the fix touches the planner and tests:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "fix: stabilize planner model verification"
```

Do not create an empty commit.

## Self-Review

- Spec coverage: The plan covers one shared planner model, `run`/`explain`/`doctor` model reuse, reasons, blockers, warnings, memory state, selected main source, tool requirements, planner persistence, docs, and final verification.
- Scope: The plan intentionally does not add Gradle, IDE metadata hints, new `.jv` event schemas, or packaging changes.
- Parallelization: The central `jv.sh` tasks are sequenced to avoid conflicts. Documentation updates and review can run in parallel with no shared write set.
- Completeness scan: No task depends on unspecified file names or undefined follow-up work.
