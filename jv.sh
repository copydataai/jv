#!/bin/bash

set -eo pipefail

# JV - Simple Java Wrapper for Daily Tasks
# Version: 0.1.0

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
            printf ', '
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
        return 1
    fi
    write_state "$PLAN_SHAPE" "$PLAN_SELECTED_MAIN" "$PLAN_BUILD_DISPLAY" "$PLAN_RUN_DISPLAY" || return 1
    append_run_event "executed" "$PLAN_RUN_DISPLAY" || return 1
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
    echo -e "  ${GREEN}doctor${NC}                       Inspect Java project state and possible entrypoints"
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
    echo -e "jv version 0.1.0"
    java -version 2>&1 | head -n 1
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

doctor_project() {
    build_plan
    print_doctor_report
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
    
    # Compile
    if javac -d "$BIN_DIR" -cp "$classpath" "${java_files[@]}" 2>&1; then
        success "Compilation successful"
    else
        error "Compilation failed"
    fi
}

# Run Java program
run_java() {
    local class_name
    local args=()
    local shape

    build_plan "$@"
    if [[ ${#PLAN_BLOCKERS[@]} -gt 0 ]]; then
        print_plan_summary >&2
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

        set +e
        mvn compile
        local maven_status=$?
        set -e
        if [[ $maven_status -ne 0 ]]; then
            return "$maven_status"
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
            return "$maven_status"
        fi

        if ! write_success_memory_from_plan; then
            warn "Could not write JV memory to $JV_DIR/"
        fi
        return 0
    fi

    if [[ "$shape" != "plain-java" ]]; then
        error "jv run currently supports plain Java and Maven projects only"
    fi
    
    check_java
    
    if [[ ! -d "$BIN_DIR" ]]; then
        warn "Output directory '$BIN_DIR' not found. Compiling first..."
        compile_java
    fi
    
    # Check if class file exists (convert package.Class to package/Class.class)
    local class_file="${class_name//./\/}.class"
    if [[ ! -f "$BIN_DIR/$class_file" ]]; then
        warn "Class file not found. Compiling first..."
        compile_java
    fi
    
    # Build classpath
    local classpath
    classpath=$(build_classpath)
    
    info "Running $class_name..."
    echo -e ""
    
    # Run the program
    set +e
    java -cp "$classpath" "$class_name" "${args[@]}"
    local java_status=$?
    set -e

    if [[ $java_status -eq 0 ]]; then
        if ! write_success_memory_from_plan; then
            warn "Could not write JV memory to $JV_DIR/"
        fi
    fi

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
            if [[ $# -ne 0 ]]; then
                error "Usage: jv doctor"
            fi
            doctor_project
            ;;
        compile)
            compile_java "$@"
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
        version)
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
