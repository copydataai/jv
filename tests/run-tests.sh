#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JV="$ROOT_DIR/jv.sh"
TMP_ROOT=""

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Expected output to contain: $needle" >&2
        echo "Actual output:" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "Expected output not to contain: $needle" >&2
        echo "Actual output:" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

assert_not_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        fail "Expected path not to exist: $path"
    fi
}

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
    local line
    if command -v jq >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if printf '%s\n' "$line" | jq -e --arg event_type "$event_type" '.schemaVersion == 1 and .eventType == $event_type' >/dev/null 2>&1; then
                return 0
            fi
        done < "$file"
        fail "Expected $file to contain schema v1 event type: $event_type"
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

setup_tmp() {
    cleanup_tmp
    TMP_ROOT="$(mktemp -d)"
}

cleanup_tmp() {
    if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}

trap cleanup_tmp EXIT

test_create_compile_run_packaged_project() {
    setup_tmp
    cd "$TMP_ROOT"

    "$JV" create demo com.example >"$TMP_ROOT/jv-test-create.out"
    cd demo

    local output
    output="$("$JV" run com.example.Main alpha beta)"

    assert_contains "$output" "Hello from JV!"
    assert_contains "$output" "Package: com.example"
    assert_contains "$output" "  - alpha"
    assert_contains "$output" "  - beta"
}

test_create_does_not_write_jv_json() {
    setup_tmp
    cd "$TMP_ROOT"

    printf '\n' | "$JV" create demo >"$TMP_ROOT/jv-test-create-no-json.out"

    assert_not_exists "$TMP_ROOT/demo/jv.json"
}

test_run_infers_single_plain_main_class() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("inferred main");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "JV detected: plain Java project"
    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "inferred main"
}

test_run_infers_single_plain_main_class_with_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("args count: " + args.length);
        for (String arg : args) {
            System.out.println("arg: " + arg);
        }
    }
}
JAVA

    local output
    output="$("$JV" run one two)"

    assert_contains "$output" "Main class: Main"
    assert_contains "$output" "args count: 2"
    assert_contains "$output" "arg: one"
    assert_contains "$output" "arg: two"
}

test_run_refuses_multiple_plain_main_classes() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("app");
    }
}
JAVA
    cat > src/com/example/Tool.java <<'JAVA'
package com.example;

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

    if [[ $status -eq 0 ]]; then
        fail "Expected ambiguous main class run to fail"
    fi
    assert_contains "$output" "Multiple main classes found"
    assert_contains "$output" "com.example.App"
    assert_contains "$output" "com.example.Tool"
    assert_contains "$output" "jv run <MainClass>"
}

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
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"eventType":"failure"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"main_ambiguous"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"retryCommand":"jv run App"'
}

test_run_refuses_multiple_plain_main_classes_with_non_candidate_token() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("app");
    }
}
JAVA
    cat > src/com/example/Tool.java <<'JAVA'
package com.example;

public class Tool {
    public static void main(String[] args) {
        System.out.println("tool");
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run one two 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected ambiguous main class run with app-like args to fail"
    fi
    assert_contains "$output" "Multiple main classes found"
    assert_contains "$output" "com.example.App"
    assert_contains "$output" "com.example.Tool"
    assert_contains "$output" "jv run <MainClass>"
}

test_run_ignores_commented_plain_main_signatures() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("real main");
    }
}
JAVA
    cat > src/com/example/Notes.java <<'JAVA'
package com.example;

public class Notes {
    // public static void main(String[] args) {
    //     System.out.println("not a main");
    // }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "real main"
}

test_run_ignores_block_commented_plain_main_signatures() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("real block main");
    }
}
JAVA
    cat > src/com/example/Notes.java <<'JAVA'
package com.example;

public class Notes {
    /*
    public static void main(String[] args) {
        System.out.println("not real");
    }
    */
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "real block main"
}

test_run_infers_main_with_spaced_array_signature() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String [] args) {
        System.out.println("spaced array main");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "spaced array main"
}

test_run_infers_main_with_name_array_signature() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String args[]) {
        System.out.println("name array main");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "name array main"
}

test_run_infers_main_with_no_space_varargs_signature() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    public static void main(String... args) {
        System.out.println("no-space varargs main");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "no-space varargs main"
}

test_run_ignores_block_comment_marker_inside_string_literal() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    private static final String MARKER = "/*";

    public static void main(String[] args) {
        System.out.println("string marker main");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "string marker main"
}

test_run_detects_main_after_block_comment_with_quote_before_terminator() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src/com/example"
    cd "$TMP_ROOT/app"
    cat > src/com/example/App.java <<'JAVA'
package com.example;

public class App {
    /* comment mentions "*/
    public static void main(String[] args) {
        System.out.println("after tricky comment");
    }
}
JAVA

    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "after tricky comment"
}

test_explain_prints_plan_without_compiling() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("hello");
    }
}
JAVA

    local output
    output="$("$JV" explain)"

    assert_contains "$output" "JV detected: plain Java project"
    assert_contains "$output" "Main class: Main"
    assert_contains "$output" "Build path: javac -d bin"
    assert_contains "$output" "Run path: java -cp bin Main"
    assert_not_exists "$TMP_ROOT/app/bin/Main.class"
}

test_explain_prints_plain_run_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("hello");
    }
}
JAVA

    local output
    output="$("$JV" explain Main one two)"

    assert_contains "$output" "Main class: Main"
    assert_contains "$output" "Run path: java -cp bin Main one two"
}

test_run_writes_jv_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("memory");
    }
}
JAVA

    "$JV" run >"$TMP_ROOT/jv-test-memory.out"

    [[ -f "$TMP_ROOT/app/.jv/state.json" ]] || fail "Expected .jv/state.json"
    [[ -f "$TMP_ROOT/app/.jv/runs.jsonl" ]] || fail "Expected .jv/runs.jsonl"
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"projectShape": "plain-java"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"lastSuccessfulMainClass": "Main"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"eventType":"memory_write"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"classification":"completed"'
}

test_run_writes_plain_args_to_jv_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("args memory");
    }
}
JAVA

    "$JV" run Main one two >"$TMP_ROOT/jv-test-memory-args.out"

    [[ -f "$TMP_ROOT/app/.jv/state.json" ]] || fail "Expected .jv/state.json"
    [[ -f "$TMP_ROOT/app/.jv/runs.jsonl" ]] || fail "Expected .jv/runs.jsonl"
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"run": "java -cp bin Main one two"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"eventType":"memory_write"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"run":"java -cp bin Main one two"'
}

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
    assert_jsonl_event_count_at_least "$events" 5
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

test_run_memory_write_failure_preserves_success_exit() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("memory unavailable");
    }
}
JAVA
    touch .jv

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    if [[ $status -ne 0 ]]; then
        fail "Expected successful Java run to preserve exit 0 when memory write fails; got $status"
    fi
    assert_contains "$output" "memory unavailable"
    assert_contains "$output" "Warning:"
}

test_run_state_write_failure_warns_even_when_run_log_can_append() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src" "$TMP_ROOT/app/.jv/state.json"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("partial memory");
    }
}
JAVA

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    if [[ $status -ne 0 ]]; then
        fail "Expected successful Java run to preserve exit 0 when state write fails; got $status"
    fi
    assert_contains "$output" "partial memory"
    assert_contains "$output" "Warning: Could not write JV memory"
}

test_run_escapes_control_characters_in_memory_json() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src" "$TMP_ROOT/app/lib" "$TMP_ROOT/empty"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("escaped memory");
    }
}
JAVA
    jar cf "$TMP_ROOT/app/lib/control
name.jar" -C "$TMP_ROOT/empty" .

    "$JV" run >"$TMP_ROOT/jv-test-escaped-memory.out"

    if command -v jq >/dev/null 2>&1; then
        jq -e . "$TMP_ROOT/app/.jv/state.json" >/dev/null
    else
        assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" 'control\nname.jar'
    fi
}

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
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"eventType":"failure"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"reason":"compile_failed"'
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}

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
    "$JV" run >"$TMP_ROOT/jv-test-failing-run.out" 2>&1
    local status=$?
    set -e

    if [[ $status -ne 7 ]]; then
        fail "Expected Java exit status 7; got $status"
    fi
    assert_contains "$(cat "$TMP_ROOT/jv-test-failing-run.out")" "failing main"
    assert_not_exists "$TMP_ROOT/app/.jv/state.json"
}

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

test_remember_main_resolves_ambiguity() {
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

    "$JV" remember main Tool
    local output
    output="$("$JV" run)"

    assert_contains "$output" "Main class: Tool"
    assert_contains "$output" "tool"

    "$JV" forget main
    set +e
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e
    if [[ $status -eq 0 ]]; then
        fail "Expected run to become ambiguous after forget"
    fi
    assert_contains "$output" "Multiple main classes found"
}

test_remember_main_rejects_stale_source_memory() {
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

    "$JV" remember main Tool
    "$JV" run >"$TMP_ROOT/jv-test-remember-stale-first-run.out"
    rm src/Tool.java

    set +e
    local output
    output="$("$JV" run 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected stale remembered main to fail"
    fi
    assert_contains "$output" ".jv/state.json"
    assert_contains "$output" "stale"
    assert_contains "$output" "App"
    assert_not_contains "$output" "tool"
}

test_run_with_args_ignores_remembered_main_when_ambiguous() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/App.java <<'JAVA'
public class App {
    public static void main(String[] args) {
        System.out.println("app ran");
    }
}
JAVA
    cat > src/Tool.java <<'JAVA'
public class Tool {
    public static void main(String[] args) {
        System.out.println("tool ran");
    }
}
JAVA

    "$JV" remember main Tool

    set +e
    local output
    output="$("$JV" run arg 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected ambiguous run with args to fail despite remembered main"
    fi
    assert_contains "$output" "Multiple main classes found"
    assert_contains "$output" "App"
    assert_contains "$output" "Tool"
    assert_not_contains "$output" "tool ran"
}

test_run_with_args_infers_single_main_despite_stale_memory() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("main ran");
        for (String arg : args) {
            System.out.println("arg: " + arg);
        }
    }
}
JAVA

    "$JV" remember main OldMain

    local output
    output="$("$JV" run arg)"

    assert_contains "$output" "Main class: Main"
    assert_contains "$output" "main ran"
    assert_contains "$output" "arg: arg"
    assert_not_contains "$output" "stale"
}

test_remember_main_rejects_extra_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    set +e
    local output
    output="$("$JV" remember main Tool Extra 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected remember main with extra args to fail"
    fi
    assert_contains "$output" "Usage: jv remember main <MainClass>"
}

test_remember_main_rejects_invalid_class_names() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    "$JV" remember main App

    local invalid
    for invalid in 'Bad\Name' 'Bad Name'; do
        set +e
        local output
        output="$("$JV" remember main "$invalid" 2>&1)"
        local status=$?
        set -e

        if [[ $status -eq 0 ]]; then
            fail "Expected invalid remembered main class to fail: $invalid"
        fi
        assert_contains "$output" "Invalid main class"
    done

    [[ -f "$TMP_ROOT/app/.jv/state.json" ]] || fail "Expected valid state to remain"
    if command -v jq >/dev/null 2>&1; then
        jq -e . "$TMP_ROOT/app/.jv/state.json" >/dev/null
    fi
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"rememberedMainClass": "App"'
    assert_not_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" 'Bad'
}

test_forget_main_rejects_extra_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    set +e
    local output
    output="$("$JV" forget main Extra 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected forget main with extra args to fail"
    fi
    assert_contains "$output" "Usage: jv forget main"
}

test_maven_explain_and_run() {
    if ! command -v mvn >/dev/null 2>&1; then
        echo "Skipping Maven test; mvn not installed"
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
        System.out.println("maven app");
        System.out.println("args count: " + args.length);
        for (String arg : args) {
            System.out.println("arg: " + arg);
        }
    }
}
JAVA

    local output
    output="$("$JV" explain)"
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "Source roots: src/main/java"
    assert_contains "$output" "Main class: com.example.App"
    assert_contains "$output" "Build path: mvn compile"

    output="$("$JV" explain com.example.App one two)"
    assert_contains "$output" "Run path: mvn -q exec:java -Dexec.mainClass=com.example.App -Dexec.args=\"one two\""

    output="$("$JV" run)"
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "maven app"

    output="$("$JV" run one two)"
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "Run path: mvn -q exec:java -Dexec.mainClass=com.example.App -Dexec.args=\"one two\""
    assert_contains "$output" "args count: 2"
    assert_contains "$output" "arg: one"
    assert_contains "$output" "arg: two"

    output="$("$JV" run com.example.App one two)"
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "Run path: mvn -q exec:java -Dexec.mainClass=com.example.App -Dexec.args=\"one two\""
    assert_contains "$output" "args count: 2"
    assert_contains "$output" "arg: one"
    assert_contains "$output" "arg: two"
}

test_doctor_reports_project_state() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("doctor");
    }
}
JAVA

    local output
    output="$("$JV" doctor)"

    assert_contains "$output" "JV doctor"
    assert_contains "$output" "Shape: plain-java"
    assert_contains "$output" "Source roots: src"
    assert_contains "$output" "Main class candidates:"
    assert_contains "$output" "Main"
    assert_contains "$output" "java:"
    assert_contains "$output" "javac:"
}

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

test_doctor_survives_broken_tool_versions() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src" "$TMP_ROOT/fake-bin"
    cd "$TMP_ROOT/app"
    cat > src/Main.java <<'JAVA'
public class Main {
    public static void main(String[] args) {
        System.out.println("broken versions");
    }
}
JAVA
    cat > "$TMP_ROOT/fake-bin/java" <<'SH'
#!/usr/bin/env bash
echo "broken java version"
exit 42
SH
    cat > "$TMP_ROOT/fake-bin/javac" <<'SH'
#!/usr/bin/env bash
echo "broken javac version"
exit 42
SH
    chmod +x "$TMP_ROOT/fake-bin/java" "$TMP_ROOT/fake-bin/javac"

    local output
    output="$(PATH="$TMP_ROOT/fake-bin:$PATH" "$JV" doctor)"

    assert_contains "$output" "Tools:"
    assert_contains "$output" "java:"
    assert_contains "$output" "javac:"
    assert_contains "$output" "required"
}

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

test_doctor_rejects_extra_args() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"

    set +e
    local output
    output="$("$JV" doctor extra 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected doctor with extra args to fail"
    fi
    assert_contains "$output" "Usage: jv doctor"
}

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

test_help_lists_diagnostics_commands() {
    local output
    output="$("$JV" help)"

    assert_contains "$output" "explain [ClassName]           Show the detected build/run plan without running"
    assert_contains "$output" "doctor                       Inspect Java project state and possible entrypoints"
    assert_contains "$output" "run [ClassName] [args...]     Infer, explain, compile, and run"
    assert_contains "$output" "remember main <ClassName>      Remember a preferred main class in .jv/"
    assert_contains "$output" "forget main                    Remove the remembered main class"
    assert_contains "$output" ".jv/          Generated JV memory after successful runs"
    assert_not_contains "$output" ".jv/          Generated JV memory after explain/run"
    assert_contains "$output" "jv run                                # Infer, explain, compile, and run"
    assert_contains "$output" "jv explain                            # Show what JV would do"
    assert_contains "$output" "jv doctor                             # Inspect detected project state"
}

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

test_explain_reports_missing_maven_source_root_as_blocker() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app"
    cd "$TMP_ROOT/app"
    cat > pom.xml <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>missing-source</artifactId>
  <version>1.0.0</version>
</project>
XML

    set +e
    local output
    output="$("$JV" explain 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected explain with missing Maven source root to fail"
    fi
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "Source roots: src/main/java"
    assert_contains "$output" "Reason: pom.xml found in project root"
    assert_contains "$output" "Blocker: Source root not found: src/main/java"
    assert_not_contains "$output" "Error:"
}

test_explain_reports_empty_src_as_blocker() {
    setup_tmp
    mkdir -p "$TMP_ROOT/app/src"
    cd "$TMP_ROOT/app"

    set +e
    local output
    output="$("$JV" explain 2>&1)"
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected explain with empty src to fail"
    fi
    assert_contains "$output" "JV detected: plain Java project"
    assert_contains "$output" "Source roots: src"
    assert_contains "$output" "Reason: src directory found"
    assert_contains "$output" "Blocker: No main class found in src. Pass one explicitly: jv run <MainClass>"
    assert_not_contains "$output" "Error:"
}

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

main() {
    test_create_compile_run_packaged_project
    test_create_does_not_write_jv_json
    test_run_infers_single_plain_main_class
    test_run_infers_single_plain_main_class_with_args
    test_run_refuses_multiple_plain_main_classes
    test_run_writes_blocker_event_without_execution_start
    test_run_prints_agent_failure_for_ambiguous_main
    test_run_refuses_multiple_plain_main_classes_with_non_candidate_token
    test_run_ignores_commented_plain_main_signatures
    test_run_ignores_block_commented_plain_main_signatures
    test_run_infers_main_with_spaced_array_signature
    test_run_infers_main_with_name_array_signature
    test_run_infers_main_with_no_space_varargs_signature
    test_run_ignores_block_comment_marker_inside_string_literal
    test_run_detects_main_after_block_comment_with_quote_before_terminator
    test_explain_prints_plan_without_compiling
    test_explain_prints_plain_run_args
    test_explain_shows_reasons_and_no_side_effects
    test_explain_reports_missing_maven_source_root_as_blocker
    test_explain_reports_empty_src_as_blocker
    test_run_and_explain_share_plain_plan_output
    test_run_writes_jv_memory
    test_run_writes_plain_args_to_jv_memory
    test_run_writes_agent_grade_event_schema
    test_run_appends_v1_events_after_legacy_and_corrupt_lines
    test_run_state_contains_planner_reasons
    test_run_memory_write_failure_preserves_success_exit
    test_run_state_write_failure_warns_even_when_run_log_can_append
    test_run_escapes_control_characters_in_memory_json
    test_run_prints_agent_failure_for_plain_compile_error
    test_run_failure_does_not_write_success_memory
    test_run_failure_writes_execution_result_event_without_success_memory
    test_remember_main_resolves_ambiguity
    test_remember_main_rejects_stale_source_memory
    test_run_with_args_ignores_remembered_main_when_ambiguous
    test_run_with_args_infers_single_main_despite_stale_memory
    test_remember_main_rejects_extra_args
    test_remember_main_rejects_invalid_class_names
    test_forget_main_rejects_extra_args
    test_maven_explain_and_run
    test_doctor_reports_project_state
    test_doctor_reports_tool_versions
    test_doctor_survives_broken_tool_versions
    test_doctor_reports_plan_reasons_memory_and_blockers
    test_doctor_rejects_extra_args
    test_doctor_reports_ambiguous_main_as_blocker
    test_doctor_reports_unknown_project_as_blocker
    test_help_lists_diagnostics_commands
    echo "All tests passed"
}

main "$@"
