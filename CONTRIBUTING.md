# Contributing to JV

Thank you for your interest in contributing to JV! This document provides guidelines for contributing.

## Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/copydataai/jv.git
   cd jv
   ```

2. **Make the script executable**
   ```bash
   chmod +x jv.sh
   ```

3. **Test locally**
   ```bash
   ./jv.sh help
   ./jv.sh create test-project
   ```

## How to Contribute

### Reporting Bugs

- Check if the bug has already been reported in Issues
- Include steps to reproduce the bug
- Include your OS, shell version, and Java version
- Include the output of `jv version`

### Suggesting Features

- Open an issue with the `enhancement` label
- Explain the use case and why it would be helpful
- Keep in mind JV's philosophy: simple and focused on university/small projects

### Pull Requests

1. **Fork the repository**

2. **Create a feature branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

3. **Make your changes**
   - Follow the existing code style
   - Keep functions focused and well-named
   - Add comments for complex logic
   - Test your changes

4. **Test thoroughly**
   ```bash
   # Test all commands
   ./jv.sh create test-proj
   cd test-proj
   ../jv.sh compile
   ../jv.sh run Main
   ../jv.sh clean
   ```

5. **Commit with clear messages**
   ```bash
   git commit -m "feat: add support for custom source directories"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/my-new-feature
   ```

## Code Style

- Use 4 spaces for indentation (not tabs)
- Keep lines under 100 characters when possible
- Use meaningful variable names
- Add comments for non-obvious logic
- Use helper functions (`error`, `success`, `info`, `warn`)

## Testing Checklist

Before submitting a PR, test these scenarios:

- [ ] `jv create new-project` works
- [ ] `jv init` in empty directory works
- [ ] `jv compile` compiles all Java files
- [ ] `jv run ClassName` runs programs
- [ ] `jv run ClassName arg1 arg2` passes arguments
- [ ] `jv clean` removes .class files
- [ ] Works with external JARs in `lib/` directory
- [ ] Error messages are clear and helpful
- [ ] Works on macOS (if you can test)
- [ ] Works on Linux (if you can test)

## Project Philosophy

Keep these principles in mind:

1. **Simplicity First**: JV should be easy to understand and use
2. **No Configuration Overhead**: Prefer conventions over configuration
3. **University-Friendly**: Perfect for assignments and small projects
4. **Clear Errors**: Students should understand what went wrong
5. **Escape Hatches**: Don't prevent users from using javac directly

## Questions?

Open an issue with the `question` label, and we'll be happy to help!
