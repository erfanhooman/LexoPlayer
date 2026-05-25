# LexoPlayer

LexoPlayer is a modern, interactive desktop video player designed for language learning. It lets you watch movies and TV shows with interactive subtitles, allowing you to hover over or click any word to instantly view monolingual (definition) and bilingual (translation) dictionary lookups offline.

---

## Quick Start

### 1. Prerequisites
- Flutter SDK (`>= 3.2.0`)
- Dart SDK (`>= 3.2.0`)

### 2. Launching the App
Run these commands in your terminal to set up and start the application:

```bash
# Get dependencies
flutter pub get

# Run in Debug mode (best for development/hot-reload)
flutter run -d macos  # Or: flutter run -d windows

# Run in Release mode (best for smooth, lag-free video testing)
flutter run -d macos --release
```

---

## Step-by-Step Testing Guide

Follow these steps to thoroughly test all core features of LexoPlayer:

### Step 1: Set Up Dictionaries
To test word lookups, you need active dictionaries:
1. Launch the app and click on **Dictionary Hub** from the main library dashboard.
2. In the Download Hub, download one of the available dictionaries from the cloud (or click **Import Local Db** to select a custom `.db` dictionary database file).
3. Go to the active dictionary dropdowns at the top right of the dashboard, and select your downloaded dictionary in the **Definition Slot** (monolingual) or **Translation Slot** (bilingual).

### Step 2: Play a Video
1. On the main library screen, click **Open Local File** and pick a video file (MP4, MKV, AVI, MOV, or WEBM).
2. Alternatively, click **Stream from Link**, paste a streaming video URL, and click **Stream**.

### Step 3: Load Subtitles
1. While the video is playing, click the **Settings icon** on the bottom control bar.
2. Choose **Import Subtitle File** and select an external `.srt` or `.vtt` file.
3. In the subtitle track selection list, click on your imported subtitle track to activate it.

### Step 4: Interactive Word Lookup
1. Pause or play the video on a frame with subtitles.
2. Hover your mouse cursor over any word in the subtitle track. The word will highlight.
3. Observe the popup at the top/center of the screen. It should display:
   - The word's base form (stemmed/tokenized).
   - The bilingual translation (e.g. English to Persian) if a translation dictionary is selected.
   - The monolingual dictionary definitions and usage examples if a definition dictionary is selected.

### Step 5: Test Playback Resumption
1. Play the video, seek to the middle (e.g. 5 minutes in), and watch for a few seconds.
2. Click the **Back arrow button** in the top-left corner of the screen to return to the library dashboard.
3. In the library dashboard, look at the **Continue Watching** list.
4. Click on the video you just exited. It should resume playing **exactly** from where you left off.
5. Watch the video near completion (within 5 seconds of the end), exit back to the library, and click on it again. It should start over from the beginning (`0:00`).

---

## Dictionary SQLite Schema

If you want to import your own custom dictionaries, prepare your SQLite `.db` database using the following schemas:

### Monolingual (Definition) Dictionary
```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  html_definition TEXT -- JSON string containing parts of speech, definitions, and examples
);
```

### Bilingual (Translation) Dictionary
```sql
CREATE TABLE entries (
  word TEXT PRIMARY KEY,
  localized_text TEXT -- Translation text string
);
```

---

## Command Cheat Sheet

| Task | Command |
| :--- | :--- |
| **Install packages** | `flutter pub get` |
| **Run app (Debug)** | `flutter run` |
| **Run app (Release)** | `flutter run --release` |
| **Run static analysis** | `flutter analyze` |
| **Run unit tests** | `flutter test` |
| **Build macOS App** | `flutter build macos --release` |
| **Build Windows App** | `flutter build windows --release` |
