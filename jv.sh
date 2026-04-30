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

valid_main_class_name() {
    local main_class="$1"
    [[ "$main_class" =~ ^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$ ]]
}

ensure_jv_dir() {
    mkdir -p "$JV_DIR"
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
  }
}
EOF
    } > "$JV_STATE"
}

append_run_event() {
    local event="$1"
    local detail="$2"

    ensure_jv_dir || return
    printf '{"event":"%s","detail":"%s"}\n' "$(json_escape "$event")" "$(json_escape "$detail")" >> "$JV_RUNS"
}

remembered_main_class() {
    [[ -f "$JV_STATE" ]] || return 0
    sed -n 's/^[[:space:]]*"rememberedMainClass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$JV_STATE" | head -n 1
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
    echo -e "  ${GREEN}explain${NC} [ClassName]           Show detected build/run plan without compiling"
    echo -e "  ${GREEN}doctor${NC}                       Show project diagnostics"
    echo -e "  ${GREEN}compile${NC} [ClassName]           Compile Java files (all or specific)"
    echo -e "  ${GREEN}run${NC} <ClassName> [args...]     Run compiled Java program"
    echo -e "  ${GREEN}remember${NC} main <MainClass>      Remember main class for ambiguous projects"
    echo -e "  ${GREEN}forget${NC} main                    Forget remembered main class"
    echo -e "  ${GREEN}clean${NC}                         Remove all compiled .class files"
    echo -e "  ${GREEN}help${NC}                          Show this help message"
    echo -e "  ${GREEN}version${NC}                       Show jv and Java version"
    echo -e ""
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  jv create my-assignment              # Create new project"
    echo -e "  jv create my-app ie.atu.sw           # Create with package"
    echo -e "  jv init                               # Initialize in current dir"
    echo -e "  jv explain                            # Show inferred build/run plan"
    echo -e "  jv doctor                             # Show project diagnostics"
    echo -e "  jv compile                            # Compile all Java files"
    echo -e "  jv run ie.atu.sw.Main                # Run main class"
    echo -e "  jv run ie.atu.sw.Main arg1 arg2      # Run with arguments"
    echo -e "  jv clean                              # Clean build artifacts"
    echo -e ""
    echo -e "${BLUE}Project Structure:${NC}"
    echo -e "  src/          Source files (.java)"
    echo -e "  bin/          Compiled files (.class)"
    echo -e "  lib/          External JARs (auto-detected)"
    echo -e "  .jv/          Generated JV memory after explain/run"
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

select_main_class() {
    local requested="$1"
    local source_root="$2"

    if [[ -n "$requested" ]]; then
        echo "$requested"
        return 0
    fi

    local mains=()
    local main_class
    while IFS= read -r main_class; do
        [[ -n "$main_class" ]] && mains+=("$main_class")
    done < <(find_main_classes "$source_root")

    local remembered
    remembered="$(remembered_main_class)"
    if [[ -n "$remembered" ]]; then
        if ! valid_main_class_name "$remembered"; then
            error "Invalid remembered main class in $JV_STATE: $remembered"
        fi

        for main_class in "${mains[@]}"; do
            if [[ "$main_class" == "$remembered" ]]; then
                echo "$remembered"
                return 0
            fi
        done

        echo "Remembered main class in $JV_STATE is stale: $remembered" >&2
        if [[ ${#mains[@]} -gt 0 ]]; then
            echo "Detected main classes:" >&2
            for main_class in "${mains[@]}"; do
                echo "  $main_class" >&2
            done
        else
            echo "No main classes detected in $source_root" >&2
        fi
        error "Forget or update remembered main class: jv forget main"
    fi

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
            error "No Java project detected. Checked for pom.xml and $SRC_DIR/."
            ;;
    esac
}

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
    local class_name="${1:-}"
    if [[ $# -gt 0 ]]; then
        shift
    fi
    local args=("$@")
    local shape
    local source_root
    shape="$(detect_project_shape)"
    source_root="$(source_root_for_shape "$shape")"
    
    if [[ "$shape" == "unknown" ]]; then
        error "No Java project detected. Checked for pom.xml and $SRC_DIR/."
    fi

    class_name="$(select_main_class "$class_name" "$source_root")"

    if [[ "$shape" == "maven" ]]; then
        if ! command -v mvn >/dev/null 2>&1; then
            error "Maven project detected from pom.xml, but mvn is not installed."
        fi

        local maven_args
        local run_command="mvn -q exec:java -Dexec.mainClass=$class_name"
        maven_args="$(join_maven_args "${args[@]}")"
        if [[ -n "$maven_args" ]]; then
            run_command="$run_command -Dexec.args=\"$maven_args\""
        fi

        print_maven_plan "$source_root" "$class_name" "$maven_args"
        echo ""

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

        local build_command="mvn compile"
        if ! write_state "$shape" "$class_name" "$build_command" "$run_command" || ! append_run_event "executed" "$run_command"; then
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
    
    print_plain_java_plan "$source_root" "$class_name"
    echo ""
    info "Running $class_name..."
    echo -e ""
    
    # Run the program
    set +e
    java -cp "$classpath" "$class_name" "${args[@]}"
    local java_status=$?
    set -e

    if [[ $java_status -eq 0 ]]; then
        local build_command="javac -d $BIN_DIR -cp $classpath <sources>"
        local run_command="java -cp $classpath $class_name"
        if ! write_state "$shape" "$class_name" "$build_command" "$run_command" || ! append_run_event "executed" "$run_command"; then
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
