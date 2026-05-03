<div align="center">
  <img src="jv.png" alt="JV Logo" width="200"/>
  
  # JV
  
  **Java middleware that turns hidden IDE/project state into one reliable action: build and run the latest code correctly.**
  
  [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
  [![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
  
  *An alternative to Maven, Gradle, and Ant for simple projects*
  
</div>

---

## ⚡ What is JV?

JV is an explainable Java runner. It detects whether a project is plain Java or Maven, finds the source roots and main class candidates, shows the build/run plan, then runs the latest code through the correct toolchain.

### Why JV?

- **⚡ Fast Setup** - Get started in under 1 minute
- **🎯 Zero Configuration** - Convention over configuration
- **📦 Simple Dependencies** - Just drop JARs in `lib/`
- **🧑‍🎓 Student Friendly** - No steep learning curve

### The Problem

As a Computer Science student, many courses require Eclipse or complex build tools like Maven and Gradle. But these tools are:
- **Overkill** for simple assignments
- **Time-consuming** to set up
- **Complex** with steep learning curves
- **Verbose** with XML or DSL configuration files

### The Solution

JV provides a simple CLI wrapper around `javac` and `java` that handles:
- Project structure creation
- Compilation with proper classpaths
- Running programs with arguments
- Managing external JAR dependencies

**No configuration files. No XML. No DSL. Just code.**

---

## 🚀 Quick Start

### Installation

```bash
# Quick install (recommended)
curl -fsSL https://raw.githubusercontent.com/copydataai/jv/main/install.sh | bash

# Choose a custom install location
JV_INSTALL_DIR="$HOME/bin" bash install.sh

# Or manual installation
git clone https://github.com/copydataai/jv.git
cd jv
chmod +x jv.sh
mkdir -p "$HOME/.local/bin"
cp jv.sh "$HOME/.local/bin/jv"
```

### Basic Usage

```bash
# Create a new project
jv create my-assignment

# Create with package structure
jv create my-assignment ie.atu.sw

# Infer, compile, and run
cd my-assignment
jv run

# Add external library
cp professor-library.jar lib/

# Compile with dependencies
jv compile

# Clean build artifacts
jv clean
```

---

## 📚 Commands

| Command | Description |
|---------|-------------|
| `jv create <name> [package]` | Create new project with optional package structure |
| `jv init` | Initialize project in current directory |
| `jv compile [ClassName]` | Compile all or specific Java files |
| `jv run [ClassName] [args...]` | Infer, explain, compile, and run the latest code |
| `jv explain [ClassName]` | Show the detected build/run plan without running |
| `jv doctor [--json]` | Inspect Java project state and possible entrypoints |
| `jv history [--limit N] [--failures] [--json]` | Show recent JV run history |
| `jv events [--limit N] [--failures] [--json]` | Alias for `jv history` |
| `jv retry [--dry-run] [--json]` | Retry the latest failed or blocked JV run |
| `jv fix [--json]` | Show a repair brief for the latest failed run |
| `jv watch [ClassName] [args...]` | Re-run when Java source files change |
| `jv remember main <ClassName>` | Remember a preferred main class in `.jv/` |
| `jv forget main` | Remove the remembered main class |
| `jv clean` | Remove all `.class` files |
| `jv version` / `jv --version` | Show JV and Java version information |
| `jv help` | Show usage and available commands |

---

### Inspect The Plan

`jv doctor` shows the same planner model that powers `jv run` and `jv explain`: project shape, source roots, tool availability, selected main class, reasons, warnings, blockers, and `.jv/` memory status.

Use `jv doctor --json` for the same project health model as machine-readable JSON.

---

### Generated JV Memory

JV does not require a hand-written config file for normal projects. Source files and build tools are truth; `.jv/` is generated memory. JV writes `.jv/state.json` and `.jv/runs.jsonl` after successful runs so humans and coding agents can inspect what JV detected and executed.

Use `jv history` to inspect that run log without reading `.jv/runs.jsonl` directly:

```bash
jv history
jv history --failures
jv history --json
```

### Agent-Friendly Failures

When `jv run` is blocked or a build/run step fails, JV keeps the original tool output visible and adds a stable failure block:

```text
JV failure
Reason: compile_failed
Action: compile
Message: javac failed while compiling the selected plain Java project.
Next action: Fix the compiler errors above, then retry the same JV command.
Retry command: jv run
Exit code: 1
```

Agents can use the stable `Reason`, `Next action`, and `Retry command` lines for repair loops. JV also records blocked and failed run attempts in `.jv/runs.jsonl` when the memory directory is writable.

Use `jv retry` after fixing source code to rerun the latest failed or blocked JV run. `jv retry --dry-run` prints the selected retry command without executing it, and `jv retry --json` emits the same selection as JSON for agents.

Use `jv fix` to print a read-only repair brief for the latest failed or blocked run. `jv fix --json` emits the same brief as structured data for agents.

Use `jv watch` while editing to run once immediately, then rerun whenever Java source files change.

### Shell Completions

Static completions are available in `completions/` for Bash, Zsh, and Fish. Install the file that matches your shell into the standard completion directory for your environment.

### Packaging

`scripts/release.sh <version>` builds a local release archive under `dist/`. A Homebrew formula template lives at `packaging/homebrew/jv.rb`; maintainers should replace the URL and SHA-256 with real release artifact values before publishing.

---

## ✨ Features

- ✅ **Convention-based** directory structure (`src/`, `bin/`, `lib/`)
- ✅ **Auto-detect** and include JARs from `lib/` folder
- ✅ **Generated** `.jv/` memory for detected project state and run history
- ✅ **Pass-through** arguments to Java programs
- ✅ **Clear** error messages for compilation failures
- ✅ **Zero** external dependencies (just bash and Java)

---

## 📊 Why JV over Maven/Gradle?

| Feature | JV | Maven | Gradle |
|---------|-----|-------|--------|
| **Setup time** | < 1 minute | 5-10 minutes | 5-10 minutes |
| **Config complexity** | Minimal/None | XML (verbose) | Groovy/Kotlin DSL |
| **Learning curve** | Minimal | Steep | Steep |
| **Best for** | University assignments, small projects | Enterprise, large projects | Enterprise, Android |
| **Dependencies** | Drop JARs in `lib/` | XML declaration | DSL declaration |

---

## 🗺️ Roadmap

### ✅ Phase 1: Shell-Based MVP (Current)
- Basic project management for university assignments
- Simple CLI commands for create, compile, run, clean
- Convention-based directory structure
- JAR dependency support

### 🚧 Phase 2: Go Implementation (Planned)
- Single binary distribution (Windows, Linux, macOS)
- Faster execution and better error handling
- Colored terminal output
- Watch mode for auto-recompilation
- Enhanced dependency management

### 📋 Phase 3: Template System (Planned)
- Project templates (console-app, microservice, mvc, etc.)
- `jv create --template <name>` command
- Custom user-defined templates
- Best practices and boilerplate code

---

## 📖 Documentation

- **[Examples](EXAMPLES.md)** - Detailed usage examples
- **[Contributing](CONTRIBUTING.md)** - Contribution guidelines
- **[Changelog](CHANGELOG.md)** - Version history and updates

---

## 🤝 Contributing

Contributions are welcome! Whether it's:
- 🐛 Bug reports
- 💡 Feature requests
- 📝 Documentation improvements
- 🔧 Code contributions

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

MIT License - feel free to use JV in your projects!

---

<div align="center">
  
  **Made with ❤️ for students and developers**
  
  [Website](https://jv.copydataai.com) • [GitHub](https://github.com/copydataai/jv) • [Examples](EXAMPLES.md)
  
</div>
