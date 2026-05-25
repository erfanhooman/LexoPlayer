# LexoPlayer

LexoPlayer is a modern, premium cross-platform video player built with Flutter, designed specifically for language learning and acquisition. It features interactive subtitles that allow users to hover over or click any word to instantly lookup monolingual definitions and bilingual translations from offline SQLite databases.

---

## Key Features

- **Interactive Subtitles (Softsubs & Hardsubs)**: Every word in the subtitle track is rendered as an independent interactive token. Hovering or tapping highlights the token and initiates a dictionary lookup.
- **Multi-Word Phrase Detection**: Instead of relying on predefined chunking, the app dynamically constructs candidate phrases up to **8 words** in length by looking ahead and behind the hovered word. This allows automatic matching of compound verbs, idioms, and phrases (e.g., hovering over *"voice"* in *"i had no voice in that matter"* matches the entire phrase).
- **Graceful Compound Word Matching**: Normalizes casing, spaces, and hyphens so compound variations match seamlessly (e.g., subtitle word `"able-bodied"`, `"able bodied"`, or `"ablebodied"` will successfully find whatever variation is stored in the dictionary database).
- **Tabbed Result Interface**: If multiple overlapping phrases or words match (e.g., `"voice"`, `"no voice"`, and `"i had no voice in that matter"`), the definition card renders sleek, horizontal tabs at the top to easily switch between definitions.
- **Premium, Adaptive Glassmorphic UI**: Dynamic position guards prevent popup clipping near screen edges. Wide-wrap header layouts prevent premature scrolling of bilingual translations.
- **Intelligent Playback Lifecycle**: Automatically pauses the video when hovering/tapping on words. Resumes playback after exit. Mutes and stops all audio playback in **0ms** when exiting back to the main menu.
- **Playback Resume**: Remembers the exact playback location of each video. Resumes from the last watched position, resetting automatically if you watched near the end.

---

## Getting Started

### 1. Prerequisites
- **Flutter SDK** (`>= 3.2.0`)
- **Dart SDK** (`>= 3.2.0`)

### 2. Setup and Run
Execute the following commands in your workspace:

```bash
# Get dependency packages
flutter pub get

# Run in Debug mode (supports hot-reload)
flutter run -d macos  # Or: flutter run -d windows

# Run in Release mode (best for smooth video testing)
flutter run -d macos --release  # Or: flutter run -d windows --release
```

---

## Step-by-Step Testing Guide

1. **Set Up Dictionaries**:
   - Go to **Dictionary Hub** from the main library dashboard.
   - Click **Download Hub** to fetch dictionaries or click **Import Local Db** to select a custom `.db` SQLite file.
   - Select your active dictionaries in the **Definition Slot** (monolingual) and **Translation Slot** (bilingual) dropdowns.
2. **Open Media**:
   - Click **Open Local File** to pick a video file (MP4, MKV, AVI, MOV, WEBM) or click **Stream from Link** to paste a streaming video URL.
3. **Load Subtitles**:
   - Tap the **Settings icon** on the bottom control bar during playback.
   - Select **Import Subtitle File** to load an external `.srt` or `.vtt` file.
   - Select the loaded track in the tracks list to activate it.
4. **Interact**:
   - Hover or tap any word. Observe that the player pauses and the popup appears.
   - Switch between candidate tabs for multi-word phrases.
   - Move mouse away to resume playing.

---

## Dictionary SQLite Schema

To import custom offline dictionaries, ensure your SQLite database matches the schemas below:

### Monolingual (Definition) Dictionary
```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  html_definition TEXT -- JSON string containing parts of speech, definitions, and examples
);
CREATE INDEX idx_entries_word ON entries(word);
```

*Example JSON for `html_definition`:*
```json
{
  "part_of_speech": "adjective",
  "definitions": [
    {
      "meaning": "Physically strong and healthy.",
      "translation": "تندرست و قوی هیکل",
      "example": "An able-bodied young man."
    }
  ]
}
```

### Bilingual (Translation) Dictionary
```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  localized_text TEXT -- Native language translation string
);
CREATE INDEX idx_entries_word ON entries(word);
```

---

## Command Reference

| Command | Action |
| :--- | :--- |
| `flutter pub get` | Installs project dependencies |
| `flutter run` | Runs application in debug mode |
| `flutter run --release` | Runs application in release mode |
| `flutter analyze` | Checks for code analysis warnings and linting errors |
| `flutter test` | Executes unit tests |
| `flutter build macos --release` | Generates a production macOS build |
| `flutter build windows --release` | Generates a production Windows build |

---

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
Copyright (c) 2026 LexoPlayer.
