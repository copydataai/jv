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
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"executed"'
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

    output="$("$JV" run)"
    assert_contains "$output" "JV detected: Maven project"
    assert_contains "$output" "maven app"

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
    assert_contains "$output" "Project shape: plain-java"
    assert_contains "$output" "Source roots: src"
    assert_contains "$output" "Main class candidates:"
    assert_contains "$output" "Main"
    assert_contains "$output" "java:"
    assert_contains "$output" "javac:"
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

test_help_lists_diagnostics_commands() {
    local output
    output="$("$JV" help)"

    assert_contains "$output" "doctor"
    assert_contains "$output" "explain"
}

main() {
    test_create_compile_run_packaged_project
    test_create_does_not_write_jv_json
    test_run_infers_single_plain_main_class
    test_run_refuses_multiple_plain_main_classes
    test_run_ignores_commented_plain_main_signatures
    test_run_ignores_block_commented_plain_main_signatures
    test_run_infers_main_with_spaced_array_signature
    test_run_infers_main_with_name_array_signature
    test_run_infers_main_with_no_space_varargs_signature
    test_run_ignores_block_comment_marker_inside_string_literal
    test_run_detects_main_after_block_comment_with_quote_before_terminator
    test_explain_prints_plan_without_compiling
    test_run_writes_jv_memory
    test_run_memory_write_failure_preserves_success_exit
    test_run_escapes_control_characters_in_memory_json
    test_run_failure_does_not_write_success_memory
    test_remember_main_resolves_ambiguity
    test_remember_main_rejects_stale_source_memory
    test_remember_main_rejects_extra_args
    test_remember_main_rejects_invalid_class_names
    test_forget_main_rejects_extra_args
    test_maven_explain_and_run
    test_doctor_reports_project_state
    test_doctor_rejects_extra_args
    test_help_lists_diagnostics_commands
    echo "All tests passed"
}

main "$@"
