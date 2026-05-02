# JV History / Events Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only `jv history` inspection command, with `jv events` as an alias, that summarizes recent `.jv/runs.jsonl` activity for humans and agents.

**Architecture:** Keep this product slice in the existing Bash CLI. Add one history parser/normalizer path that reads `.jv/runs.jsonl`, optionally enriches the latest legacy record from `.jv/state.json`, and renders either text or normalized JSON. Do not change how `jv run` writes events in this slice; tolerate current simple records and future schema-versioned Agent-Grade JV Events records.

**Tech Stack:** Bash, existing `jv.sh`, shell integration tests in `tests/run-tests.sh`, optional `jq` only inside tests for validating JSON output, existing `.jv/state.json` and `.jv/runs.jsonl` generated memory.

---

## File Structure

- Modify `jv.sh`: add `history` and `events` command routing; add argument parsing for `--limit`, `--failures`, and `--json`; add read-only history normalization/rendering helpers.
- Modify `tests/run-tests.sh`: add focused integration tests for legacy records, aliasing, flags, missing/empty/corrupt history, mixed future events, JSON output, and side-effect freedom.
- Modify `README.md` only if help/docs drift after implementation; add one short command description if needed.
- Modify `EXAMPLES.md` only if the file exists and implementation output examples need a user-facing walkthrough. If `EXAMPLES.md` is absent, do not create it for this slice.
- Do not modify the pre-existing untracked `cli/` directory.
- Do not create new production files for MVP.

## Command Contract

Primary command:

```bash
jv history [--limit N] [--failures] [--json]
```

Alias:

```bash
jv events [--limit N] [--failures] [--json]
```

Default behavior:

- Read `.jv/runs.jsonl`.
- Show newest valid records first.
- Default limit is `10`.
- Skip corrupt lines and report a warning.
- Exit `0` for missing `.jv/`, missing log, empty log, and corrupt skipped lines.
- Exit non-zero for invalid flags, invalid `--limit`, or unreadable `.jv/runs.jsonl`.
- Never create `.jv/`, `bin/`, or any project files.

## Normalized Record Shape

Use shell variables while parsing, but render this conceptual shape:

```json
{
  "status": "success",
  "eventType": "result",
  "timestamp": null,
  "runId": null,
  "eventId": null,
  "mainClass": "Main",
  "command": "java -cp bin Main one two",
  "summary": "Executed java -cp bin Main one two",
  "reason": null
}
```

For Bash storage, use tab-separated normalized rows internally:

```text
status<TAB>eventType<TAB>timestamp<TAB>runId<TAB>eventId<TAB>mainClass<TAB>command<TAB>summary<TAB>reason
```

Before writing text or JSON, replace missing values with `-` for text and `null` for JSON.

## Task 1: Add Legacy History Rendering

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `jv.sh`

- [ ] **Step 1: Write failing tests for legacy history**

Add these tests before `main()` in `tests/run-tests.sh`:

```bash
test_history_renders_legacy_run_log() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main one two"}
JSONL
    cat > .jv/state.json <<'JSON'
{
  "schemaVersion": 1,
  "projectShape": "plain-java",
  "lastSuccessfulMainClass": "Main",
  "lastPlan": {
    "build": "javac -d bin -cp bin <sources>",
    "run": "java -cp bin Main one two"
  }
}
JSON

    local output
    output="$("$JV" history)"

    assert_contains "$output" "JV history"
    assert_contains "$output" "Source: .jv/runs.jsonl"
    assert_contains "$output" "1. success  Main  java -cp bin Main one two"
}

test_events_alias_matches_history_for_legacy_run_log() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main"}
JSONL

    local history_output
    local events_output
    history_output="$("$JV" history)"
    events_output="$("$JV" events)"

    [[ "$history_output" == "$events_output" ]] || fail "Expected jv events to match jv history"
}
```

Add both tests to `main()` after the existing `.jv` memory tests:

```bash
    test_history_renders_legacy_run_log
    test_events_alias_matches_history_for_legacy_run_log
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL with `Unknown command: history`.

- [ ] **Step 3: Add history command routing and help text**

In `show_help()` in `jv.sh`, add rows after `doctor`:

```bash
    echo -e "  ${GREEN}history${NC} [--limit N] [--failures] [--json]  Show recent JV run history"
    echo -e "  ${GREEN}events${NC} [--limit N] [--failures] [--json]   Alias for history"
```

In the examples section, add:

```bash
    echo -e "  jv history                            # Show recent JV runs"
```

In `main()`, add cases after `doctor`:

```bash
        history)
            show_history "$@"
            ;;
        events)
            show_history "$@"
            ;;
```

- [ ] **Step 4: Add minimal legacy history implementation**

Add these helpers before `compile_java()` in `jv.sh`:

```bash
history_extract_json_string() {
    local key="$1"
    local line="$2"
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<<"$line" | head -n 1
}

history_main_from_command() {
    local command_text="$1"
    local token
    local previous=""
    local after_classpath=0

    for token in $command_text; do
        if [[ "$previous" == "-cp" || "$previous" == "-classpath" ]]; then
            after_classpath=1
            previous="$token"
            continue
        fi
        if [[ $after_classpath -eq 1 ]]; then
            printf '%s\n' "$token"
            return 0
        fi
        case "$token" in
            -Dexec.mainClass=*)
                printf '%s\n' "${token#-Dexec.mainClass=}"
                return 0
                ;;
        esac
        previous="$token"
    done
}

history_normalize_legacy_line() {
    local line="$1"
    local event
    local detail
    local main_class

    event="$(history_extract_json_string "event" "$line")"
    detail="$(history_extract_json_string "detail" "$line")"

    if [[ "$event" != "executed" || -z "$detail" ]]; then
        return 1
    fi

    main_class="$(history_main_from_command "$detail")"
    printf 'success\tresult\t\t\t\t%s\t%s\tExecuted %s\t\n' "$main_class" "$detail" "$detail"
}

history_render_text_rows() {
    local rows=("$@")
    local row
    local index=1
    local status event_type timestamp run_id event_id main_class command_text summary reason

    echo "JV history"
    echo "Source: $JV_RUNS"
    echo ""

    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "No JV history entries found in $JV_RUNS."
        return 0
    fi

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r status event_type timestamp run_id event_id main_class command_text summary reason <<<"$row"
        [[ -n "$main_class" ]] || main_class="-"
        [[ -n "$command_text" ]] || command_text="-"
        printf '%d. %s  %s  %s\n' "$index" "$status" "$main_class" "$command_text"
        if [[ -n "$reason" ]]; then
            printf '   Reason: %s\n' "$reason"
        fi
        index=$((index + 1))
    done
}

show_history() {
    local limit=10
    local failures_only=0
    local json_mode=0
    local arg
    local rows=()
    local line
    local normalized

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --limit)
                shift
                limit="${1:-}"
                ;;
            --failures)
                failures_only=1
                ;;
            --json)
                json_mode=1
                ;;
            *)
                error "Unknown history option: $arg"
                ;;
        esac
        shift || true
    done

    : "$failures_only" "$json_mode"

    if [[ ! "$limit" =~ ^[1-9][0-9]*$ ]]; then
        error "--limit must be a positive integer"
    fi

    if [[ ! -e "$JV_RUNS" ]]; then
        echo "JV history"
        echo "Source: $JV_RUNS"
        echo ""
        echo "No JV history found. Run \`jv run\` to create $JV_RUNS."
        return 0
    fi

    if [[ ! -r "$JV_RUNS" ]]; then
        error "Cannot read $JV_RUNS"
    fi

    while IFS= read -r line; do
        normalized="$(history_normalize_legacy_line "$line" || true)"
        if [[ -n "$normalized" ]]; then
            rows=("$normalized" "${rows[@]}")
        fi
    done < "$JV_RUNS"

    if [[ ${#rows[@]} -gt "$limit" ]]; then
        rows=("${rows[@]:0:$limit}")
    fi

    history_render_text_rows "${rows[@]}"
}
```

This step intentionally ignores `--json`, `--failures`, future event records, and corrupt-line warnings. Later tasks add those behaviors with tests.

- [ ] **Step 5: Run tests to verify pass**

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
git commit -m "feat: add JV history command"
```

## Task 2: Add Empty-State And Side-Effect Tests

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `jv.sh`

- [ ] **Step 1: Write failing tests for missing and empty history**

Add:

```bash
test_history_missing_jv_is_empty_state_and_side_effect_free() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    local output
    output="$("$JV" history)"

    assert_contains "$output" "No JV history found"
    assert_not_exists "$TMP_ROOT/app/.jv"
    assert_not_exists "$TMP_ROOT/app/bin"
}

test_history_empty_runs_log_is_empty_state() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    : > .jv/runs.jsonl

    local output
    output="$("$JV" history)"

    assert_contains "$output" "No JV history entries found in .jv/runs.jsonl."
}
```

Add both tests to `main()` after `test_events_alias_matches_history_for_legacy_run_log`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL if the current implementation does not distinguish empty logs from missing logs.

- [ ] **Step 3: Track whether the log file had lines**

In `show_history()`, add:

```bash
    local line_count=0
```

Inside the `while IFS= read -r line` loop, add before normalization:

```bash
        line_count=$((line_count + 1))
```

After the loop and before applying the limit, add:

```bash
    if [[ $line_count -eq 0 ]]; then
        echo "JV history"
        echo "Source: $JV_RUNS"
        echo ""
        echo "No JV history entries found in $JV_RUNS."
        return 0
    fi
```

- [ ] **Step 4: Run tests to verify pass**

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
git commit -m "fix: handle empty JV history"
```

## Task 3: Add Limit, Failure Filter, And Flag Validation

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `jv.sh`

- [ ] **Step 1: Write failing tests for filters and validation**

Add:

```bash
test_history_limit_shows_newest_records() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin First"}
{"event":"executed","detail":"java -cp bin Second"}
JSONL

    local output
    output="$("$JV" history --limit 1)"

    assert_contains "$output" "1. success  Second  java -cp bin Second"
    assert_not_contains "$output" "First"
}

test_history_failures_filter_empty_for_legacy_successes() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main"}
JSONL

    local output
    output="$("$JV" history --failures)"

    assert_contains "$output" "No failed or blocked JV events found."
    assert_not_contains "$output" "java -cp bin Main"
}

test_history_rejects_invalid_limit() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    set +e
    local output
    output="$("$JV" history --limit nope 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected invalid --limit to fail"
    fi
    assert_contains "$output" "Error: --limit must be a positive integer"
}
```

Add the tests to `main()`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `--failures` still renders success rows or does not print the filtered empty state.

- [ ] **Step 3: Apply failure filtering before limiting**

In `show_history()`, after collecting rows and before applying `limit`, add:

```bash
    if [[ $failures_only -eq 1 ]]; then
        local filtered=()
        local row_status
        local row
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r row_status _ <<<"$row"
            if [[ "$row_status" == "failure" || "$row_status" == "blocked" ]]; then
                filtered+=("$row")
            fi
        done
        rows=("${filtered[@]}")
    fi
```

Update `history_render_text_rows()` to accept a second argument for the empty message:

```bash
history_render_text_rows() {
    local empty_message="$1"
    shift
    local rows=("$@")
```

Replace its empty-state line with:

```bash
        echo "$empty_message"
```

Update the call in `show_history()`:

```bash
    local empty_message="No JV history entries found in $JV_RUNS."
    if [[ $failures_only -eq 1 ]]; then
        empty_message="No failed or blocked JV events found."
    fi
    history_render_text_rows "$empty_message" "${rows[@]}"
```

- [ ] **Step 4: Run tests to verify pass**

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
git commit -m "feat: filter JV history"
```

## Task 4: Support Future Event Records And Corrupt Lines

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `jv.sh`

- [ ] **Step 1: Write failing tests for schema-versioned records and corrupt lines**

Add:

```bash
test_history_renders_mixed_legacy_and_future_events() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main"}
{"schemaVersion":1,"eventId":"evt_2","runId":"run_2","timestamp":"2026-05-01T20:05:00Z","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"error","summary":"Compilation failed","payload":{"status":"failure","phase":"compile","step":{"kind":"build","argv":["javac","-d","bin","-cp","bin","src/Main.java"],"exitCode":1},"classification":"compile-failure","nextAction":"Fix compiler errors and run jv run again"}}
JSONL

    local output
    output="$("$JV" history)"

    assert_contains "$output" "1. failure  -  javac -d bin -cp bin src/Main.java"
    assert_contains "$output" "Reason: compile-failure"
    assert_contains "$output" "2. success  Main  java -cp bin Main"
}

test_history_skips_corrupt_jsonl_lines() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main"}
not json
{"schemaVersion":1,"eventType":"result","level":"error","summary":"No main class","payload":{"status":"blocked","classification":"missing-main"}}
JSONL

    local output
    output="$("$JV" history)"

    assert_contains "$output" "1. blocked  -  -"
    assert_contains "$output" "Reason: missing-main"
    assert_contains "$output" "2. success  Main  java -cp bin Main"
    assert_contains "$output" "Warning: skipped 1 corrupt .jv/runs.jsonl line"
}
```

Add both tests to `main()`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because future event records are not normalized and corrupt-line warnings are not counted.

- [ ] **Step 3: Add small extraction helpers for future records**

Add helpers near the existing history helpers:

```bash
history_line_looks_like_json_object() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*\{.*\}[[:space:]]*$ ]]
}

history_extract_json_number_or_string() {
    local key="$1"
    local line="$2"
    local value
    value="$(history_extract_json_string "$key" "$line")"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
    fi
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([^,}][^,}]*\\).*/\\1/p" <<<"$line" | head -n 1 | xargs
}

history_extract_argv_command() {
    local key_path="$1"
    local line="$2"
    local array_text
    : "$key_path"
    array_text="$(sed -n 's/.*"argv"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' <<<"$line" | tail -n 1)"
    if [[ -z "$array_text" ]]; then
        return 0
    fi
    printf '%s\n' "$array_text" | sed 's/"//g; s/[[:space:]]*,[[:space:]]*/ /g'
}
```

- [ ] **Step 4: Add future event normalizer**

Add:

```bash
history_normalize_future_line() {
    local line="$1"
    local status
    local event_type
    local timestamp
    local run_id
    local event_id
    local summary
    local reason
    local command_text
    local main_class
    local level

    if ! grep -q '"schemaVersion"[[:space:]]*:' <<<"$line"; then
        return 1
    fi

    status="$(history_extract_json_string "status" "$line")"
    level="$(history_extract_json_string "level" "$line")"
    reason="$(history_extract_json_string "classification" "$line")"
    event_type="$(history_extract_json_string "eventType" "$line")"
    timestamp="$(history_extract_json_string "timestamp" "$line")"
    run_id="$(history_extract_json_string "runId" "$line")"
    event_id="$(history_extract_json_string "eventId" "$line")"
    summary="$(history_extract_json_string "summary" "$line")"
    command_text="$(history_extract_argv_command "payload.step.argv" "$line")"

    if [[ -z "$status" ]]; then
        if [[ "$level" == "error" ]]; then
            status="failure"
        else
            status="info"
        fi
    fi
    if [[ "$status" == "failure" && "$reason" == *"missing-main"* ]]; then
        status="blocked"
    fi
    if [[ "$reason" == *"missing-main"* || "$reason" == *"ambiguous-main"* ]]; then
        status="blocked"
    fi

    main_class="$(history_main_from_command "$command_text")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$event_type" "$timestamp" "$run_id" "$event_id" "$main_class" "$command_text" "$summary" "$reason"
}
```

This extraction is intentionally narrow and test-driven. It supports the documented event shapes without pretending to be a full JSON parser.

- [ ] **Step 5: Count corrupt lines and call both normalizers**

In `show_history()`, add:

```bash
    local corrupt_count=0
```

Replace the normalization body in the read loop with:

```bash
        if ! history_line_looks_like_json_object "$line"; then
            corrupt_count=$((corrupt_count + 1))
            continue
        fi

        normalized="$(history_normalize_future_line "$line" || true)"
        if [[ -z "$normalized" ]]; then
            normalized="$(history_normalize_legacy_line "$line" || true)"
        fi
        if [[ -n "$normalized" ]]; then
            rows=("$normalized" "${rows[@]}")
        else
            corrupt_count=$((corrupt_count + 1))
        fi
```

After `history_render_text_rows`, print warnings:

```bash
    if [[ $corrupt_count -eq 1 ]]; then
        echo ""
        echo "Warning: skipped 1 corrupt $JV_RUNS line"
    elif [[ $corrupt_count -gt 1 ]]; then
        echo ""
        echo "Warning: skipped $corrupt_count corrupt $JV_RUNS lines"
    fi
```

- [ ] **Step 6: Run tests to verify pass**

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
git commit -m "feat: normalize JV event history"
```

## Task 5: Add JSON Output

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `jv.sh`

- [ ] **Step 1: Write failing JSON output test**

Add:

```bash
test_history_json_outputs_normalized_records() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/.jv"
    cd "$TMP_ROOT/app"
    cat > .jv/runs.jsonl <<'JSONL'
{"event":"executed","detail":"java -cp bin Main one two"}
JSONL

    local output
    output="$("$JV" history --json)"

    assert_contains "$output" '"schemaVersion": 1'
    assert_contains "$output" '"source": ".jv/runs.jsonl"'
    assert_contains "$output" '"failuresOnly": false'
    assert_contains "$output" '"status": "success"'
    assert_contains "$output" '"mainClass": "Main"'
    assert_contains "$output" '"command": "java -cp bin Main one two"'
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$output" | jq -e '.records[0].status == "success"' >/dev/null
    fi
}
```

Add the test to `main()`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `--json` still renders text.

- [ ] **Step 3: Add JSON value helper**

Add:

```bash
history_json_value() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "$value")"
    fi
}
```

- [ ] **Step 4: Add JSON renderer**

Add:

```bash
history_render_json_rows() {
    local limit="$1"
    local failures_only="$2"
    local corrupt_count="$3"
    shift 3
    local rows=("$@")
    local row
    local first=1
    local status event_type timestamp run_id event_id main_class command_text summary reason

    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "source": "%s",\n' "$(json_escape "$JV_RUNS")"
    printf '  "limit": %s,\n' "$limit"
    if [[ $failures_only -eq 1 ]]; then
        echo '  "failuresOnly": true,'
    else
        echo '  "failuresOnly": false,'
    fi
    echo '  "records": ['
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r status event_type timestamp run_id event_id main_class command_text summary reason <<<"$row"
        if [[ $first -eq 0 ]]; then
            echo ","
        fi
        echo "    {"
        printf '      "status": %s,\n' "$(history_json_value "$status")"
        printf '      "eventType": %s,\n' "$(history_json_value "$event_type")"
        printf '      "timestamp": %s,\n' "$(history_json_value "$timestamp")"
        printf '      "runId": %s,\n' "$(history_json_value "$run_id")"
        printf '      "eventId": %s,\n' "$(history_json_value "$event_id")"
        printf '      "mainClass": %s,\n' "$(history_json_value "$main_class")"
        printf '      "command": %s,\n' "$(history_json_value "$command_text")"
        printf '      "summary": %s,\n' "$(history_json_value "$summary")"
        printf '      "reason": %s\n' "$(history_json_value "$reason")"
        printf '    }'
        first=0
    done
    echo ""
    echo '  ],'
    echo '  "warnings": ['
    if [[ $corrupt_count -gt 0 ]]; then
        echo "    {"
        echo '      "type": "corrupt-line",'
        printf '      "count": %s,\n' "$corrupt_count"
        if [[ $corrupt_count -eq 1 ]]; then
            printf '      "message": "Skipped 1 corrupt %s line"\n' "$(json_escape "$JV_RUNS")"
        else
            printf '      "message": "Skipped %s corrupt %s lines"\n' "$corrupt_count" "$(json_escape "$JV_RUNS")"
        fi
        echo "    }"
    fi
    echo '  ]'
    echo "}"
}
```

- [ ] **Step 5: Route JSON mode**

In `show_history()`, before text rendering, add:

```bash
    if [[ $json_mode -eq 1 ]]; then
        history_render_json_rows "$limit" "$failures_only" "$corrupt_count" "${rows[@]}"
        return 0
    fi
```

For missing and empty history branches, return JSON when `json_mode=1`:

```bash
        if [[ $json_mode -eq 1 ]]; then
            history_render_json_rows "$limit" "$failures_only" 0
            return 0
        fi
```

- [ ] **Step 6: Run tests to verify pass**

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
git commit -m "feat: add JSON JV history output"
```

## Task 6: Update User Docs If Needed

**Files:**
- Modify: `README.md`
- Modify: `EXAMPLES.md` only if it already exists
- Modify: `tests/run-tests.sh` if help-output assertions need updating

- [ ] **Step 1: Inspect current docs and help tests**

Run:

```bash
rg -n "doctor|history|events|help_lists" README.md EXAMPLES.md tests/run-tests.sh
```

Expected: existing docs mention `doctor` and `.jv/`, and tests may assert help output.

- [ ] **Step 2: Update README only if command docs are missing**

If `README.md` has a command list, add this concise line near `doctor`:

```markdown
`jv history` shows recent generated `.jv/runs.jsonl` activity; `jv events` is an alias for the same inspection view.
```

If `README.md` has examples, add:

```bash
jv history
jv history --failures
jv history --json
```

- [ ] **Step 3: Update EXAMPLES only if it exists**

If `EXAMPLES.md` exists, add this example:

````markdown
### Inspect recent JV activity

```bash
jv history
```

```text
JV history
Source: .jv/runs.jsonl

1. success  Main  java -cp bin Main
```
````

If `EXAMPLES.md` does not exist, skip this step and do not create it.

- [ ] **Step 4: Run docs-related tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 5: Commit only if docs changed**

If `README.md`, `EXAMPLES.md`, or help tests changed:

```bash
git add README.md tests/run-tests.sh
if [[ -f EXAMPLES.md ]]; then
    git add EXAMPLES.md
fi
git commit -m "docs: document JV history command"
```

If no docs changed, do not create an empty commit.

## Task 7: Final Verification

**Files:**
- No planned file edits unless verification finds a bug.

- [ ] **Step 1: Run full shell tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 2: Run syntax checks**

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

- [ ] **Step 4: Inspect git diff**

Run:

```bash
git status --short
git diff -- jv.sh tests/run-tests.sh README.md EXAMPLES.md
```

Expected:

- Only intended files are modified.
- The pre-existing untracked `cli/` directory remains untouched and unstaged.
- `jv history` and `jv events` are read-only.

- [ ] **Step 5: Commit any verification fixes**

If verification finds a bug, fix only the affected files and commit. For example:

```bash
git add jv.sh tests/run-tests.sh
git commit -m "fix: stabilize JV history command"
```

If no fixes are needed, do not create an empty commit.

## Self-Review Checklist

- Spec coverage: The tasks cover `jv history` as primary command, `jv events` aliasing, human text output, agent JSON output, `--limit`, `--failures`, missing `.jv/`, empty logs, corrupt JSONL lines, mixed legacy/future records, side-effect freedom, and optional docs updates.
- Placeholder scan: No task relies on "add appropriate handling" without exact tests, code shape, and commands.
- Type consistency: The normalized row order is stable across parser, text renderer, JSON renderer, and filter steps.
- Implementation scope: Production changes stay in `jv.sh`; tests stay in `tests/run-tests.sh`; README/EXAMPLES changes are conditional and small.
- Verification: Final commands are `tests/run-tests.sh`, `bash -n jv.sh tests/run-tests.sh install.sh`, and `shellcheck jv.sh tests/run-tests.sh install.sh`.
