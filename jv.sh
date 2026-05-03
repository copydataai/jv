#!/bin/bash

set -eo pipefail

# JV - Simple Java Wrapper for Daily Tasks
# Version: 0.1.0
JV_VERSION="0.1.0"

# Initialize colors as empty
RED=''
GREEN=''
YELLOW=''
BLUE=''
NC=''

# Only set colors if output is to a terminal
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi


# Configuration
JV_DIR=".jv"
JV_STATE="$JV_DIR/state.json"
JV_RUNS="$JV_DIR/runs.jsonl"
SRC_DIR="src"
BIN_DIR="bin"
LIB_DIR="lib"
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
PLAN_MAIN_CANDIDATE_REASONS=()
PLAN_REASONS=()
PLAN_WARNINGS=()
PLAN_BLOCKERS=()
PLAN_REMEMBERED_MAIN=""
PLAN_MEMORY_STATE=""
PLAN_LAST_SUCCESSFUL_MAIN=""
PLAN_LAST_RUN_SUMMARY=""
PLAN_RUN_ARGS=()
EVENT_RUN_ID=""
EVENT_SEQUENCE=0
EVENT_COMMAND_NAME=""
EVENT_COMMAND_ARGV=()
RETRY_RUN_ARGS=()

# Helper functions
error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

json_escape() {
    local byte
    while read -r -a bytes; do
        for byte in "${bytes[@]}"; do
            case "$byte" in
                08) printf '\\b' ;;
                09) printf '\\t' ;;
                0a) printf '\\n' ;;
                0c) printf '\\f' ;;
                0d) printf '\\r' ;;
                22) printf '%s' "\\\"" ;;
                5c) printf '%s' "\\\\" ;;
                00|01|02|03|04|05|06|07|0b|0e|0f|1?) printf '\\u00%s' "$byte" ;;
                *) printf '%b' "\\x$byte" ;;
            esac
        done
    done < <(printf '%s' "$1" | LC_ALL=C od -An -tx1 -v)
}

json_array_from_lines() {
    local item
    local first=1
    printf '['
    for item in "$@"; do
        if [[ $first -eq 0 ]]; then
            printf ','
        fi
        printf '"%s"' "$(json_escape "$item")"
        first=0
    done
    printf ']'
}

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

valid_main_class_name() {
    local main_class="$1"
    [[ "$main_class" =~ ^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$ ]]
}

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
    PLAN_MAIN_CANDIDATE_REASONS=()
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

ensure_jv_dir() {
    mkdir -p "$JV_DIR"
}

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

emit_memory_write_event() {
    local target="$1"
    local status="$2"
    local classification="$3"
    local payload
    payload="{\"target\":\"$(json_escape "$target")\",\"status\":\"$(json_escape "$status")\",\"classification\":\"$(json_escape "$classification")\",\"rememberedMainClass\":\"$(json_escape "$PLAN_REMEMBERED_MAIN")\",\"lastSuccessfulMainClass\":\"$(json_escape "$PLAN_SELECTED_MAIN")\",\"lastPlan\":{\"build\":\"$(json_escape "$PLAN_BUILD_DISPLAY")\",\"run\":\"$(json_escape "$PLAN_RUN_DISPLAY")\"}}"
    append_event_json "memory_write" "Memory write $status for $target" "$payload"
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
    local payload

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "$retry")"
    payload="{\"event\":\"$(json_escape "$event")\",\"action\":\"$(json_escape "$action")\",\"reason\":\"$(json_escape "$reason")\",\"command\":\"$(json_escape "$command")\",\"message\":\"$(json_escape "$message")\",\"nextAction\":\"$(json_escape "$next_action")\",\"retryCommand\":\"$(json_escape "$retry")\",\"exitCode\":$exit_code}"
    append_event_json "failure" "$message" "$payload"
}

append_warning_event() {
    local reason="$1"
    local retry="$2"
    local message
    local next_action
    local payload

    message="$(failure_message_for_reason "$reason")"
    next_action="$(next_action_for_reason "$reason" "$retry")"
    payload="{\"event\":\"warning\",\"action\":\"memory\",\"reason\":\"$(json_escape "$reason")\",\"command\":\"\",\"message\":\"$(json_escape "$message")\",\"nextAction\":\"$(json_escape "$next_action")\",\"retryCommand\":\"$(json_escape "$retry")\"}"
    append_event_json "warning" "$message" "$payload"
}

write_state() {
    local shape="$1"
    local main_class="$2"
    local build_command="$3"
    local run_command="$4"
    local remembered

    remembered="$(remembered_main_class)"

    ensure_jv_dir || return
    {
        cat <<EOF
{
  "schemaVersion": 1,
EOF
        if [[ -n "$remembered" ]] && valid_main_class_name "$remembered"; then
            printf '  "rememberedMainClass": "%s",\n' "$(json_escape "$remembered")"
        fi
        cat <<EOF
  "projectShape": "$(json_escape "$shape")",
  "lastSuccessfulMainClass": "$(json_escape "$main_class")",
  "lastPlan": {
    "build": "$(json_escape "$build_command")",
    "run": "$(json_escape "$run_command")"
  },
  "planner": {
    "shapeReason": "$(json_escape "$PLAN_SHAPE_REASON")",
    "sourceRoot": "$(json_escape "$PLAN_SOURCE_ROOT")",
    "selectedMainSource": "$(json_escape "$PLAN_SELECTED_MAIN_SOURCE")",
    "reasons": $(json_array_from_lines "${PLAN_REASONS[@]}"),
    "warnings": $(json_array_from_lines "${PLAN_WARNINGS[@]}"),
    "blockers": $(json_array_from_lines "${PLAN_BLOCKERS[@]}")
  }
}
EOF
    } > "$JV_STATE"
}

append_run_event() {
    local event="$1"
    local detail="$2"

    append_event_json "execution_result" "$detail" "{\"phase\":\"run\",\"status\":\"success\",\"exitCode\":0,\"classification\":\"legacy-$event\",\"step\":{\"kind\":\"legacy\",\"display\":\"$(json_escape "$detail")\"}}"
}

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

remembered_main_class() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"rememberedMainClass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}

read_last_successful_main() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"lastSuccessfulMainClass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}

read_last_plan_run() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"run"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
}

state_has_run_memory() {
    [[ -f "$JV_STATE" ]] || return 1
    grep -Eq '"(projectShape|lastSuccessfulMainClass|lastPlan)"' "$JV_STATE"
}

remember_main() {
    local main_class="$1"
    local escaped_main
    local tmp_state

    [[ -n "$main_class" ]] || error "Usage: jv remember main <MainClass>"
    if ! valid_main_class_name "$main_class"; then
        error "Invalid main class: $main_class\nUsage: jv remember main <MainClass>"
    fi
    escaped_main="$(json_escape "$main_class")"
    ensure_jv_dir

    if state_has_run_memory; then
        tmp_state="$JV_STATE.tmp.$$"
        awk -v remembered_line="  \"rememberedMainClass\": \"$escaped_main\"," '
            /^[[:space:]]*"rememberedMainClass"[[:space:]]*:/ { next }
            /^[[:space:]]*"schemaVersion"[[:space:]]*:/ {
                print
                print remembered_line
                next
            }
            { print }
        ' "$JV_STATE" > "$tmp_state"
        mv "$tmp_state" "$JV_STATE"
    else
        cat > "$JV_STATE" <<EOF
{
  "schemaVersion": 1,
  "rememberedMainClass": "$escaped_main"
}
EOF
    fi

    PLAN_REMEMBERED_MAIN="$main_class"
    PLAN_SELECTED_MAIN="$main_class"
    emit_memory_write_event "$JV_STATE" "success" "remember-main" || warn "Could not write JV events to $JV_RUNS"
    success "Remembered main class: $main_class"
}

forget_main() {
    local tmp_state

    if state_has_run_memory; then
        tmp_state="$JV_STATE.tmp.$$"
        sed '/^[[:space:]]*"rememberedMainClass"[[:space:]]*:/d' "$JV_STATE" > "$tmp_state"
        mv "$tmp_state" "$JV_STATE"
    elif [[ -f "$JV_STATE" ]]; then
        rm -f "$JV_STATE"
    fi

    PLAN_REMEMBERED_MAIN=""
    PLAN_SELECTED_MAIN=""
    emit_memory_write_event "$JV_STATE" "success" "forget-main" || warn "Could not write JV events to $JV_RUNS"
    success "Forgot remembered main class"
}

# Check if Java is installed
check_java() {
    if ! command -v java &> /dev/null; then
        error "Java is not installed. Please install Java to use jv."
    fi
    if ! command -v javac &> /dev/null; then
        error "javac is not installed. Please install JDK to use jv."
    fi
}

tool_version() {
    local tool="$1"
    local output
    case "$tool" in
        java|javac|mvn)
            output="$("$tool" -version 2>&1 || true)"
            printf '%s\n' "${output%%$'\n'*}"
            ;;
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

# Show help
show_help() {
    echo -e "${GREEN}JV${NC} - Simple Java Wrapper for Daily Tasks"
    echo -e ""
    echo -e "${BLUE}Usage:${NC}"
    echo -e "  jv <command> [arguments]"
    echo -e ""
    echo -e "${BLUE}Commands:${NC}"
    echo -e "  ${GREEN}create${NC} <project-name> [package]  Create a new Java project (mkdir + init)"
    echo -e "  ${GREEN}init${NC}                          Initialize project in current directory"
    echo -e "  ${GREEN}explain${NC} [ClassName]           Show the detected build/run plan without running"
    echo -e "  ${GREEN}doctor${NC} [--json]              Inspect Java project state and possible entrypoints"
    echo -e "  ${GREEN}history${NC} [--limit N] [--failures] [--json]  Show recent JV run history"
    echo -e "  ${GREEN}events${NC} [--limit N] [--failures] [--json]   Alias for history"
    echo -e "  ${GREEN}retry${NC} [--dry-run] [--json]     Retry the latest failed or blocked JV run"
    echo -e "  ${GREEN}fix${NC} [--json]                  Show a repair brief for the latest failed run"
    echo -e "  ${GREEN}watch${NC} [ClassName] [args...]   Re-run when Java source files change"
    echo -e "  ${GREEN}compile${NC} [ClassName]           Compile Java files (all or specific)"
    echo -e "  ${GREEN}run${NC} [ClassName] [args...]     Infer, explain, compile, and run"
    echo -e "  ${GREEN}remember${NC} main <ClassName>      Remember a preferred main class in .jv/"
    echo -e "  ${GREEN}forget${NC} main                    Remove the remembered main class"
    echo -e "  ${GREEN}clean${NC}                         Remove all compiled .class files"
    echo -e "  ${GREEN}help${NC}                          Show this help message"
    echo -e "  ${GREEN}version${NC}                       Show jv and Java version"
    echo -e ""
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  jv create my-assignment              # Create new project"
    echo -e "  jv create my-app ie.atu.sw           # Create with package"
    echo -e "  jv init                               # Initialize in current dir"
    echo -e "  jv run                                # Infer, explain, compile, and run"
    echo -e "  jv explain                            # Show what JV would do"
    echo -e "  jv doctor                             # Inspect detected project state"
    echo -e "  jv history                            # Show recent JV runs"
    echo -e "  jv retry                              # Retry latest failed JV run"
    echo -e "  jv fix                                # Show latest failure repair brief"
    echo -e "  jv watch                              # Re-run on Java source changes"
    echo -e "  jv compile                            # Compile all Java files"
    echo -e "  jv run ie.atu.sw.Main                # Run main class"
    echo -e "  jv run ie.atu.sw.Main arg1 arg2      # Run with arguments"
    echo -e "  jv clean                              # Clean build artifacts"
    echo -e ""
    echo -e "${BLUE}Project Structure:${NC}"
    echo -e "  src/          Source files (.java)"
    echo -e "  bin/          Compiled files (.class)"
    echo -e "  lib/          External JARs (auto-detected)"
    echo -e "  .jv/          Generated JV memory after successful runs"
    echo -e ""
    echo -e "${BLUE}Learn more:${NC} https://github.com/copydataai/jv"
}

# Show version
show_version() {
    echo -e "jv $JV_VERSION (bash)"
    if command -v java >/dev/null 2>&1; then
        java -version 2>&1 | head -n 1
    else
        warn "Java is not installed"
    fi
}

# Initialize project structure
init_project() {
    local project_name="${1:-my-project}"
    local package_name="${2:-}"
    
    info "Initializing Java project..."
    
    # Create directories
    if [[ -d "$SRC_DIR" && "$(ls -A "$SRC_DIR" 2>/dev/null)" ]]; then
        warn "Source directory already contains files; leaving existing source untouched"
    else
        mkdir -p "$SRC_DIR"
    fi
    mkdir -p "$BIN_DIR" "$LIB_DIR"
    
    # Create sample Main.java if src is empty
    if [[ ! "$(ls -A "$SRC_DIR" 2>/dev/null)" ]]; then
        if [[ -n "$package_name" ]]; then
            # Create package directory structure
            local package_path="${package_name//.//}"
            mkdir -p "$SRC_DIR/$package_path"
            
            # Create Main.java with package declaration
            cat > "$SRC_DIR/$package_path/Main.java" << EOF
package $package_name;

public class Main {
    public static void main(String[] args) {
        System.out.println("Hello from JV!");
        System.out.println("Package: $package_name");
        
        if (args.length > 0) {
            System.out.println("Arguments:");
            for (String arg : args) {
                System.out.println("  - " + arg);
            }
        }
    }
}
EOF
            success "Created $package_name.Main in $SRC_DIR/$package_path/"
        else
            # Create simple Main.java without package
            cat > "$SRC_DIR/Main.java" << 'EOF'
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello from JV!");
        
        if (args.length > 0) {
            System.out.println("Arguments:");
            for (String arg : args) {
                System.out.println("  - " + arg);
            }
        }
    }
}
EOF
            success "Created sample Main.java"
        fi
    fi
    
    success "Project initialized successfully"
    echo -e ""
    info "Directory structure:"
    echo -e "  $SRC_DIR/  - Place your .java files here"
    echo -e "  $BIN_DIR/  - Compiled .class files (auto-generated)"
    echo -e "  $LIB_DIR/  - External .jar files"
}

# Create new project (mkdir + init)
create_project() {
    local project_name="$1"
    local package_name="$2"
    
    if [[ -z "$project_name" ]]; then
        error "Project name required. Usage: jv create <project-name> [package-name]"
    fi
    
    if [[ -d "$project_name" ]]; then
        error "Directory '$project_name' already exists"
    fi
    
    # If package name not provided as argument, ask interactively
    if [[ -z "$package_name" ]]; then
        echo -e ""
        echo -e "${BLUE}Do you want to create a package structure?${NC}"
        echo -e "  Examples: ie.atu.sw, com.example, org.myapp"
        echo -e "  Press Enter to skip (no package)"
        read -r -p "Package name: " package_name
        
        # Trim whitespace
        package_name="$(echo -e "${package_name}" | xargs)"
    fi
    
    info "Creating project: $project_name"
    if [[ -n "$package_name" ]]; then
        info "With package: $package_name"
    fi
    
    mkdir -p "$project_name"
    cd "$project_name"
    
    init_project "$project_name" "$package_name"
    
    echo -e ""
    success "Project created successfully!"
    info "Next steps:"
    echo -e "  cd $project_name"
    echo -e "  jv compile"
    if [[ -n "$package_name" ]]; then
        echo -e "  jv run $package_name.Main"
    else
        echo -e "  jv run Main"
    fi
}

# Build classpath from lib directory
build_classpath() {
    local classpath="$BIN_DIR"
    
    if [[ -d "$LIB_DIR" ]] && compgen -G "$LIB_DIR/*.jar" >/dev/null; then
        for jar in "$LIB_DIR"/*.jar; do
            classpath="$classpath:$jar"
        done
    fi
    
    echo -e "$classpath"
}

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
    local main_signature_regex='public[[:space:]]+static[[:space:]]+void[[:space:]]+main[[:space:]]*\([[:space:]]*String[[:space:]]*(\[\]|\.\.\.)?[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(\[\])?[[:space:]]*\)'
    [[ -d "$source_root" ]] || return 0

    while IFS= read -r -d '' file; do
        if awk '
            function neutralize_strings(text,    i, ch, prev, masked, in_string) {
                masked = ""
                prev = ""
                in_string = 0
                for (i = 1; i <= length(text); i++) {
                    ch = substr(text, i, 1)
                    if (in_string) {
                        if (ch == "\"" && prev != "\\") {
                            in_string = 0
                        }
                        masked = masked " "
                    } else if (ch == "\"") {
                        in_string = 1
                        masked = masked " "
                    } else {
                        masked = masked ch
                    }
                    if (ch == "\\" && prev == "\\") {
                        prev = ""
                    } else {
                        prev = ch
                    }
                }
                return masked
            }

            {
                line = $0
                visible = ""
                while (length(line) > 0) {
                    if (in_block_comment) {
                        end = index(line, "*/")
                        if (end == 0) {
                            line = ""
                        } else {
                            line = substr(line, end + 2)
                            in_block_comment = 0
                        }
                    } else {
                        search_line = neutralize_strings(line)
                        line_comment = index(search_line, "//")
                        block_comment = index(search_line, "/*")
                        if (line_comment > 0 && (block_comment == 0 || line_comment < block_comment)) {
                            visible = visible substr(line, 1, line_comment - 1)
                            line = ""
                        } else if (block_comment > 0) {
                            visible = visible substr(line, 1, block_comment - 1)
                            line = substr(line, block_comment + 2)
                            in_block_comment = 1
                        } else {
                            visible = visible line
                            line = ""
                        }
                    }
                }
                print visible
            }
        ' "$file" | grep -Eq "$main_signature_regex"; then
            class_name_for_file "$file"
        fi
    done < <(find "$source_root" -name "*.java" -print0 2>/dev/null | sort -z)
}

plan_main_candidates_csv() {
    local candidates=""
    local main_class

    for main_class in "${PLAN_MAIN_CANDIDATES[@]}"; do
        if [[ -n "$candidates" ]]; then
            candidates="$candidates, "
        fi
        candidates="$candidates$main_class"
    done

    printf '%s' "$candidates"
}

main_class_basename() {
    local main_class="$1"
    printf '%s' "${main_class##*.}"
}

normalized_project_name() {
    local name
    name="$(basename "$PWD")"
    printf '%s' "$name" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

normalized_class_name() {
    local name="$1"
    printf '%s' "$name" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

main_candidate_depth() {
    local main_class="$1"
    local dots="${main_class//[^.]}"
    printf '%s' "${#dots}"
}

main_candidate_reason() {
    local main_class="$1"
    local basename
    local normalized_project
    local normalized_class
    basename="$(main_class_basename "$main_class")"
    normalized_project="$(normalized_project_name)"
    normalized_class="$(normalized_class_name "$basename")"

    if [[ -n "$PLAN_LAST_SUCCESSFUL_MAIN" && "$main_class" == "$PLAN_LAST_SUCCESSFUL_MAIN" ]]; then
        printf 'last successful main in this project'
    elif [[ "$basename" == "Main" ]]; then
        printf 'conventional Java entrypoint'
    elif [[ "$basename" == *Application || "$basename" == *App ]]; then
        printf 'class name looks like an application entrypoint'
    elif [[ -n "$normalized_project" && "$normalized_class" == "$normalized_project" ]]; then
        printf 'class name matches the project directory'
    elif [[ "$basename" =~ (Test|Tests|Tool|Util|Utils|Helper|Example|Scratch)$ ]]; then
        printf 'utility or example-looking entrypoint'
    else
        printf 'detected public static main method'
    fi
}

main_candidate_score() {
    local main_class="$1"
    local basename
    local score=500
    basename="$(main_class_basename "$main_class")"

    if [[ -n "$PLAN_LAST_SUCCESSFUL_MAIN" && "$main_class" == "$PLAN_LAST_SUCCESSFUL_MAIN" ]]; then
        score=0
    elif [[ "$basename" == "Main" ]]; then
        score=10
    elif [[ "$basename" == *Application || "$basename" == *App ]]; then
        score=20
    elif [[ -n "$(normalized_project_name)" && "$(normalized_class_name "$basename")" == "$(normalized_project_name)" ]]; then
        score=30
    elif [[ "$basename" =~ (Test|Tests|Tool|Util|Utils|Helper|Example|Scratch)$ ]]; then
        score=900
    else
        score=100
    fi

    score=$((score + $(main_candidate_depth "$main_class")))
    printf '%s' "$score"
}

rank_main_candidates() {
    if [[ ${#PLAN_MAIN_CANDIDATES[@]} -lt 2 ]]; then
        if [[ ${#PLAN_MAIN_CANDIDATES[@]} -eq 1 ]]; then
            PLAN_MAIN_CANDIDATE_REASONS=("$(main_candidate_reason "${PLAN_MAIN_CANDIDATES[0]}")")
        fi
        return 0
    fi

    local rows=()
    local ranked=()
    local reasons=()
    local index=0
    local main_class
    local row
    local score original reason candidate

    for main_class in "${PLAN_MAIN_CANDIDATES[@]}"; do
        rows+=("$(main_candidate_score "$main_class")"$'\t'"$index"$'\t'"$main_class"$'\t'"$(main_candidate_reason "$main_class")")
        index=$((index + 1))
    done

    while IFS=$'\t' read -r score original candidate reason; do
        : "$score" "$original"
        ranked+=("$candidate")
        reasons+=("$reason")
    done < <(printf '%s\n' "${rows[@]}" | sort -n -k1,1 -k2,2)

    PLAN_MAIN_CANDIDATES=("${ranked[@]}")
    PLAN_MAIN_CANDIDATE_REASONS=("${reasons[@]}")
}

print_ranked_main_candidates() {
    local indent="${1:-}"
    local index
    local reason

    if [[ ${#PLAN_MAIN_CANDIDATES[@]} -eq 0 ]]; then
        printf '%snone\n' "$indent"
        return 0
    fi

    for index in "${!PLAN_MAIN_CANDIDATES[@]}"; do
        reason="${PLAN_MAIN_CANDIDATE_REASONS[$index]:-detected public static main method}"
        printf '%s%d. %s - %s\n' "$indent" "$((index + 1))" "${PLAN_MAIN_CANDIDATES[$index]}" "$reason"
    done
}

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
        local candidates
        candidates="$(plan_main_candidates_csv)"
        if [[ -n "$candidates" ]]; then
            plan_add_blocker "Remembered main class in $JV_STATE is stale: $PLAN_REMEMBERED_MAIN. Detected main classes: $candidates"
        else
            plan_add_blocker "Remembered main class in $JV_STATE is stale: $PLAN_REMEMBERED_MAIN. No main classes detected in $source_root"
        fi
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
            local candidates
            candidates="$(plan_main_candidates_csv)"
            plan_add_blocker "Multiple main classes found: $candidates. Pass one explicitly: jv run <MainClass>"
            ;;
    esac
}

print_plain_java_plan() {
    local source_root="$1"
    local class_name="$2"
    local run_args="${3:-}"
    local classpath
    local run_path
    classpath="$(build_classpath)"
    run_path="java -cp $classpath $class_name"

    if [[ -n "$run_args" ]]; then
        run_path="$run_path $run_args"
    fi

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
    echo "Run path: $run_path"
}

print_maven_plan() {
    local source_root="$1"
    local class_name="$2"
    local maven_args="${3:-}"
    local run_path="mvn -q exec:java -Dexec.mainClass=$class_name"

    if [[ -n "$maven_args" ]]; then
        run_path="$run_path -Dexec.args=\"$maven_args\""
    fi

    echo "JV detected: Maven project"
    echo "Source roots: $source_root"
    echo "Main class: $class_name"
    echo "Build path: mvn compile"
    echo "Run path: $run_path"
}

join_maven_args() {
    local joined=""
    local arg

    for arg in "$@"; do
        if [[ -n "$joined" ]]; then
            joined="$joined "
        fi
        joined="$joined$arg"
    done

    printf '%s' "$joined"
}

build_plan() {
    local source_root
    local class_name
    local run_args
    local main_class
    local requested_main=""
    local first_token
    local remaining_args=()

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

    local tool
    for tool in "${PLAN_REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            plan_add_blocker "Required tool missing: $tool"
        fi
    done

    source_root="$(source_root_for_shape "$PLAN_SHAPE")"
    PLAN_SOURCE_ROOT="$source_root"
    if [[ -n "$source_root" && -d "$source_root" ]]; then
        PLAN_SOURCE_ROOT_REASON="$source_root exists"
        plan_add_reason "$PLAN_SOURCE_ROOT_REASON"
    else
        PLAN_SOURCE_ROOT_REASON="$source_root missing"
        plan_add_blocker "Source root not found: $source_root"
        return 0
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
    rank_main_candidates

    first_token="${1:-}"
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

        if [[ -n "$requested_main" ]]; then
            plan_select_main_class "$requested_main" "$source_root"
        else
            PLAN_RUN_ARGS=("$first_token" "${remaining_args[@]}")
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
                    local candidates
                    candidates="$(plan_main_candidates_csv)"
                    plan_add_blocker "Multiple main classes found: $candidates. Pass one explicitly: jv run <MainClass>"
                    ;;
            esac
        fi
    else
        plan_select_main_class "$requested_main" "$source_root"
    fi

    class_name="$PLAN_SELECTED_MAIN"
    if [[ -z "$class_name" ]]; then
        return 0
    fi

    run_args="$(join_maven_args "${PLAN_RUN_ARGS[@]}")"

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

    return 0
}

print_plan_summary() {
    : "${PLAN_SHAPE_REASON}" "${PLAN_SOURCE_ROOT_REASON}" "${PLAN_SELECTED_MAIN_SOURCE}"
    : "${PLAN_BUILD_KIND}" "${PLAN_RUN_KIND}" "${PLAN_MEMORY_STATE}"
    : "${PLAN_LAST_SUCCESSFUL_MAIN}" "${PLAN_LAST_RUN_SUMMARY}"
    : "${PLAN_REQUIRED_TOOLS[@]}" "${PLAN_MAIN_CANDIDATES[@]}"
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
        if [[ ${#PLAN_MAIN_CANDIDATES[@]} -gt 1 ]]; then
            echo "Main class candidates:"
            print_ranked_main_candidates "  "
            echo "Run one now: jv run $(first_main_candidate)"
            echo "Make it the default: jv remember main $(first_main_candidate)"
        fi
    fi
}

explain_project() {
    build_plan "$@"
    print_plan_summary
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        return 1
    fi
}

print_doctor_report() {
    local item
    local requirement
    local tool_path
    local version

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
        if tool_is_required "$item"; then
            requirement="required"
        else
            requirement="optional"
        fi

        if command -v "$item" >/dev/null 2>&1; then
            tool_path="$(command -v "$item")"
            version="$(tool_version "$item")"
            if [[ -n "$version" ]]; then
                echo "    $item: $tool_path ($requirement) - $version"
            else
                echo "    $item: $tool_path ($requirement)"
            fi
        else
            echo "    $item: missing ($requirement)"
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
    print_ranked_main_candidates "  "

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

json_nullable_string() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "$value")"
    fi
}

plan_status_json_value() {
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        printf 'blocked'
    elif [[ ${#PLAN_WARNINGS[@]} -gt 0 ]]; then
        printf 'warn'
    else
        printf 'ok'
    fi
}

source_roots_json() {
    if [[ -z "$PLAN_SOURCE_ROOT" ]]; then
        printf '[]'
        return 0
    fi

    printf '[{"path":"%s","exists":%s,"role":"%s","reason":"%s"}]' \
        "$(json_escape "$PLAN_SOURCE_ROOT")" \
        "$(json_bool "$([[ -d "$PLAN_SOURCE_ROOT" ]] && printf true || printf false)")" \
        "$(json_escape "$PLAN_SHAPE-source")" \
        "$(json_escape "$PLAN_SOURCE_ROOT_REASON")"
}

tool_json_for_doctor() {
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

    printf '{"name":"%s","required":%s,"available":%s,"path":%s,"version":%s}' \
        "$(json_escape "$tool")" \
        "$(json_bool "$required")" \
        "$(json_bool "$available")" \
        "$(json_nullable_string "$path")" \
        "$(json_nullable_string "$version")"
}

tools_json_for_doctor() {
    printf '[%s,%s,%s]' "$(tool_json_for_doctor java)" "$(tool_json_for_doctor javac)" "$(tool_json_for_doctor mvn)"
}

doctor_next_action_json() {
    if [[ ${#PLAN_BLOCKERS[@]} -eq 0 ]]; then
        printf 'null'
        return 0
    fi

    local reason
    local retry
    reason="$(failure_reason_for_blocker "${PLAN_BLOCKERS[0]}")"
    retry="$(retry_command_for_current_run "${PLAN_RUN_ARGS[@]}")"
    printf '"%s"' "$(json_escape "$(next_action_for_reason "$reason" "$retry")")"
}

print_doctor_json_report() {
    local status
    status="$(plan_status_json_value)"

    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "command": %s,\n' "$(event_command_json)"
    printf '  "cwd": "%s",\n' "$(json_escape "$PWD")"
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    echo '  "project": {'
    printf '    "shape": "%s",\n' "$(json_escape "$PLAN_SHAPE")"
    printf '    "shapeReason": %s,\n' "$(json_nullable_string "$PLAN_SHAPE_REASON")"
    printf '    "sourceRoots": %s\n' "$(source_roots_json)"
    echo '  },'
    printf '  "tools": %s,\n' "$(tools_json_for_doctor)"
    echo '  "main": {'
    printf '    "selected": %s,\n' "$(json_nullable_string "$PLAN_SELECTED_MAIN")"
    printf '    "selectedSource": %s,\n' "$(json_nullable_string "$PLAN_SELECTED_MAIN_SOURCE")"
    printf '    "selectedReason": %s,\n' "$(json_nullable_string "$PLAN_SELECTED_MAIN_REASON")"
    printf '    "candidates": %s\n' "$(json_array_from_lines "${PLAN_MAIN_CANDIDATES[@]}")"
    echo '  },'
    echo '  "plan": {'
    echo '    "build": {'
    printf '      "kind": %s,\n' "$(json_nullable_string "$PLAN_BUILD_KIND")"
    printf '      "display": %s,\n' "$(json_nullable_string "$PLAN_BUILD_DISPLAY")"
    printf '      "runnable": %s\n' "$(json_bool "$([[ -n "$PLAN_BUILD_DISPLAY" && ${#PLAN_BLOCKERS[@]} -eq 0 ]] && printf true || printf false)")"
    echo '    },'
    echo '    "run": {'
    printf '      "kind": %s,\n' "$(json_nullable_string "$PLAN_RUN_KIND")"
    printf '      "display": %s,\n' "$(json_nullable_string "$PLAN_RUN_DISPLAY")"
    printf '      "args": %s,\n' "$(json_array_from_lines "${PLAN_RUN_ARGS[@]}")"
    printf '      "runnable": %s\n' "$(json_bool "$([[ -n "$PLAN_RUN_DISPLAY" && ${#PLAN_BLOCKERS[@]} -eq 0 ]] && printf true || printf false)")"
    echo '    }'
    echo '  },'
    echo '  "memory": {'
    printf '    "state": "%s",\n' "$(json_escape "$PLAN_MEMORY_STATE")"
    printf '    "statePath": "%s",\n' "$(json_escape "$JV_STATE")"
    printf '    "runsPath": "%s",\n' "$(json_escape "$JV_RUNS")"
    printf '    "rememberedMainClass": %s,\n' "$(json_nullable_string "$PLAN_REMEMBERED_MAIN")"
    printf '    "lastSuccessfulMainClass": %s,\n' "$(json_nullable_string "$PLAN_LAST_SUCCESSFUL_MAIN")"
    printf '    "lastRun": %s\n' "$(json_nullable_string "$PLAN_LAST_RUN_SUMMARY")"
    echo '  },'
    printf '  "reasons": %s,\n' "$(json_array_from_lines "${PLAN_REASONS[@]}")"
    printf '  "warnings": %s,\n' "$(json_array_from_lines "${PLAN_WARNINGS[@]}")"
    printf '  "blockers": %s,\n' "$(json_array_from_lines "${PLAN_BLOCKERS[@]}")"
    printf '  "nextAction": %s\n' "$(doctor_next_action_json)"
    echo "}"
}

doctor_project() {
    local json_mode="${1:-0}"

    build_plan
    if ! emit_environment_event || ! emit_plan_event; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        if ! emit_blockers_event; then
            warn "Could not write JV events to $JV_RUNS"
        fi
    fi
    if [[ "$json_mode" -eq 1 ]]; then
        print_doctor_json_report
        return 0
    fi
    print_doctor_report
}

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

    case "$command_text" in
        javac\ *) return 0 ;;
    esac

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
    printf 'success\tresult\t-\t-\t-\t%s\t%s\tExecuted %s\t-\n' "$main_class" "$detail" "$detail"
}

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
    local payload_event

    if ! grep -q '"schemaVersion"[[:space:]]*:' <<<"$line"; then
        return 1
    fi

    status="$(history_extract_json_string "status" "$line")"
    level="$(history_extract_json_string "level" "$line")"
    payload_event="$(history_extract_json_string "event" "$line")"
    reason="$(history_extract_json_string "classification" "$line")"
    event_type="$(history_extract_json_string "eventType" "$line")"
    timestamp="$(history_extract_json_string "timestamp" "$line")"
    run_id="$(history_extract_json_string "runId" "$line")"
    event_id="$(history_extract_json_string "eventId" "$line")"
    summary="$(history_extract_json_string "summary" "$line")"
    command_text="$(history_extract_argv_command "payload.step.argv" "$line")"

    if [[ -z "$command_text" ]]; then
        command_text="$(history_extract_json_string "display" "$line")"
    fi
    if [[ -z "$reason" ]]; then
        reason="$(history_extract_json_string "reason" "$line")"
    fi
    if [[ -z "$status" ]]; then
        if [[ "$event_type" == "failure" && "$payload_event" == "blocked" ]]; then
            status="blocked"
        elif [[ "$event_type" == "failure" ]]; then
            status="failure"
        elif [[ "$level" == "error" ]]; then
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
    [[ -n "$timestamp" ]] || timestamp="-"
    [[ -n "$run_id" ]] || run_id="-"
    [[ -n "$event_id" ]] || event_id="-"
    [[ -n "$main_class" ]] || main_class="-"
    [[ -n "$command_text" ]] || command_text="-"
    [[ -n "$summary" ]] || summary="-"
    [[ -n "$reason" ]] || reason="-"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$event_type" "$timestamp" "$run_id" "$event_id" "$main_class" "$command_text" "$summary" "$reason"
}

history_render_text_rows() {
    local empty_message="$1"
    shift
    local rows=("$@")
    local row
    local index=1
    local status event_type timestamp run_id event_id main_class command_text summary reason
    : "$event_type" "$timestamp" "$run_id" "$event_id" "$summary"

    echo "JV history"
    echo "Source: $JV_RUNS"
    echo ""

    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "$empty_message"
        return 0
    fi

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r status event_type timestamp run_id event_id main_class command_text summary reason <<<"$row"
        : "$timestamp" "$run_id" "$event_id" "$summary"
        [[ -n "$main_class" && "$main_class" != "-" ]] || main_class="-"
        [[ -n "$command_text" && "$command_text" != "-" ]] || command_text="-"
        printf '%d. %s  %s  %s\n' "$index" "$status" "$main_class" "$command_text"
        if [[ -n "$reason" && "$reason" != "-" ]]; then
            printf '   Reason: %s\n' "$reason"
        fi
        index=$((index + 1))
    done
}

history_json_value() {
    local value="$1"
    if [[ -z "$value" || "$value" == "-" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "$value")"
    fi
}

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

show_history() {
    local limit=10
    local failures_only=0
    local json_mode=0
    local arg
    local rows=()
    local line
    local normalized
    local empty_message
    local corrupt_count=0

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
        if [[ $json_mode -eq 1 ]]; then
            history_render_json_rows "$limit" "$failures_only" 0
            return 0
        fi
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
    done < "$JV_RUNS"

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

    if [[ ${#rows[@]} -gt "$limit" ]]; then
        rows=("${rows[@]:0:$limit}")
    fi

    if [[ $json_mode -eq 1 ]]; then
        history_render_json_rows "$limit" "$failures_only" "$corrupt_count" "${rows[@]}"
        return 0
    fi

    empty_message="No JV history entries found in $JV_RUNS."
    if [[ $failures_only -eq 1 ]]; then
        empty_message="No failed or blocked JV events found."
    fi
    history_render_text_rows "$empty_message" "${rows[@]}"
    if [[ $corrupt_count -eq 1 ]]; then
        echo ""
        echo "Warning: skipped 1 corrupt $JV_RUNS line"
    elif [[ $corrupt_count -gt 1 ]]; then
        echo ""
        echo "Warning: skipped $corrupt_count corrupt $JV_RUNS lines"
    fi
}

retry_render_empty_json() {
    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "source": "%s",\n' "$(json_escape "$JV_RUNS")"
    echo '  "found": false,'
    echo '  "reason": null,'
    echo '  "status": null,'
    echo '  "retryCommand": null,'
    echo '  "runId": null,'
    echo '  "eventType": null'
    echo "}"
}

retry_render_selection_json() {
    local reason="$1"
    local status="$2"
    local retry_command="$3"
    local run_id="$4"
    local event_type="$5"

    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "source": "%s",\n' "$(json_escape "$JV_RUNS")"
    echo '  "found": true,'
    printf '  "reason": "%s",\n' "$(json_escape "$reason")"
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "retryCommand": "%s",\n' "$(json_escape "$retry_command")"
    printf '  "runId": "%s",\n' "$(json_escape "$run_id")"
    printf '  "eventType": "%s"\n' "$(json_escape "$event_type")"
    echo "}"
}

retry_find_latest_candidate() {
    [[ -f "$JV_RUNS" ]] || return 1

    local lines=()
    local line
    local index
    while IFS= read -r line; do
        lines+=("$line")
    done < "$JV_RUNS"

    for ((index=${#lines[@]} - 1; index >= 0; index--)); do
        line="${lines[$index]}"
        history_line_looks_like_json_object "$line" || continue

        local event_type
        local payload_event
        local reason
        local retry_command
        local run_id
        local status

        event_type="$(history_extract_json_string "eventType" "$line")"
        [[ "$event_type" == "failure" ]] || continue

        retry_command="$(history_extract_json_string "retryCommand" "$line")"
        [[ -n "$retry_command" ]] || continue

        payload_event="$(history_extract_json_string "event" "$line")"
        reason="$(history_extract_json_string "reason" "$line")"
        run_id="$(history_extract_json_string "runId" "$line")"
        case "$payload_event" in
            blocked) status="blocked" ;;
            failed) status="failure" ;;
            *) status="$(history_extract_json_string "status" "$line")" ;;
        esac
        [[ -n "$status" ]] || status="failure"
        [[ -n "$reason" ]] || reason="-"
        [[ -n "$run_id" ]] || run_id="-"

        printf '%s\t%s\t%s\t%s\t%s\n' "$reason" "$status" "$retry_command" "$run_id" "$event_type"
        return 0
    done

    return 1
}

retry_command_to_run_args() {
    local retry_command="$1"
    RETRY_RUN_ARGS=()

    local tokens=()
    local token
    # shellcheck disable=SC2206
    tokens=($retry_command)

    if [[ ${#tokens[@]} -lt 2 || "${tokens[0]}" != "jv" || "${tokens[1]}" != "run" ]]; then
        return 1
    fi

    for token in "${tokens[@]:2}"; do
        if [[ ! "$token" =~ ^[A-Za-z0-9._/@:+,=-]+$ ]]; then
            return 1
        fi
        RETRY_RUN_ARGS+=("$token")
    done
}

show_retry() {
    local dry_run=0
    local json_mode=0
    local arg
    local candidate
    local reason status retry_command run_id event_type

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                dry_run=1
                ;;
            --json)
                json_mode=1
                dry_run=1
                ;;
            *)
                error "Usage: jv retry [--dry-run] [--json]"
                ;;
        esac
        shift
    done

    if ! candidate="$(retry_find_latest_candidate)"; then
        if [[ $json_mode -eq 1 ]]; then
            retry_render_empty_json
        else
            echo "JV retry"
            echo "Source: $JV_RUNS"
            echo ""
            echo "No failed or blocked JV run found. Run \`jv history --failures\` to inspect failures."
        fi
        return 1
    fi

    IFS=$'\t' read -r reason status retry_command run_id event_type <<<"$candidate"

    if ! retry_command_to_run_args "$retry_command"; then
        if [[ $json_mode -eq 1 ]]; then
            retry_render_selection_json "$reason" "$status" "$retry_command" "$run_id" "$event_type"
        else
            echo "JV retry"
            echo "Source: $JV_RUNS"
            echo "Reason: $reason"
            echo "Retry command: $retry_command"
            echo ""
            echo "Unsafe retry command. JV retry only accepts stored commands shaped like: jv run [args...]"
        fi
        return 1
    fi

    if [[ $json_mode -eq 1 ]]; then
        retry_render_selection_json "$reason" "$status" "$retry_command" "$run_id" "$event_type"
        return 0
    fi

    echo "JV retry"
    echo "Source: $JV_RUNS"
    echo "Reason: $reason"
    echo "Retry command: $retry_command"
    echo ""

    if [[ $dry_run -eq 1 ]]; then
        return 0
    fi

    run_java "${RETRY_RUN_ARGS[@]}"
}

fix_repair_steps() {
    local reason="$1"

    case "$reason" in
        compile_failed|maven_compile_failed)
            printf '%s\n' \
                "Inspect the compiler errors above the JV failure block." \
                "Fix the Java source reported by javac or Maven." \
                "Run jv retry to rebuild and rerun the same JV command."
            ;;
        runtime_failed|maven_run_failed)
            printf '%s\n' \
                "Inspect the runtime exception or non-zero exit output above the JV failure block." \
                "Fix the Java logic or input arguments that caused the program to fail." \
                "Run jv retry to rerun the same JV command."
            ;;
        main_ambiguous)
            printf '%s\n' \
                "Choose one detected main class from the ranked candidate list." \
                "Run the selected class explicitly or remember it as the default." \
                "Run jv retry after the project state is unblocked."
            ;;
        main_missing|unknown_project|source_missing|tool_missing)
            printf '%s\n' \
                "Run jv doctor to inspect the current project state." \
                "Fix the blocker reported by JV." \
                "Run jv retry after the blocker is resolved."
            ;;
        *)
            printf '%s\n' \
                "Inspect the latest JV failure output." \
                "Fix the reported source or project state." \
                "Run jv retry to try the same JV command again."
            ;;
    esac
}

fix_render_empty_json() {
    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "source": "%s",\n' "$(json_escape "$JV_RUNS")"
    echo '  "found": false,'
    echo '  "reason": null,'
    echo '  "retryCommand": null,'
    echo '  "repairSteps": []'
    echo "}"
}

fix_render_json() {
    local reason="$1"
    local retry_command="$2"
    local run_id="$3"
    local event_type="$4"
    local steps=()
    local step

    while IFS= read -r step; do
        steps+=("$step")
    done < <(fix_repair_steps "$reason")

    echo "{"
    echo '  "schemaVersion": 1,'
    printf '  "source": "%s",\n' "$(json_escape "$JV_RUNS")"
    echo '  "found": true,'
    printf '  "reason": "%s",\n' "$(json_escape "$reason")"
    printf '  "retryCommand": "%s",\n' "$(json_escape "$retry_command")"
    printf '  "runId": "%s",\n' "$(json_escape "$run_id")"
    printf '  "eventType": "%s",\n' "$(json_escape "$event_type")"
    printf '  "repairSteps": %s\n' "$(json_array_from_lines "${steps[@]}")"
    echo "}"
}

show_fix() {
    local json_mode=0
    local arg
    local candidate
    local reason status retry_command run_id event_type
    local step
    : "$status"

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --json)
                json_mode=1
                ;;
            *)
                error "Usage: jv fix [--json]"
                ;;
        esac
        shift
    done

    if ! candidate="$(retry_find_latest_candidate)"; then
        if [[ $json_mode -eq 1 ]]; then
            fix_render_empty_json
        else
            echo "JV fix"
            echo "Source: $JV_RUNS"
            echo ""
            echo "No failed or blocked JV run found. Run \`jv history --failures\` to inspect failures."
        fi
        return 1
    fi

    IFS=$'\t' read -r reason status retry_command run_id event_type <<<"$candidate"

    if [[ $json_mode -eq 1 ]]; then
        fix_render_json "$reason" "$retry_command" "$run_id" "$event_type"
        return 0
    fi

    echo "JV fix"
    echo "Source: $JV_RUNS"
    echo "Reason: $reason"
    echo "Retry command: $retry_command"
    echo ""
    echo "Repair brief:"
    while IFS= read -r step; do
        echo "- $step"
    done < <(fix_repair_steps "$reason")
}

source_snapshot() {
    local source_root="$1"
    local file
    [[ -d "$source_root" ]] || return 0

    while IFS= read -r -d '' file; do
        printf '%s\t' "$file"
        cksum "$file"
    done < <(find "$source_root" -name "*.java" -print0 2>/dev/null | sort -z)
}

source_snapshot_checksum() {
    local source_root="$1"
    source_snapshot "$source_root" | cksum
}

watch_wait_for_change() {
    local source_root="$1"
    local previous="$2"
    local current

    while true; do
        sleep "${JV_WATCH_INTERVAL:-1}"
        current="$(source_snapshot_checksum "$source_root")"
        [[ "$current" != "$previous" ]] && return 0
    done
}

watch_project() {
    local args=("$@")
    local source_root
    local snapshot
    local retry

    trap 'echo ""; info "Stopped watch mode"; exit 130' INT TERM

    info "Watching Java sources. Press Ctrl-C to stop."
    run_java "${args[@]}" || true

    source_root="$PLAN_SOURCE_ROOT"
    if [[ -z "$source_root" || ! -d "$source_root" ]]; then
        error "No source root available to watch."
    fi

    snapshot="$(source_snapshot_checksum "$source_root")"
    info "Watch ready."

    while true; do
        watch_wait_for_change "$source_root" "$snapshot"
        echo ""
        retry="$(retry_command_for_current_run "${args[@]}")"
        info "Change detected. Re-running $retry..."
        if [[ "$PLAN_SHAPE" == "plain-java" ]]; then
            rm -rf "$BIN_DIR"
        fi
        run_java "${args[@]}" || true

        if [[ -n "$PLAN_SOURCE_ROOT" && -d "$PLAN_SOURCE_ROOT" ]]; then
            source_root="$PLAN_SOURCE_ROOT"
        fi
        snapshot="$(source_snapshot_checksum "$source_root")"
    done
}

# Compile Java files
compile_java() {
    check_java
    
    if [[ ! -d "$SRC_DIR" ]]; then
        error "Source directory '$SRC_DIR' not found. Run 'jv init' first."
    fi
    
    # Find Java files
    local java_files=()
    while IFS= read -r -d '' file; do
        java_files+=("$file")
    done < <(find "$SRC_DIR" -name "*.java" -print0 2>/dev/null)
    
    if [[ ${#java_files[@]} -eq 0 ]]; then
        error "No .java files found in $SRC_DIR"
    fi
    
    info "Compiling ${#java_files[@]} Java file(s)..."
    
    # Create bin directory if it doesn't exist
    mkdir -p "$BIN_DIR"
    
    # Build classpath
    local classpath
    classpath=$(build_classpath)
    
    javac -d "$BIN_DIR" -cp "$classpath" "${java_files[@]}"
}

compile_for_run_or_fail() {
    local retry
    local compile_status

    set +e
    compile_java
    compile_status=$?
    set -e

    if [[ $compile_status -ne 0 ]]; then
        retry="$(retry_command_for_current_run "$@")"
        print_failure_block "compile_failed" "compile" "$retry" "$compile_status" >&2
        append_failure_event "failed" "compile" "compile_failed" "$PLAN_BUILD_DISPLAY" "$retry" "$compile_status" || true
        return "$compile_status"
    fi

    success "Compilation successful"
}

compile_java_with_events() {
    local compile_display
    local compile_status

    compile_display="javac -d $BIN_DIR -cp $(build_classpath) <sources>"

    if ! emit_execution_start_event "compile" "javac" "$compile_display"; then
        warn "Could not write JV events to $JV_RUNS"
    fi

    set +e
    compile_java "$@"
    compile_status=$?
    set -e

    if [[ $compile_status -eq 0 ]]; then
        if ! emit_execution_result_event "compile" "javac" "$compile_display" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
        return 0
    fi

    if ! emit_execution_result_event "compile" "javac" "$compile_display" "failure" "$compile_status" "compile-failure"; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    return "$compile_status"
}

# Run Java program
run_java() {
    local class_name
    local args=()
    local shape

    build_plan "$@"
    if ! emit_environment_event || ! emit_plan_event; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        if ! emit_blockers_event; then
            warn "Could not write JV events to $JV_RUNS"
        fi
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

    shape="$PLAN_SHAPE"
    class_name="$PLAN_SELECTED_MAIN"
    args=("${PLAN_RUN_ARGS[@]}")

    print_plan_summary
    echo ""

    if [[ "$shape" == "maven" ]]; then
        if ! command -v mvn >/dev/null 2>&1; then
            error "Maven project detected from pom.xml, but mvn is not installed."
        fi

        local maven_args
        maven_args="$(join_maven_args "${args[@]}")"

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
            local retry
            retry="$(retry_command_for_current_run "$@")"
            print_failure_block "maven_compile_failed" "maven" "$retry" "$maven_status" >&2
            append_failure_event "failed" "maven" "maven_compile_failed" "$PLAN_BUILD_DISPLAY" "$retry" "$maven_status" || true
            return "$maven_status"
        fi
        if ! emit_execution_result_event "compile" "maven" "$PLAN_BUILD_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi

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
            local retry
            retry="$(retry_command_for_current_run "$@")"
            print_failure_block "maven_run_failed" "maven" "$retry" "$maven_status" >&2
            append_failure_event "failed" "maven" "maven_run_failed" "$PLAN_RUN_DISPLAY" "$retry" "$maven_status" || true
            return "$maven_status"
        fi
        if ! emit_execution_result_event "run" "maven" "$PLAN_RUN_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi

        if ! write_success_memory_from_plan; then
            print_warning_block "memory_write_failed" >&2
            append_warning_event "memory_write_failed" "$(retry_command_for_current_run "$@")" || true
        fi
        return 0
    fi

    if [[ "$shape" != "plain-java" ]]; then
        error "jv run currently supports plain Java and Maven projects only"
    fi
    
    check_java
    
    if [[ ! -d "$BIN_DIR" ]]; then
        warn "Output directory '$BIN_DIR' not found. Compiling first..."
        compile_for_run_or_fail "$@" || return "$?"
    fi
    
    # Check if class file exists (convert package.Class to package/Class.class)
    local class_file="${class_name//./\/}.class"
    if [[ ! -f "$BIN_DIR/$class_file" ]]; then
        warn "Class file not found. Compiling first..."
        compile_for_run_or_fail "$@" || return "$?"
    fi
    
    # Build classpath
    local classpath
    classpath=$(build_classpath)
    
    info "Running $class_name..."
    echo -e ""
    
    # Run the program
    if ! emit_execution_start_event "run" "java" "$PLAN_RUN_DISPLAY"; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    set +e
    java -cp "$classpath" "$class_name" "${args[@]}"
    local java_status=$?
    set -e

    if [[ $java_status -eq 0 ]]; then
        if ! emit_execution_result_event "run" "java" "$PLAN_RUN_DISPLAY" "success" 0 "completed"; then
            warn "Could not write JV events to $JV_RUNS"
        fi
        if ! write_success_memory_from_plan; then
            print_warning_block "memory_write_failed" >&2
            append_warning_event "memory_write_failed" "$(retry_command_for_current_run "$@")" || true
        fi
        return 0
    fi

    if ! emit_execution_result_event "run" "java" "$PLAN_RUN_DISPLAY" "failure" "$java_status" "runtime-failure"; then
        warn "Could not write JV events to $JV_RUNS"
    fi
    local retry
    retry="$(retry_command_for_current_run "$@")"
    print_failure_block "runtime_failed" "runtime" "$retry" "$java_status" >&2
    append_failure_event "failed" "runtime" "runtime_failed" "$PLAN_RUN_DISPLAY" "$retry" "$java_status" || true

    return "$java_status"
}

# Clean compiled files
clean_project() {
    if [[ ! -d "$BIN_DIR" ]]; then
        warn "Nothing to clean (no $BIN_DIR directory)"
        return 0
    fi
    
    info "Cleaning compiled files..."
    
    local count
    count=$(find "$BIN_DIR" -name "*.class" 2>/dev/null | wc -l)
    
    if [[ $count -eq 0 ]]; then
        warn "No .class files to remove"
    else
        find "$BIN_DIR" -name "*.class" -delete
        success "Removed $count .class file(s)"
    fi
}

# Main command router
main() {
    local command="${1:-help}"
    shift || true
    event_init "$command" "$@"
    
    case "$command" in
        create)
            create_project "$@"
            ;;
        init)
            init_project "${1:-$(basename "$PWD")}"
            ;;
        explain)
            explain_project "$@"
            ;;
        doctor)
            if [[ $# -eq 0 ]]; then
                doctor_project 0
            elif [[ $# -eq 1 && "${1:-}" == "--json" ]]; then
                doctor_project 1
            else
                error "Usage: jv doctor [--json]"
            fi
            ;;
        history)
            show_history "$@"
            ;;
        events)
            show_history "$@"
            ;;
        retry)
            show_retry "$@"
            ;;
        fix)
            show_fix "$@"
            ;;
        watch)
            watch_project "$@"
            ;;
        compile)
            compile_java_with_events "$@"
            ;;
        run)
            run_java "$@"
            ;;
        remember)
            if [[ $# -ne 2 || "${1:-}" != "main" ]]; then
                error "Usage: jv remember main <MainClass>"
            fi
            remember_main "$2"
            ;;
        forget)
            if [[ $# -ne 1 || "${1:-}" != "main" ]]; then
                error "Usage: jv forget main"
            fi
            forget_main
            ;;
        clean)
            clean_project
            ;;
        version|--version|-v)
            show_version
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command\nRun 'jv help' for usage information."
            ;;
    esac
}

# Run main function
main "$@"
