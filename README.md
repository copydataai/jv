# JV is npm but for java

> jv is the npm but for java

## Description
A simple java wrapper for daily tasks


allows you to use java as a wrapper of java for the creation of simple java projects like university 


## Pain
As a computer Science student all my teachers use Eclipse as IDE but I don't like to install software that makes all this I would prefer a CLI and use pure NeoVim or Emacs, but they have their ecosystem like maven, gradle and jake all of them becoming so big that are mainly adopted for big projects.


### Solution
JV is a simple java wrapper for daily tasks, college student that wants to user the CLI without to have to worry about all the arguments and mkdir, just worry to compile, run and check that works without to have to worry about the arguments and mkdir, configuration files, etc.

---

## Development Roadmap

### Phase 1: Shell-Based MVP (Simple Java Wrapper)

**Goal**: Basic project management for university assignments

**Commands**:
- `jv create <project-name> [package]` - Create directory + initialize project (optionally with package structure)
- `jv init` - Initialize project in current directory (creates `src/`, `bin/`, `lib/` structure)
- `jv compile [package.ClassName]` - Compile all or specific Java files
- `jv run <package.ClassName> [args...]` - Run compiled programs (auto-compiles if needed)
- `jv clean` - Remove all compiled `.class` files
- `jv help` - Show usage and available commands

**Features**:
- Convention-based directory structure (no complex config files)
- Auto-detect and include JARs from `lib/` folder
- Simple `jv.json` config file for project metadata
- Pass-through arguments to Java programs
- Clear error messages for compilation failures

**Target Use Case**: Single or few Java files for university assignments

---

### Phase 2: Go Implementation (Cross-Platform & Enhanced)

**Goal**: Rewrite in Go for better performance and cross-platform support

**Improvements**:
- Single binary distribution (no bash dependency)
- Windows, Linux, and macOS support
- Faster execution and better error handling
- Colored terminal output for better UX
- Basic dependency management (download JARs from URLs)
- Watch mode: `jv run --watch` (auto-recompile on file changes)
- Better classpath management and Java version detection

**New Commands**:
- `jv add <jar-url-or-path>` - Add external JAR dependencies
- `jv test [TestClass]` - Run JUnit tests without complex setup
- `jv watch` - Auto-compile on file changes
- `jv version` - Show JV and detected Java version

---

### Phase 3: Template System (Cookiecutter-Style Projects)

**Goal**: Support different project types and architectures

**Enhanced `jv create` Command**:
```bash
jv create <project-name> [--template <template-name>]
```

**Available Templates**:

1. **`simple`** (default)
   - Single package structure
   - One Main.java file
   - Perfect for university assignments

2. **`console-app`**
   - Multi-class console application
   - Input/output utilities pre-configured
   - Example command-line argument parsing

3. **`microservice`**
   - Lightweight HTTP server (using Javalin or similar)
   - RESTful API structure
   - Basic routing and JSON handling
   - Docker configuration included

4. **`mvc`**
   - Model-View-Controller structure
   - Separation of concerns setup
   - Configuration for web apps

5. **`data-structures`**
   - Pre-configured for algorithms and data structures practice
   - Test harness included
   - Common interfaces (List, Stack, Queue, etc.)

6. **`desktop`**
   - JavaFX or Swing setup
   - GUI application boilerplate
   - Event handling examples

7. **`cli-tool`**
   - Command-line application with subcommands
   - Argument parsing library included
   - Professional CLI structure

**Template Features**:
- Each template includes README with setup instructions
- Pre-configured dependencies in `jv.json`
- Sample code and project structure
- Best practices for that specific use case
- Optional GitHub Actions CI/CD workflows

**Template Management**:
- `jv templates list` - Show available templates
- `jv templates show <name>` - Display template details
- Custom templates: Support for user-defined templates in `~/.jv/templates/`

---

## Installation

```bash
# Phase 1 (Shell version)
curl -fsSL https://raw.githubusercontent.com/copydataai/jv/main/install.sh | bash

# Or manual
git clone https://github.com/copydataai/jv.git
cd jv
chmod +x jv.sh
sudo ln -s $(pwd)/jv.sh /usr/local/bin/jv
```

## Quick Start

```bash
# Create a new project (simple, no package)
jv create my-assignment

# Create with package structure
jv create my-assignment ie.atu.sw

# Or interactive (will prompt for package)
jv create my-assignment

# Compile and run
cd my-assignment
jv run ie.atu.sw.Main

# Add external library
cp professor-library.jar lib/

# Compile with dependencies
jv compile

# Run tests
jv test
```

---

## Why JV over Maven/Gradle?

| Feature | JV | Maven | Gradle |
|---------|-----|-------|--------|
| Setup time | < 1 minute | 5-10 minutes | 5-10 minutes |
| Config complexity | Minimal/None | XML (verbose) | Groovy/Kotlin DSL |
| Learning curve | Minimal | Steep | Steep |
| Best for | University assignments, small projects | Enterprise, large projects | Enterprise, Android |
| Dependencies | Drop JARs in `lib/` | XML declaration | DSL declaration |

---

## Examples

See [EXAMPLES.md](EXAMPLES.md) for detailed examples including:
- University assignments with packages
- Using external JAR libraries
- Multi-class projects
- Command-line argument handling

## Project Status

✅ **Phase 1** - Complete! Shell-based MVP is ready to use
🚧 **Phase 2** - Go implementation (planned)
📋 **Phase 3** - Template system (planned)

## Contribute

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - feel free to use in your projects!
