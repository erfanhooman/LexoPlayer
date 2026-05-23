# Contributing to LexoPlayer

Thank you for your interest in contributing to LexoPlayer! This document provides guidelines and instructions for contributing.

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on what is best for the community

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Description**: Clear and concise description of the bug
- **Steps to Reproduce**: Detailed steps to reproduce the behavior
- **Expected Behavior**: What you expected to happen
- **Screenshots**: If applicable
- **Environment**: OS, Flutter version, app version

### Suggesting Enhancements

- Check existing issues and pull requests first
- Explain why this enhancement would be useful
- Consider how it fits with the project's goals

### Pull Requests

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`flutter test`)
5. Run linter (`flutter analyze`)
6. Commit your changes (`git commit -m 'feat: add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

## Development Setup

```bash
# Clone your fork
git clone https://github.com/your-username/lexo-player.git
cd lexo-player

# Install dependencies
flutter pub get

# Run the app
flutter run -d macos
```

## Code Style

- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Run `flutter format .` before committing
- Run `flutter analyze` to catch issues early

## Dictionary Contributions

If you want to contribute dictionary files:

1. Follow the database schema outlined in the README
2. Test your database with the app's import feature
3. **Do not** commit `.db` or `.zip` files directly (they are gitignored)
4. Provide documentation or scripts for generating dictionary databases

## Questions?

Feel free to open an issue for any questions not covered here.
