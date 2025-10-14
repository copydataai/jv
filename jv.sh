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
JV_CONFIG="jv.json"
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
    echo -e "${BLUE} done ${NC}"
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
    echo -e "  ${GREEN}create${NC} <project-name>         Create a new Java project (mkdir + init)"
    echo -e "  ${GREEN}init${NC}                          Initialize project in current directory"
    echo -e "  ${GREEN}compile${NC} [ClassName]           Compile Java files (all or specific)"
    echo -e "  ${GREEN}run${NC} <ClassName> [args...]     Run compiled Java program"
    echo -e "  ${GREEN}clean${NC}                         Remove all compiled .class files"
    echo -e "  ${GREEN}help${NC}                          Show this help message"
    echo -e "  ${GREEN}version${NC}                       Show jv and Java version"
    echo -e ""
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  jv create my-assignment              # Create new project"
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
    echo -e "  jv.json       Project configuration"
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
    
    if [[ -f "$JV_CONFIG" ]]; then
        warn "Project already initialized (jv.json exists)"
        return 0
    fi
    
    info "Initializing Java project..."
    
    # Create directories
    mkdir -p "$SRC_DIR" "$BIN_DIR" "$LIB_DIR"
    
    # Create jv.json config
    cat > "$JV_CONFIG" << EOF
{
  "name": "$project_name",
  "version": "1.0.0",
  "mainClass": "",
  "sourceDir": "src",
  "outputDir": "bin",
  "libDir": "lib"
}
EOF
    
    # Create sample Main.java if src is empty
    if [[ ! "$(ls -A $SRC_DIR 2>/dev/null)" ]]; then
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
    
    if [[ -z "$project_name" ]]; then
        error "Project name required. Usage: jv create <project-name>"
    fi
    
    if [[ -d "$project_name" ]]; then
        error "Directory '$project_name' already exists"
    fi
    
    info "Creating project: $project_name"
    mkdir -p "$project_name"
    cd "$project_name"
    
    init_project "$project_name"
    
    echo -e ""
    success "Project created successfully!"
    info "Next steps:"
    echo -e "  cd $project_name"
    echo -e "  jv compile"
    echo -e "  jv run Main"
}

# Build classpath from lib directory
build_classpath() {
    local classpath="$BIN_DIR"
    
    if [[ -d "$LIB_DIR" ]] && [[ "$(ls -A $LIB_DIR/*.jar 2>/dev/null)" ]]; then
        for jar in "$LIB_DIR"/*.jar; do
            classpath="$classpath:$jar"
        done
    fi
    
    echo -e "$classpath"
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
    local class_name="$1"
    shift || true
    local args=("$@")
    
    if [[ -z "$class_name" ]]; then
        error "Class name required. Usage: jv run <ClassName> [args...]"
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
