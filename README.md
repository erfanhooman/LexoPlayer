# LexoPlayer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.2+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey?logo=apple)](https://flutter.dev/macos)

An interactive video player optimized for language acquisition, featuring dual-tier dictionary lookups, interactive subtitles, and a flexible dictionary subsystem.

---

## Features

- **Video Playback**: Full-featured video player powered by `media_kit`
- **Interactive Subtitles**: Tap any word in subtitles for instant lookup
- **Dual Dictionary System**: 
  - Monolingual (definition) dictionaries for in-depth explanations
  - Bilingual (translation) dictionaries for quick native translations
- **Cloud Dictionary Downloads**: Fetch dictionaries from a remote server via `manifest.json`
- **Local Dictionary Import**: Import custom `.db` SQLite dictionaries directly from your device
- **Download Hub**: Manage, track, and install dictionaries from within the app

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- macOS (primary target platform)

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/lexo-player.git
cd lexo-player

# Install dependencies
flutter pub get

# Run the app
flutter run -d macos
```

---

## Project Structure

```
your-username/lexo-player/
├── .github/                          # GitHub templates & workflows
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
├── lib/                              # Flutter/Dart source code
│   ├── main.dart                     # App entry point
│   ├── core/                         # Shared services, models, utils
│   │   ├── database/
│   │   ├── models/
│   │   ├── services/
│   │   └── utils/
│   └── features/                     # Feature-based modules
│       ├── dictionary/
│       ├── subtitles/
│       ├── video_player/
│       └── main_menu/
├── test/                             # Unit & widget tests
├── macos/                            # macOS platform-specific code
├── dictionaries/                     # Dictionary distribution folder
│   ├── manifest.json                 # Central dictionary manifest
│   ├── eng_oxford.zip                # Oxford dictionary (user-provided)
│   └── eng_to_pes.zip                # English-to-Persian dictionary (user-provided)
├── pubspec.yaml                      # Flutter dependencies
├── analysis_options.yaml             # Dart linter rules
├── LICENSE                           # MIT License
└── README.md
```

---

## Dictionary System

LexoPlayer uses SQLite databases for both monolingual and bilingual dictionaries. Dictionaries can be loaded either from a remote server (via `manifest.json`) or imported locally.

### Database Schema

#### Monolingual (Definition) Dictionary

```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  html_definition TEXT
);
CREATE INDEX idx_entries_word ON entries(word);
```

The `html_definition` field contains a JSON string with structured definition cards:

```json
{
  "part_of_speech": "adjective",
  "definitions": [
    {
      "meaning": "A word that describes or limits a noun.",
      "example": "In the phrase 'the blue car', 'blue' is an adjective."
    }
  ]
}
```

#### Bilingual (Translation) Dictionary

```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  localized_text TEXT
);
CREATE INDEX idx_entries_word ON entries(word);
```

### Manifest File

The `dictionaries/manifest.json` file defines available dictionaries for cloud download:

```json
{
  "last_updated": "2026-05-23T00:00:00Z",
  "version": 1,
  "dictionaries": {
    "monolingual": [
      {
        "id": "eng_oxford",
        "source_language": "en",
        "display_name": "Oxford Advanced Dictionary",
        "description": "Premium English monolingual definitions with phonetics.",
        "remote_url": "https://api.yourserver.com/dicts/eng_oxford.zip",
        "file_size_bytes": 0,
        "md5_checksum": ""
      }
    ],
    "bilingual": [
      {
        "id": "eng_to_pes",
        "source_language": "en",
        "native_language": "fa",
        "display_name": "English-to-Persian Dictionary",
        "description": "Bilingual translations for Persian learners.",
        "remote_url": "https://api.yourserver.com/dicts/eng_to_pes.zip",
        "file_size_bytes": 0,
        "md5_checksum": ""
      }
    ]
  }
}
```

### Creating Dictionary Archives

```bash
# Zip a SQLite database
zip -j eng_oxford.zip english_monolingual.db

# Get file size and MD5 checksum
wc -c eng_oxford.zip
md5 eng_oxford.zip   # macOS
md5sum eng_oxford.zip # Linux
```

> **Note**: The `dictionaries/` folder in this repo contains only the `manifest.json` template. Database files (`.db`) and zip archives (`.zip`) are excluded from version control. You will need to provide your own dictionary files.

---

## Configuration

The manifest endpoint URL is configured in:
- `lib/core/services/manifest_service.dart`

Update this URL to point to your hosted `manifest.json` file.

---

## Testing

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/subtitle_parser_test.dart
```

---

## Building for Production

```bash
# Build for macOS
flutter build macos --release

# Build for other platforms (if configured)
flutter build <platform> --release
```

---

## Contributing

Contributions are welcome! Please read the [contributing guidelines](CONTRIBUTING.md) before submitting a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [media_kit](https://github.com/media-kit/media-kit) - Video playback engine
- [flutter_riverpod](https://riverpod.dev) - State management
- [sqflite](https://pub.dev/packages/sqflite) - SQLite database support
