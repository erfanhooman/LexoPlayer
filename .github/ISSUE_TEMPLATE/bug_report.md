name: Bug Report
description: Report a bug to help us improve LexoPlayer
title: "[Bug]: "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to fill out this bug report!
  - type: textarea
    id: description
    attributes:
      label: What happened?
      description: A clear and concise description of the bug.
    validations:
      required: true
  - type: textarea
    id: reproduce
    attributes:
      label: Steps to reproduce
      description: How do you trigger this bug?
      value: |
        1. Go to '...'
        2. Click on '...'
        3. Scroll down to '...'
        4. See error
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
      description: What did you expect to happen?
    validations:
      required: true
  - type: input
    id: platform
    attributes:
      label: Platform
      description: What platform are you running on? (macOS, Windows, Linux)
    validations:
      required: true
  - type: input
    id: flutter-version
    attributes:
      label: Flutter Version
      description: Run `flutter --version` to find your Flutter version.
    validations:
      required: true
