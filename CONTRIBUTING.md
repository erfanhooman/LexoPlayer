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

### Git Branching Strategy & Workflow

We follow a structured **Git Flow** tailored for cross-platform desktop application delivery:

- **`main`**: Production release branch. Code here must always be stable.
  - Tagging `main` with a release tag (e.g., `git tag v1.0.0 && git push origin v1.0.0`) triggers the **Automated Multi-Platform Release Pipeline**.
- **`develop`**: Integration branch for active development. All feature PRs target `develop`.
- **`feature/<name>`**: Short-lived feature branches created off `develop` (e.g., `feature/custom-subtitle-styling`).
- **`fix/<name>`**: Bugfix branches created off `develop` (e.g., `fix/dictionary-lookup-crash`).
- **`hotfix/<name>`**: Emergency bugfix branches created directly off `main`.

### Automated GitHub Actions Workflows

You no longer need to perform full release builds locally for every operating system!

1. **Continuous Integration (`ci.yml`)**:
   - Runs automatically on every push or Pull Request targeting `develop` or `main`.
   - Runs `dart format`, `flutter analyze`, `flutter test`, and multi-platform compilation checks across macOS, Windows, and Linux.
   - Builds artifacts available for download under the Actions workflow run summary.

2. **Automated Release Pipeline (`release.yml`)**:
   - Triggered when pushing a version tag (e.g. `v1.0.0`) or manually via GitHub's "Run workflow" button.
   - Automatically builds:
     - **macOS**: Bundle + Installer DMG (`LexoPlayer-macOS-Installer.dmg`)
     - **Windows**: Portable ZIP + Inno Setup Executable (`LexoPlayer-Setup-x64.exe`)
     - **Linux**: Release tarball (`LexoPlayer-Linux-x64.tar.gz`)
   - Packages and attaches all release assets to a newly published GitHub Release with release notes!

### Pull Requests

1. Fork or clone the repository
2. Create your branch off `develop` (`git checkout -b feature/amazing-feature develop`)
3. Make your changes
4. Run local sanity tests (`flutter test` and `flutter analyze`)
5. Commit your changes (`git commit -m 'feat: add amazing feature'`)
6. Push to your branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request targeting `develop`

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
