# JV Runner Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first explainable JV runner core so `jv run` can infer, explain, compile, and run plain Java and Maven projects without requiring `jv.json`.

**Architecture:** Keep the first runner core in the tracked Bash CLI, `jv.sh`, because it is the currently installed entrypoint. Add focused shell functions for detection, model building, planning, explanation, execution, and generated `.jv/` memory. Add a shell test harness under `tests/` so behavior is covered before and after each runner change.

**Tech Stack:** Bash, POSIX-ish shell utilities, `javac`, `java`, optional `mvn`, temporary-directory integration tests.

---

## File Structure

- Create `tests/run-tests.sh`: a self-contained Bash integration test harness that creates temporary Java/Maven projects and runs `jv.sh` against them.
- Modify `jv.sh`: add the runner core while preserving existing `create`, `init`, `compile`, `clean`, `help`, and `version` behavior.
- Modify `.gitignore`: ignore generated `.jv/`, `bin/`, and Java `.class` files.
- Modify `README.md`: update the positioning and command examples after implementation.
- Modify `EXAMPLES.md`: replace `jv.json`-first examples with inference, `explain`, and `.jv/` memory examples.

## Task 1: Add Test Harness Baseline

**Files:**
- Create: `tests/run-tests.sh`

- [ ] **Step 1: Write the test harness with existing behavior tests**

Create `tests/run-tests.sh`:

```bash
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

assert_not_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        fail "Expected path not to exist: $path"
    fi
}

setup_tmp() {
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

    "$JV" create demo com.example >/tmp/jv-test-create.out
    cd demo

    local output
    output="$("$JV" run com.example.Main alpha beta)"

    assert_contains "$output" "Hello from JV!"
    assert_contains "$output" "Package: com.example"
    assert_contains "$output" "  - alpha"
    assert_contains "$output" "  - beta"
}

main() {
    test_create_compile_run_packaged_project
    echo "All tests passed"
}

main "$@"
```

- [ ] **Step 2: Make the harness executable**

Run:

```bash
chmod +x tests/run-tests.sh
```

- [ ] **Step 3: Run the baseline test**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 4: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add JV CLI integration harness"
```

## Task 2: Stop Creating `jv.json` By Default

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add a failing test that new projects do not create `jv.json`**

Append this function before `main()` in `tests/run-tests.sh`:

```bash
test_create_does_not_write_jv_json() {
    setup_tmp
    cd "$TMP_ROOT"

    "$JV" create demo >/tmp/jv-test-create-no-json.out

    assert_not_exists "$TMP_ROOT/demo/jv.json"
}
```

Update `main()`:

```bash
main() {
    test_create_compile_run_packaged_project
    test_create_does_not_write_jv_json
    echo "All tests passed"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL with:

```text
Expected path not to exist:
```

- [ ] **Step 3: Remove default `jv.json` creation from `init_project`**

In `jv.sh`, remove `JV_CONFIG="jv.json"` as a project standard and add:

```bash
JV_DIR=".jv"
JV_STATE="$JV_DIR/state.json"
JV_RUNS="$JV_DIR/runs.jsonl"
```

In `init_project()`, delete the block that checks for `jv.json` and the block that writes the JSON config. Keep directory and sample source creation. Add a guard that only avoids overwriting existing source:

```bash
if [[ -d "$SRC_DIR" && "$(ls -A "$SRC_DIR" 2>/dev/null)" ]]; then
    warn "Source directory already contains files; leaving existing source untouched"
else
    mkdir -p "$SRC_DIR"
fi
mkdir -p "$BIN_DIR" "$LIB_DIR"
```

Update help text to replace:

```text
jv.json       Project configuration
```

with:

```text
.jv/          Generated JV memory after explain/run
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
git commit -m "feat: stop creating jv config by default"
```

## Task 3: Detect Plain Java Projects And Main Classes

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add failing tests for inferred main classes and ambiguity**

Append before `main()`:

```bash
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
```

Update `main()`:

```bash
main() {
    test_create_compile_run_packaged_project
    test_create_does_not_write_jv_json
    test_run_infers_single_plain_main_class
    test_run_refuses_multiple_plain_main_classes
    echo "All tests passed"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `jv run` without an explicit class still requires `jv.json` or a class argument.

- [ ] **Step 3: Add detection and main-class helper functions**

Add these functions above `compile_java()` in `jv.sh`:

```bash
detect_project_shape() {
    if [[ -f "pom.xml" ]]; then
        echo "maven"
    elif [[ -d "$SRC_DIR" ]]; then
        echo "plain-java"
    else
        echo "unknown"
    fi
}

source_root_for_shape() {
    local shape="$1"
    case "$shape" in
        maven) echo "src/main/java" ;;
        plain-java) echo "$SRC_DIR" ;;
        *) echo "" ;;
    esac
}

package_for_file() {
    local file="$1"
    local package_name
    package_name=$(sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_.]*\)[[:space:]]*;[[:space:]]*$/\1/p' "$file" | head -n 1)
    echo "$package_name"
}

class_name_for_file() {
    local file="$1"
    local base
    local package_name
    base="$(basename "$file" .java)"
    package_name="$(package_for_file "$file")"
    if [[ -n "$package_name" ]]; then
        echo "$package_name.$base"
    else
        echo "$base"
    fi
}

find_main_classes() {
    local source_root="$1"
    [[ -d "$source_root" ]] || return 0

    while IFS= read -r -d '' file; do
        if grep -Eq 'public[[:space:]]+static[[:space:]]+void[[:space:]]+main[[:space:]]*\([[:space:]]*String(\[\]|[[:space:]]+\.\.\.)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\)' "$file"; then
            class_name_for_file "$file"
        fi
    done < <(find "$source_root" -name "*.java" -print0 2>/dev/null | sort -z)
}

select_main_class() {
    local requested="$1"
    local source_root="$2"

    if [[ -n "$requested" ]]; then
        echo "$requested"
        return 0
    fi

    local mains=()
    while IFS= read -r main_class; do
        [[ -n "$main_class" ]] && mains+=("$main_class")
    done < <(find_main_classes "$source_root")

    if [[ ${#mains[@]} -eq 1 ]]; then
        echo "${mains[0]}"
        return 0
    fi

    if [[ ${#mains[@]} -eq 0 ]]; then
        error "No main class found in $source_root. Pass one explicitly: jv run <MainClass>"
    fi

    echo "Multiple main classes found:" >&2
    for main_class in "${mains[@]}"; do
        echo "  $main_class" >&2
    done
    error "Pass one explicitly: jv run <MainClass>"
}
```

- [ ] **Step 4: Update `run_java()` to infer plain Java main class**

At the start of `run_java()`, after argument parsing, compute:

```bash
local shape
local source_root
shape="$(detect_project_shape)"
source_root="$(source_root_for_shape "$shape")"
```

Replace the old `jv.json` lookup with:

```bash
if [[ "$shape" == "unknown" ]]; then
    error "No Java project detected. Checked for pom.xml and src/."
fi

class_name="$(select_main_class "$class_name" "$source_root")"
```

Before running the program, print:

```bash
echo "JV detected: plain Java project"
echo "Source roots: $source_root"
echo "Main class: $class_name"
echo "Build path: javac -d $BIN_DIR -cp $(build_classpath) <sources>"
echo "Run path: java -cp $(build_classpath) $class_name"
echo ""
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
git commit -m "feat: infer plain Java main classes"
```

## Task 4: Add `jv explain`

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add a failing explain test**

Append before `main()`:

```bash
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
```

Update `main()` to call `test_explain_prints_plan_without_compiling`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL with unknown command `explain`.

- [ ] **Step 3: Add plan printing and explain command**

Add:

```bash
print_plain_java_plan() {
    local source_root="$1"
    local class_name="$2"
    local classpath
    classpath="$(build_classpath)"

    echo "JV detected: plain Java project"
    echo "Source roots: $source_root"
    if [[ -d "$LIB_DIR" ]]; then
        local jar_count
        jar_count=$(find "$LIB_DIR" -name "*.jar" 2>/dev/null | wc -l | xargs)
        echo "Libraries: $jar_count jars from $LIB_DIR/"
    else
        echo "Libraries: 0 jars from $LIB_DIR/"
    fi
    echo "Main class: $class_name"
    echo "Build path: javac -d $BIN_DIR -cp $classpath <sources>"
    echo "Run path: java -cp $classpath $class_name"
}

explain_project() {
    local requested_class="${1:-}"
    local shape
    local source_root
    local class_name

    shape="$(detect_project_shape)"
    source_root="$(source_root_for_shape "$shape")"

    case "$shape" in
        plain-java)
            class_name="$(select_main_class "$requested_class" "$source_root")"
            print_plain_java_plan "$source_root" "$class_name"
            ;;
        maven)
            class_name="$(select_main_class "$requested_class" "$source_root")"
            print_maven_plan "$source_root" "$class_name"
            ;;
        *)
            error "No Java project detected. Checked for pom.xml and src/."
            ;;
    esac
}
```

Add command routing:

```bash
explain)
    explain_project "$@"
    ;;
```

- [ ] **Step 4: Reuse `print_plain_java_plan` in `run_java()`**

Replace the inline explanation output from Task 3 with:

```bash
print_plain_java_plan "$source_root" "$class_name"
echo ""
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
git commit -m "feat: add explain command"
```

## Task 5: Add Generated `.jv/` Memory

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Add failing tests for generated memory**

Append before `main()`:

```bash
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

    "$JV" run >/tmp/jv-test-memory.out

    [[ -f "$TMP_ROOT/app/.jv/state.json" ]] || fail "Expected .jv/state.json"
    [[ -f "$TMP_ROOT/app/.jv/runs.jsonl" ]] || fail "Expected .jv/runs.jsonl"
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"projectShape": "plain-java"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/state.json")" '"lastSuccessfulMainClass": "Main"'
    assert_contains "$(cat "$TMP_ROOT/app/.jv/runs.jsonl")" '"event":"executed"'
}
```

Update `main()` to call `test_run_writes_jv_memory`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL because `.jv/state.json` does not exist.

- [ ] **Step 3: Add memory helper functions**

Add to `jv.sh`:

```bash
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_jv_dir() {
    mkdir -p "$JV_DIR"
}

write_state() {
    local shape="$1"
    local main_class="$2"
    local build_command="$3"
    local run_command="$4"

    ensure_jv_dir
    cat > "$JV_STATE" <<EOF
{
  "schemaVersion": 1,
  "projectShape": "$(json_escape "$shape")",
  "lastSuccessfulMainClass": "$(json_escape "$main_class")",
  "lastPlan": {
    "build": "$(json_escape "$build_command")",
    "run": "$(json_escape "$run_command")"
  }
}
EOF
}

append_run_event() {
    local event="$1"
    local detail="$2"

    ensure_jv_dir
    printf '{"event":"%s","detail":"%s"}\n' "$(json_escape "$event")" "$(json_escape "$detail")" >> "$JV_RUNS"
}
```

- [ ] **Step 4: Write memory after successful plain Java run**

After `java -cp "$classpath" "$class_name" "${args[@]}"` succeeds in `run_java()`, write:

```bash
local build_command="javac -d $BIN_DIR -cp $classpath <sources>"
local run_command="java -cp $classpath $class_name"
write_state "$shape" "$class_name" "$build_command" "$run_command"
append_run_event "executed" "$run_command"
```

Because `set -e` exits on failed `java`, this only writes successful memory.

- [ ] **Step 5: Ignore generated memory and Java build output**

Append to `.gitignore`:

```gitignore
.jv/
bin/
*.class
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
git add .gitignore jv.sh tests/run-tests.sh
git commit -m "feat: write generated JV memory"
```

## Task 6: Add `remember`, `forget`, And Remembered Main Selection

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add failing tests for remembered main class**

Append before `main()`:

```bash
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
```

Update `main()` to call `test_remember_main_resolves_ambiguity`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL with unknown command `remember`.

- [ ] **Step 3: Add remembered main helpers**

Add:

```bash
remembered_main_class() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"rememberedMainClass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}

remember_main() {
    local main_class="$1"
    [[ -n "$main_class" ]] || error "Usage: jv remember main <MainClass>"
    ensure_jv_dir
    cat > "$JV_STATE" <<EOF
{
  "schemaVersion": 1,
  "rememberedMainClass": "$(json_escape "$main_class")"
}
EOF
    success "Remembered main class: $main_class"
}

forget_main() {
    if [[ -f "$JV_STATE" ]]; then
        rm -f "$JV_STATE"
    fi
    success "Forgot remembered main class"
}
```

- [ ] **Step 4: Use remembered main in `select_main_class()`**

In `select_main_class()`, after the requested-class check, add:

```bash
local remembered
remembered="$(remembered_main_class)"
if [[ -n "$remembered" ]]; then
    echo "$remembered"
    return 0
fi
```

- [ ] **Step 5: Add command routing**

Add to `main()`:

```bash
remember)
    if [[ "${1:-}" != "main" ]]; then
        error "Usage: jv remember main <MainClass>"
    fi
    shift
    remember_main "${1:-}"
    ;;
forget)
    if [[ "${1:-}" != "main" ]]; then
        error "Usage: jv forget main"
    fi
    forget_main
    ;;
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
git commit -m "feat: remember main class choices"
```

## Task 7: Add Maven Detection, Explanation, And Delegated Run

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add Maven tests that skip when Maven is unavailable**

Append before `main()`:

```bash
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
}
```

Update `main()` to call `test_maven_explain_and_run`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL in Maven projects because `run_java()` still uses the plain Java path.

- [ ] **Step 3: Add Maven plan printing**

Add:

```bash
print_maven_plan() {
    local source_root="$1"
    local class_name="$2"

    echo "JV detected: Maven project"
    echo "Source roots: $source_root"
    echo "Main class: $class_name"
    echo "Build path: mvn compile"
    echo "Run path: mvn -q exec:java -Dexec.mainClass=$class_name"
}
```

- [ ] **Step 4: Add Maven execution path**

In `run_java()`, after selecting `class_name`, branch:

```bash
if [[ "$shape" == "maven" ]]; then
    if ! command -v mvn >/dev/null 2>&1; then
        error "Maven project detected from pom.xml, but mvn is not installed."
    fi
    print_maven_plan "$source_root" "$class_name"
    echo ""
    mvn compile
    mvn -q exec:java -Dexec.mainClass="$class_name"
    write_state "$shape" "$class_name" "mvn compile" "mvn -q exec:java -Dexec.mainClass=$class_name"
    append_run_event "executed" "mvn -q exec:java -Dexec.mainClass=$class_name"
    return 0
fi
```

Leave the existing plain Java path under the branch.

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
git commit -m "feat: delegate Maven run plans"
```

## Task 8: Add `doctor` Diagnostics

**Files:**
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Add failing doctor test**

Append before `main()`:

```bash
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
```

Update `main()` to call `test_doctor_reports_project_state`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
tests/run-tests.sh
```

Expected: FAIL with unknown command `doctor`.

- [ ] **Step 3: Add doctor implementation**

Add:

```bash
doctor_project() {
    local shape
    local source_root
    shape="$(detect_project_shape)"
    source_root="$(source_root_for_shape "$shape")"

    echo "JV doctor"
    echo "Project shape: $shape"
    if [[ -n "$source_root" ]]; then
        echo "Source roots: $source_root"
    else
        echo "Source roots: none detected"
    fi

    echo "Tools:"
    if command -v java >/dev/null 2>&1; then
        echo "  java: $(command -v java)"
    else
        echo "  java: missing"
    fi
    if command -v javac >/dev/null 2>&1; then
        echo "  javac: $(command -v javac)"
    else
        echo "  javac: missing"
    fi
    if command -v mvn >/dev/null 2>&1; then
        echo "  mvn: $(command -v mvn)"
    else
        echo "  mvn: missing"
    fi

    echo "Main class candidates:"
    if [[ -n "$source_root" && -d "$source_root" ]]; then
        local found=0
        while IFS= read -r main_class; do
            found=1
            echo "  $main_class"
        done < <(find_main_classes "$source_root")
        if [[ $found -eq 0 ]]; then
            echo "  none"
        fi
    else
        echo "  none"
    fi
}
```

Add command routing:

```bash
doctor)
    doctor_project
    ;;
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
git commit -m "feat: add doctor diagnostics"
```

## Task 9: Update Docs For Runner Core

**Files:**
- Modify: `README.md`
- Modify: `EXAMPLES.md`
- Modify: `jv.sh`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Update help text**

In `show_help()` in `jv.sh`, update the command list to include:

```text
  explain [ClassName]               Show the detected build/run plan without running
  doctor                            Inspect Java project state and possible entrypoints
  remember main <ClassName>         Remember a preferred main class in .jv/
  forget main                       Remove the remembered main class
```

Update examples to show:

```text
  jv run                            # Infer, explain, compile, and run
  jv explain                        # Show what JV would do
  jv doctor                         # Inspect detected project state
```

- [ ] **Step 2: Update README positioning**

Change the top description to:

```markdown
**Java middleware that turns hidden IDE/project state into one reliable action: build and run the latest code correctly.**
```

Replace the “What is JV?” first paragraph with:

```markdown
JV is an explainable Java runner. It detects whether a project is plain Java or Maven, finds the source roots and main class candidates, shows the build/run plan, then runs the latest code through the correct toolchain.
```

Add a short `.jv/` section:

```markdown
### Generated JV Memory

JV does not require a hand-written config file for normal projects. Source files and build tools are truth; `.jv/` is generated memory. JV writes `.jv/state.json` and `.jv/runs.jsonl` after successful runs so humans and coding agents can inspect what JV detected and executed.
```

- [ ] **Step 3: Update examples**

In `EXAMPLES.md`, add an early example:

````markdown
## Explain Before Running

```bash
jv explain
jv run
```

`jv explain` prints the same plan `jv run` will execute without compiling or running the program.
````

Add an ambiguity example:

````markdown
## Multiple Main Classes

```bash
jv doctor
jv run com.example.App
jv remember main com.example.App
jv run
```
````

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
git add README.md EXAMPLES.md jv.sh tests/run-tests.sh
git commit -m "docs: document runner core workflow"
```

## Task 10: Final Verification

**Files:**
- No code changes expected unless verification finds a bug.

- [ ] **Step 1: Run full CLI tests**

Run:

```bash
tests/run-tests.sh
```

Expected:

```text
All tests passed
```

- [ ] **Step 2: Run docs lint if docs dependencies are installed**

Run:

```bash
cd docs && pnpm lint
```

Expected: PASS. If it fails only on existing Biome formatting in `docs/app/*.tsx`, either format those files in a separate docs-format commit or record the pre-existing lint failure in the final handoff.

- [ ] **Step 3: Run docs build if docs dependencies are installed**

Run:

```bash
cd docs && pnpm build
```

Expected: PASS. Next.js may update `docs/tsconfig.json`; if it does, review and either commit the required Next.js config change separately or restore it if unrelated.

- [ ] **Step 4: Check git status**

Run:

```bash
git status --short
```

Expected: only intentional changes remain, or a clean worktree except for pre-existing untracked `cli/`.

- [ ] **Step 5: Commit any verification fixes**

If verification changes `docs/tsconfig.json` and the change is required for Next.js 16, commit that exact file:

```bash
git add docs/tsconfig.json
git commit -m "fix: stabilize runner core verification"
```

If a runner bug is found instead, fix the specific affected implementation and test files, then stage those exact files explicitly. If no fixes were needed, do not create an empty commit.

## Self-Review

- Spec coverage: The plan covers plain Java detection, Maven delegation, explain, doctor, `.jv/` generated memory, no required `jv.json`, remembered main class choices, explicit ambiguity handling, docs, and verification.
- Scope: The plan intentionally does not implement Gradle, IDE metadata, dependency resolution beyond `lib/*.jar`, or a Java rewrite. Those are v1 non-goals in the spec.
- Type and naming consistency: Bash function names are stable across tasks: `detect_project_shape`, `source_root_for_shape`, `find_main_classes`, `select_main_class`, `print_plain_java_plan`, `print_maven_plan`, `explain_project`, `doctor_project`, `write_state`, `append_run_event`, `remember_main`, and `forget_main`.
- Placeholder scan: No implementation step depends on unspecified behavior; each code step includes concrete commands or shell snippets.
