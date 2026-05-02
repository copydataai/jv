# Agent-Grade JV Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JV's simple run-history append with stable agent-grade `.jv/runs.jsonl` events for environment summaries, plans, blockers, execution starts/results, and memory writes.

**Architecture:** Keep the event system inside `jv.sh` as small Bash helpers layered around the existing planner globals and execution paths. Emit append-only JSON Lines with a shared envelope and compact payloads; never read runs history for planning. Extend `tests/run-tests.sh` with shell integration tests that parse lines with `jq` when available and fall back to string checks otherwise.

**Tech Stack:** Bash, existing `jv.sh` planner globals, `.jv/state.json`, `.jv/runs.jsonl`, shell integration tests in `tests/run-tests.sh`, optional `jq` for validation in tests only, `shellcheck`.

---

## File Structure

- Modify `jv.sh`: add event run context globals, JSON object helpers, event append helpers, event payload writers, and calls from `run`, `doctor`, `remember`, and `forget`.
- Modify `tests/run-tests.sh`: add focused integration tests for event schema, blockers, execution failures, memory writes, doctor observability, corrupt legacy tolerance, and validation commands.

Do not modify docs during implementation. Do not modify the untracked `cli/` directory.

## Task 1: Add Event Schema Test Helpers

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing event helper tests**

Add these helpers after `assert_status()`:

```bash
assert_jsonl_valid_if_jq() {
    local file="$1"
    if command -v jq >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            printf '%s\n' "$line" | jq -e . >/dev/null
        done < "$file"
    fi
}

assert_jsonl_contains_event_type() {
    local file="$1"
    local event_type="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -e --arg event_type "$event_type" 'select(.schemaVersion == 1 and .eventType == $event_type)' "$file" >/dev/null
    else
        assert_contains "$(cat "$file")" "\"eventType\":\"$event_type\""
    fi
}

assert_jsonl_event_count_at_least() {
    local file="$1"
    local minimum="$2"
    local count
    count="$(wc -l < "$file" | xargs)"
    if [[ "$count" -lt "$minimum" ]]; then
        fail "Expected at least $minimum JSONL events in $file, got $count"
    fi
}
```

Append this test before `main()`:

```bash
test_run_writes_agent_grade_event_schema() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("agent events");
    }
}
JAVA

    "$JV" run Main alpha >"$TMP_ROOT/events-run.out"

    local events="$TMP_ROOT/app/.jv/runs.jsonl"
    assert_exists "$events"
    assert_jsonl_valid_if_jq "$events"
    assert_jsonl_event_count_at_least "$events" 6
    assert_jsonl_contains_event_type "$events" "environment"
    assert_jsonl_contains_event_type "$events" "plan"
    assert_jsonl_contains_event_type "$events" "execution_start"
    assert_jsonl_contains_event_type "$events" "execution_result"
    assert_jsonl_contains_event_type "$events" "memory_write"
    assert_contains "$(cat "$events")" '"schemaVersion":1'
    assert_contains "$(cat "$events")" '"runId":"run_'
    assert_contains "$(cat "$events")" '"command":{"name":"run","argv":["jv","run","Main","alpha"]}'
    assert_contains "$(cat "$events")" '"summary":"Plan selected Main from explicit main class argument"'
}
```

Add `test_run_writes_agent_grade_event_schema` to `main()` after `test_run_writes_plain_args_to_jv_memory`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `.jv/runs.jsonl` still contains only the legacy `{"event":"executed","detail":"..."}` record.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/run-tests.sh
git commit -m "test: cover agent-grade run events"
```

## Task 2: Add Event Context and Envelope Writer

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add event globals**

In `jv.sh`, add these globals near the existing planner globals:

```bash
EVENT_RUN_ID=""
EVENT_SEQUENCE=0
EVENT_COMMAND_NAME=""
EVENT_COMMAND_ARGV=()
```

- [ ] **Step 2: Add JSON helpers**

Add these functions after `json_array_from_lines()`:

```bash
json_bool() {
    if [[ "${1:-}" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

json_string_field() {
    local name="$1"
    local value="$2"
    printf '"%s":"%s"' "$name" "$(json_escape "$value")"
}
```

- [ ] **Step 3: Add event context helpers**

Add these functions after `ensure_jv_dir()`:

```bash
event_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

event_init() {
    local command_name="$1"
    shift || true
    EVENT_COMMAND_NAME="$command_name"
    EVENT_COMMAND_ARGV=("jv" "$command_name" "$@")
    EVENT_RUN_ID="run_$(date -u +"%Y%m%dT%H%M%SZ")_$$"
    EVENT_SEQUENCE=0
}

event_command_json() {
    printf '{"name":"%s","argv":%s}' \
        "$(json_escape "$EVENT_COMMAND_NAME")" \
        "$(json_array_from_lines "${EVENT_COMMAND_ARGV[@]}")"
}

append_event_json() {
    local event_type="$1"
    local summary="$2"
    local payload="$3"

    [[ -n "$EVENT_RUN_ID" ]] || event_init "unknown"
    EVENT_SEQUENCE=$((EVENT_SEQUENCE + 1))
    ensure_jv_dir || return 1
    printf '{"schemaVersion":1,"eventType":"%s","runId":"%s","sequence":%d,"timestamp":"%s","cwd":"%s","command":%s,"summary":"%s","payload":%s}\n' \
        "$(json_escape "$event_type")" \
        "$(json_escape "$EVENT_RUN_ID")" \
        "$EVENT_SEQUENCE" \
        "$(event_timestamp)" \
        "$(json_escape "$PWD")" \
        "$(event_command_json)" \
        "$(json_escape "$summary")" \
        "$payload" >> "$JV_RUNS"
}
```

- [ ] **Step 4: Emit event context from command router**

In `main()`, initialize events before command dispatch:

```bash
main() {
    local command="${1:-help}"
    shift || true
    event_init "$command" "$@"

    case "$command" in
```

- [ ] **Step 5: Keep legacy append helper unused but available**

Replace the existing `append_run_event()` implementation with a compatibility wrapper:

```bash
append_run_event() {
    local event="$1"
    local detail="$2"
    append_event_json "execution_result" "$detail" "{\"phase\":\"run\",\"status\":\"success\",\"exitCode\":0,\"classification\":\"legacy-$event\",\"step\":{\"kind\":\"legacy\",\"display\":\"$(json_escape "$detail")\"}}"
}
```

This keeps any missed call sites writing schema v1 records instead of old records.

- [ ] **Step 6: Run test to verify it still fails later**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because no new environment, plan, start, result, or memory events are emitted yet.

- [ ] **Step 7: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: add JV event envelope writer"
```

## Task 3: Emit Environment, Plan, and Blocker Events

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add blocker event test**

Append before `main()`:

```bash
test_run_writes_blocker_event_without_execution_start() {
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
    "$JV" run >"$TMP_ROOT/blocker-run.out" 2>&1
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected ambiguous run to fail"
    fi

    local events="$TMP_ROOT/app/.jv/runs.jsonl"
    assert_exists "$events"
    assert_jsonl_valid_if_jq "$events"
    assert_jsonl_contains_event_type "$events" "environment"
    assert_jsonl_contains_event_type "$events" "plan"
    assert_jsonl_contains_event_type "$events" "blockers"
    assert_contains "$(cat "$events")" '"classification":"ambiguous-main"'
    assert_not_contains "$(cat "$events")" '"eventType":"execution_start"'
}
```

Add `test_run_writes_blocker_event_without_execution_start` to `main()` after `test_run_refuses_multiple_plain_main_classes`.

- [ ] **Step 2: Add payload helpers**

Add these functions in `jv.sh` after `append_event_json()`:

```bash
tool_event_json() {
    local tool="$1"
    local required="false"
    local available="false"
    local path=""
    local version=""

    if tool_is_required "$tool"; then
        required="true"
    fi
    if command -v "$tool" >/dev/null 2>&1; then
        available="true"
        path="$(command -v "$tool")"
        version="$(tool_version "$tool")"
    fi

    printf '{"name":"%s","required":%s,"available":%s,"path":"%s","version":"%s"}' \
        "$(json_escape "$tool")" \
        "$(json_bool "$required")" \
        "$(json_bool "$available")" \
        "$(json_escape "$path")" \
        "$(json_escape "$version")"
}

tools_event_array_json() {
    printf '[%s,%s,%s]' "$(tool_event_json java)" "$(tool_event_json javac)" "$(tool_event_json mvn)"
}

event_classification_for_blockers() {
    local joined
    joined="$(join_maven_args "${PLAN_BLOCKERS[@]}")"
    case "$joined" in
        *"Multiple main classes"*) printf 'ambiguous-main' ;;
        *"Required tool missing"*) printf 'missing-tool' ;;
        *"No main class"*) printf 'missing-main' ;;
        *"Source root not found"*) printf 'missing-source' ;;
        *"No Java project detected"*) printf 'unknown-project' ;;
        *) printf 'blocked' ;;
    esac
}

emit_environment_event() {
    local payload
    payload="{\"projectShape\":\"$(json_escape "$PLAN_SHAPE")\",\"sourceRoot\":\"$(json_escape "$PLAN_SOURCE_ROOT")\",\"tools\":$(tools_event_array_json)}"
    append_event_json "environment" "Detected $PLAN_SHAPE project environment" "$payload"
}

emit_plan_event() {
    local selected_summary="no selected main"
    [[ -n "$PLAN_SELECTED_MAIN" ]] && selected_summary="$PLAN_SELECTED_MAIN from $PLAN_SELECTED_MAIN_REASON"
    local payload
    payload="{\"projectShape\":\"$(json_escape "$PLAN_SHAPE")\",\"sourceRoot\":\"$(json_escape "$PLAN_SOURCE_ROOT")\",\"mainClass\":{\"selected\":\"$(json_escape "$PLAN_SELECTED_MAIN")\",\"source\":\"$(json_escape "$PLAN_SELECTED_MAIN_SOURCE")\",\"candidates\":$(json_array_from_lines "${PLAN_MAIN_CANDIDATES[@]}")},\"build\":{\"kind\":\"$(json_escape "$PLAN_BUILD_KIND")\",\"display\":\"$(json_escape "$PLAN_BUILD_DISPLAY")\"},\"run\":{\"kind\":\"$(json_escape "$PLAN_RUN_KIND")\",\"display\":\"$(json_escape "$PLAN_RUN_DISPLAY")\",\"args\":$(json_array_from_lines "${PLAN_RUN_ARGS[@]}")},\"reasons\":$(json_array_from_lines "${PLAN_REASONS[@]}"),\"warnings\":$(json_array_from_lines "${PLAN_WARNINGS[@]}")}"
    append_event_json "plan" "Plan selected $selected_summary" "$payload"
}

emit_blockers_event() {
    local classification
    classification="$(event_classification_for_blockers)"
    local payload
    payload="{\"blockers\":$(json_array_from_lines "${PLAN_BLOCKERS[@]}"),\"classification\":\"$(json_escape "$classification")\",\"nextAction\":\"$(json_escape "Run jv doctor for details.")\"}"
    append_event_json "blockers" "Execution blocked: $classification" "$payload"
}
```

- [ ] **Step 3: Emit plan events from `run_java()`**

In `run_java()`, after `build_plan "$@"`, emit environment and plan before checking blockers:

```bash
    build_plan "$@"
    if ! emit_environment_event || ! emit_plan_event; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        if ! emit_blockers_event; then
            warn "Could not write JV events to $JV_RUNS"
        fi
        print_plan_summary >&2
        return 1
    fi
```

- [ ] **Step 4: Emit diagnostic events from `doctor_project()`**

Replace `doctor_project()` with:

```bash
doctor_project() {
    build_plan
    if ! emit_environment_event || ! emit_plan_event; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        if ! emit_blockers_event; then
            warn "Could not write JV events to $JV_RUNS"
        fi
    fi
    print_doctor_report
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL only on missing execution and memory events from the first schema test.

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: emit planner events"
```

## Task 4: Emit Execution Start and Result Events

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add runtime failure event test**

Append before `main()`:

```bash
test_run_failure_writes_execution_result_event_without_success_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("event failure");
        System.exit(7);
    }
}
JAVA

    set +e
    "$JV" run >"$TMP_ROOT/failure-events.out" 2>&1
    local status=$?
    set -e

    assert_status "$status" 7
    local events="$TMP_ROOT/app/.jv/runs.jsonl"
    assert_exists "$events"
    assert_jsonl_valid_if_jq "$events"
    assert_jsonl_contains_event_type "$events" "execution_result"
    assert_contains "$(cat "$events")" '"status":"failure"'
    assert_contains "$(cat "$events")" '"exitCode":7'
    assert_contains "$(cat "$events")" '"classification":"runtime-failure"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}
```

Add `test_run_failure_writes_execution_result_event_without_success_memory` to `main()` after `test_run_failure_does_not_write_success_memory`.

- [ ] **Step 2: Add execution event helpers**

Add these functions to `jv.sh` after `emit_blockers_event()`:

```bash
emit_execution_start_event() {
    local phase="$1"
    local kind="$2"
    local display="$3"
    local payload
    payload="{\"phase\":\"$(json_escape "$phase")\",\"step\":{\"kind\":\"$(json_escape "$kind")\",\"display\":\"$(json_escape "$display")\"}}"
    append_event_json "execution_start" "Starting $phase step" "$payload"
}

emit_execution_result_event() {
    local phase="$1"
    local kind="$2"
    local display="$3"
    local status="$4"
    local exit_code="$5"
    local classification="$6"
    local payload
    payload="{\"phase\":\"$(json_escape "$phase")\",\"status\":\"$(json_escape "$status")\",\"exitCode\":$exit_code,\"classification\":\"$(json_escape "$classification")\",\"step\":{\"kind\":\"$(json_escape "$kind")\",\"display\":\"$(json_escape "$display")\"}}"
    append_event_json "execution_result" "$phase $status with exit code $exit_code" "$payload"
}
```

- [ ] **Step 3: Wrap Maven execution events**

In the Maven branch of `run_java()`, emit events around `mvn compile`:

```bash
        if ! emit_execution_start_event "compile" "maven" "$PLAN_BUILD_DISPLAY"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
        set +e
        mvn compile
        local maven_status=$?
        set -e
        if [[ $maven_status -ne 0 ]]; then
            if ! emit_execution_result_event "compile" "maven" "$PLAN_BUILD_DISPLAY" "failure" "$maven_status" "compile-failure"; then
                warn "Could not write JV events to $JV_RUNS"
            fi
            return "$maven_status"
        fi
        if ! emit_execution_result_event "compile" "maven" "$PLAN_BUILD_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
```

Emit around the Maven run command:

```bash
        if ! emit_execution_start_event "run" "maven" "$PLAN_RUN_DISPLAY"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
        set +e
        if [[ -n "$maven_args" ]]; then
            mvn -q exec:java -Dexec.mainClass="$class_name" -Dexec.args="$maven_args"
        else
            mvn -q exec:java -Dexec.mainClass="$class_name"
        fi
        maven_status=$?
        set -e
        if [[ $maven_status -ne 0 ]]; then
            if ! emit_execution_result_event "run" "maven" "$PLAN_RUN_DISPLAY" "failure" "$maven_status" "runtime-failure"; then
                warn "Could not write JV events to $JV_RUNS"
            fi
            return "$maven_status"
        fi
        if ! emit_execution_result_event "run" "maven" "$PLAN_RUN_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
```

- [ ] **Step 4: Wrap plain Java execution events**

Before `java -cp "$classpath" "$class_name" "${args[@]}"`, add:

```bash
    if ! emit_execution_start_event "run" "java" "$PLAN_RUN_DISPLAY"; then
        warn "Could not write JV events to $JV_RUNS"
    fi
```

After `java_status` is captured, add:

```bash
    if [[ $java_status -eq 0 ]]; then
        if ! emit_execution_result_event "run" "java" "$PLAN_RUN_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
    else
        if ! emit_execution_result_event "run" "java" "$PLAN_RUN_DISPLAY" "failure" "$java_status" "runtime-failure"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
    fi
```

- [ ] **Step 5: Run tests**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL only on missing `memory_write` event from successful runs.

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: emit execution events"
```

## Task 5: Emit Memory Write Events and Preserve Legacy Compatibility

**Files:**
- Modify: `jv.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Add legacy corrupt tolerance test**

Append before `main()`:

```bash
test_run_appends_v1_events_after_legacy_and_corrupt_lines() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src" "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("legacy compatible");
    }
}
JAVA
    printf '%s\n' '{"event":"executed","detail":"java -cp bin OldMain"}' '{bad json' > .jv/runs.jsonl

    "$JV" run >"$TMP_ROOT/legacy-events.out"

    local events="$TMP_ROOT/app/.jv/runs.jsonl"
    assert_contains "$(sed -n '1p' "$events")" '"event":"executed"'
    assert_contains "$(sed -n '2p' "$events")" '{bad json'
    assert_jsonl_contains_event_type "$events" "plan"
    assert_jsonl_contains_event_type "$events" "memory_write"
}
```

Add `test_run_appends_v1_events_after_legacy_and_corrupt_lines` to `main()` after `test_run_writes_agent_grade_event_schema`.

- [ ] **Step 2: Add memory event helper**

Add to `jv.sh` after `emit_execution_result_event()`:

```bash
emit_memory_write_event() {
    local target="$1"
    local status="$2"
    local classification="$3"
    local payload
    payload="{\"target\":\"$(json_escape "$target")\",\"status\":\"$(json_escape "$status")\",\"classification\":\"$(json_escape "$classification")\",\"rememberedMainClass\":\"$(json_escape "$PLAN_REMEMBERED_MAIN")\",\"lastSuccessfulMainClass\":\"$(json_escape "$PLAN_SELECTED_MAIN")\",\"lastPlan\":{\"build\":\"$(json_escape "$PLAN_BUILD_DISPLAY")\",\"run\":\"$(json_escape "$PLAN_RUN_DISPLAY")\"}}"
    append_event_json "memory_write" "Memory write $status for $target" "$payload"
}
```

- [ ] **Step 3: Update success memory writer**

Replace `write_success_memory_from_plan()` with:

```bash
write_success_memory_from_plan() {
    if [[ -z "$PLAN_SELECTED_MAIN" || -z "$PLAN_BUILD_DISPLAY" || -z "$PLAN_RUN_DISPLAY" ]]; then
        emit_memory_write_event "$JV_STATE" "skipped" "missing-plan" || true
        return 1
    fi
    if ! write_state "$PLAN_SHAPE" "$PLAN_SELECTED_MAIN" "$PLAN_BUILD_DISPLAY" "$PLAN_RUN_DISPLAY"; then
        emit_memory_write_event "$JV_STATE" "failure" "memory-unavailable" || true
        return 1
    fi
    if ! emit_memory_write_event "$JV_STATE" "success" "completed"; then
        return 1
    fi
}
```

- [ ] **Step 4: Emit memory events for remember and forget**

After a successful write in `remember_main()`, before `success "Remembered main class: $main_class"`, add:

```bash
    PLAN_REMEMBERED_MAIN="$main_class"
    PLAN_SELECTED_MAIN="$main_class"
    emit_memory_write_event "$JV_STATE" "success" "remember-main" || warn "Could not write JV events to $JV_RUNS"
```

After `forget_main()` removes or rewrites state, before `success "Forgot remembered main class"`, add:

```bash
    PLAN_REMEMBERED_MAIN=""
    PLAN_SELECTED_MAIN=""
    emit_memory_write_event "$JV_STATE" "success" "forget-main" || warn "Could not write JV events to $JV_RUNS"
```

- [ ] **Step 5: Run full verification**

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

`bash -n` exits 0. `shellcheck` exits 0.

- [ ] **Step 6: Commit**

```bash
git add jv.sh tests/run-tests.sh
git commit -m "feat: emit JV memory events"
```

## Final Review Checklist

- [ ] New `.jv/runs.jsonl` writes are append-only.
- [ ] `run` writes environment, plan, blockers when blocked, execution start/result when executing, and memory write when state changes.
- [ ] `doctor` writes environment, plan, and blockers but does not execute or update `.jv/state.json`.
- [ ] `explain` remains side-effect free.
- [ ] Existing legacy `{"event":"executed","detail":"..."}` and corrupt lines are not rewritten and do not block new appends.
- [ ] Successful Java runs still exit 0 when event or memory writes fail, with a warning.
- [ ] No runtime dependency on `jq`.
- [ ] Only `jv.sh` and `tests/run-tests.sh` changed during implementation.

