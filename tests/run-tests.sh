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

    "$JV" create demo com.example >"$TMP_ROOT/jv-test-create.out"
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
