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
# shellcheck disable=SC2034 # Reserved for upcoming runner-memory state paths.
JV_STATE="$JV_DIR/state.json"
# shellcheck disable=SC2034 # Reserved for upcoming runner-memory run history paths.
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
    echo -e "  ${GREEN}compile${NC} [ClassName]           Compile Java files (all or specific)"
    echo -e "  ${GREEN}run${NC} <ClassName> [args...]     Run compiled Java program"
    echo -e "  ${GREEN}clean${NC}                         Remove all compiled .class files"
    echo -e "  ${GREEN}help${NC}                          Show this help message"
    echo -e "  ${GREEN}version${NC}                       Show jv and Java version"
    echo -e ""
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  jv create my-assignment              # Create new project"
    echo -e "  jv create my-app ie.atu.sw           # Create with package"
    echo -e "  jv init                               # Initialize in current dir"
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
        error "No Java project detected. Run 'jv init' first."
    fi

    if [[ "$shape" != "plain-java" ]]; then
        error "jv run currently supports plain Java projects only"
    fi

    class_name="$(select_main_class "$class_name" "$source_root")"
    
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
    
    echo "JV detected: plain Java project"
    echo "Source roots: $source_root"
    echo "Main class: $class_name"
    echo "Build path: javac -d $BIN_DIR -cp $(build_classpath) <sources>"
    echo "Run path: java -cp $(build_classpath) $class_name"
    echo ""
    info "Running $class_name..."
    echo -e ""
    
    # Run the program
    java -cp "$classpath" "$class_name" "${args[@]}"
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
        compile)
            compile_java "$@"
            ;;
        run)
            run_java "$@"
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
