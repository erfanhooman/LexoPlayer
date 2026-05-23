import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/subtitles/logic/binary_search_sync.dart';

/// Represents an option for a subtitle track (either embedded or external)
class SubtitleTrackOption {
  final String id;
  final String name;
  final bool isExternal;
  final String? filePath;
  final SubtitleTrack? nativeTrack;
  final List<SubtitleBlock>? externalBlocks;

  const SubtitleTrackOption({
    required this.id,
    required this.name,
    required this.isExternal,
    this.filePath,
    this.nativeTrack,
    this.externalBlocks,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtitleTrackOption &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Holds the currently loaded list of parsed [SubtitleBlock]s (for the active external track).
final subtitleListProvider = StateProvider.autoDispose<List<SubtitleBlock>>(
  (ref) => const [],
);

/// Tracks the index into [subtitleListProvider] of the currently active
/// subtitle block, or `null` when no block is active.
final activeSubtitleIndexProvider = StateProvider.autoDispose<int?>(
  (ref) => null,
);

/// Controls whether the subtitle overlay is visible.
final subtitleVisibilityProvider = StateProvider.autoDispose<bool>(
  (ref) => true,
);

/// Tracks the list of loaded external subtitle options.
final externalSubtitleOptionsProvider =
    StateProvider.autoDispose<List<SubtitleTrackOption>>(
  (ref) => const [],
);

/// Stream provider for all subtitle tracks discovered by media_kit.
final embeddedSubtitleTracksProvider =
    StreamProvider.autoDispose<List<SubtitleTrack>>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.tracks.map((tracks) => tracks.subtitle);
});

/// Combines embedded tracks and loaded external options.
final availableSubtitlesProvider = Provider.autoDispose<List<SubtitleTrackOption>>((ref) {
  final embeddedAsync = ref.watch(embeddedSubtitleTracksProvider);
  final externalList = ref.watch(externalSubtitleOptionsProvider);

  final embeddedList = embeddedAsync.valueOrNull ?? [];
  final List<SubtitleTrackOption> options = [];

  // Add Off/None option
  options.add(const SubtitleTrackOption(
    id: 'none',
    name: 'Off',
    isExternal: false,
  ));

  // Add embedded options (filter out None/Auto)
  for (final track in embeddedList) {
    if (track.id == 'no' || track.id == 'auto') continue;
    options.add(SubtitleTrackOption(
      id: 'embedded_${track.id}',
      name:
          '${track.title ?? track.language ?? "Track ${track.id}"} (Embedded)',
      isExternal: false,
      nativeTrack: track,
    ));
  }

  // Add external options
  options.addAll(externalList);

  return options;
});

/// The currently selected subtitle track option.
final selectedSubtitleProvider =
    StateProvider.autoDispose<SubtitleTrackOption?>((ref) => null);

/// Holds the current softsub subtitle text emitted by media_kit.
final softsubSubtitleTextProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Listen to media_kit's subtitle stream.
final softsubListenerProvider = StreamProvider.autoDispose<List<String>>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.subtitle;
});

/// Derives the active subtitle text.
final activeSubtitleTextProvider = Provider.autoDispose<String?>((ref) {
  final selected = ref.watch(selectedSubtitleProvider);
  if (selected == null || selected.id == 'none') {
    return null;
  }
  if (selected.isExternal) {
    final index = ref.watch(activeSubtitleIndexProvider);
    if (index == null) return null;
    final blocks = ref.watch(subtitleListProvider);
    if (index < 0 || index >= blocks.length) return null;
    return blocks[index].text;
  } else {
    // Embedded softsub
    return ref.watch(softsubSubtitleTextProvider);
  }
});

/// Reactively synchronizes subtitle tracks and position changes with the player.
///
/// This provider must be watched in the video player screen to ensure that
/// subtitle synchronization is active during the playback session.
final playerSubtitleSyncProvider = Provider.autoDispose<void>((ref) {
  final player = ref.watch(playerProvider);

  // 1. Sync subtitle track selection with media_kit player.
  ref.listen<SubtitleTrackOption?>(selectedSubtitleProvider, (prev, next) async {
    if (next == null || next.id == 'none') {
      await player.setSubtitleTrack(SubtitleTrack.no());
      ref.read(subtitleListProvider.notifier).state = const [];
      ref.read(activeSubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSubtitleTextProvider.notifier).state = null;
    } else if (next.isExternal) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      ref.read(subtitleListProvider.notifier).state = next.externalBlocks ?? const [];
      ref.read(activeSubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSubtitleTextProvider.notifier).state = null;
    } else if (next.nativeTrack != null) {
      ref.read(subtitleListProvider.notifier).state = const [];
      ref.read(activeSubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSubtitleTextProvider.notifier).state = null;
      await player.setSubtitleTrack(next.nativeTrack!);
    }
  });

  // 2. Listen to media_kit embedded subtitle updates.
  ref.listen<AsyncValue<List<String>>>(softsubListenerProvider, (prev, next) {
    next.whenData((lines) {
      final text = lines.isEmpty ? null : lines.join(' ').trim();
      ref.read(softsubSubtitleTextProvider.notifier).state = text;
    });
  });

  // 3. Listen to player position stream to run O(log N) binary search for external subtitles.
  ref.listen<AsyncValue<Duration>>(positionProvider, (prev, next) {
    next.whenData((position) {
      final blocks = ref.read(subtitleListProvider);
      if (blocks.isEmpty) return;

      final idx = BinarySearchSync.findActiveIndex(blocks, position);
      final currentIdx = ref.read(activeSubtitleIndexProvider);

      if (idx != currentIdx) {
        ref.read(activeSubtitleIndexProvider.notifier).state = idx;
      }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Subtitle style customization providers and state persistence
// ─────────────────────────────────────────────────────────────────────────────

// Keys for SharedPreferences
const String _kSubtitleSizeKey = 'subtitle_size';
const String _kSubtitleColorKey = 'subtitle_color';
const String _kSubtitleBgColorKey = 'subtitle_bg_color';
const String _kSubtitleOutlineWidthKey = 'subtitle_outline_width';
const String _kSubtitleFontKey = 'subtitle_font';

/// Size of the subtitle text. Defaults to `22.0` (Medium).
final subtitleSizeProvider = StateProvider<double>((ref) => 22.0);

/// Text color of the subtitle as ARGB int. Defaults to `0xFFFFFFFF` (White).
final subtitleColorProvider = StateProvider<int>((ref) => 0xFFFFFFFF);

/// Background opacity container color as ARGB int. Defaults to `0xD9000000` (85% Black).
final subtitleBgColorProvider = StateProvider<int>((ref) => 0xD9000000);

/// Outline border thickness width. Defaults to `1.2` (Medium).
final subtitleOutlineWidthProvider = StateProvider<double>((ref) => 1.2);

/// Font family. Defaults to `'System'`.
final subtitleFontFamilyProvider = StateProvider<String>((ref) => 'System');

/// Loads all subtitle customization options from local device persistent storage.
Future<void> hydrateSubtitleSettings(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble(_kSubtitleSizeKey);
    final color = prefs.getInt(_kSubtitleColorKey);
    final bg = prefs.getInt(_kSubtitleBgColorKey);
    final outline = prefs.getDouble(_kSubtitleOutlineWidthKey);
    final font = prefs.getString(_kSubtitleFontKey);

    if (size != null) ref.read(subtitleSizeProvider.notifier).state = size;
    if (color != null) ref.read(subtitleColorProvider.notifier).state = color;
    if (bg != null) ref.read(subtitleBgColorProvider.notifier).state = bg;
    if (outline != null) ref.read(subtitleOutlineWidthProvider.notifier).state = outline;
    if (font != null) ref.read(subtitleFontFamilyProvider.notifier).state = font;
  } catch (e) {
    // Fail silently in case preferences are uninitialised
  }
}

Future<void> saveSubtitleSize(double size) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kSubtitleSizeKey, size);
}

Future<void> saveSubtitleColor(int color) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kSubtitleColorKey, color);
}

Future<void> saveSubtitleBgColor(int color) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kSubtitleBgColorKey, color);
}

Future<void> saveSubtitleOutlineWidth(double width) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_kSubtitleOutlineWidthKey, width);
}

Future<void> saveSubtitleFontFamily(String font) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSubtitleFontKey, font);
}
