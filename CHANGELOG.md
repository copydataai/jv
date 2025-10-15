# Changelog

All notable changes to JV will be documented in this file.

## [0.1.0] - 2025-10-14

### Added
- Initial release of JV shell-based MVP
- `jv create <project-name> [package]` - Create new Java projects with optional package structure
- `jv init` - Initialize project in current directory
- `jv compile` - Compile all Java files with automatic classpath detection
- `jv run <ClassName> [args...]` - Run Java programs with auto-compilation
- `jv clean` - Remove compiled .class files
- `jv help` - Display usage information
- `jv version` - Show version information
- Interactive package prompt when creating projects
- Automatic package directory structure creation (e.g., `ie.atu.sw` → `src/ie/atu/sw/`)
- Auto-detection of external JARs in `lib/` directory
- Colored terminal output for better UX
- Sample Main.java generation with or without package declaration
- Simple `jv.json` configuration file
- Installation script for easy setup

### Features
- Convention-based directory structure (`src/`, `bin/`, `lib/`)
- No complex configuration files required
- Clear error messages for compilation failures
- Pass-through arguments to Java programs
- Terminal color detection (only shows colors when output is to a terminal)

### Documentation
- Comprehensive README with 3-phase roadmap
- EXAMPLES.md with common use cases
- CONTRIBUTING.md for contributors
- Installation instructions

### Target Use Case
- University assignments and small Java projects
- Alternative to Maven/Gradle for simple projects
- CLI-friendly workflow for Vim/Emacs users
