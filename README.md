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

# Or manual installation
git clone https://github.com/copydataai/jv.git
cd jv
chmod +x jv.sh
sudo ln -s $(pwd)/jv.sh /usr/local/bin/jv
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
| `jv doctor` | Inspect Java project state and possible entrypoints |
| `jv remember main <ClassName>` | Remember a preferred main class in `.jv/` |
| `jv forget main` | Remove the remembered main class |
| `jv clean` | Remove all `.class` files |
| `jv help` | Show usage and available commands |

---

### Generated JV Memory

JV does not require a hand-written config file for normal projects. Source files and build tools are truth; `.jv/` is generated memory. JV writes `.jv/state.json` and `.jv/runs.jsonl` after successful runs so humans and coding agents can inspect what JV detected and executed.

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
