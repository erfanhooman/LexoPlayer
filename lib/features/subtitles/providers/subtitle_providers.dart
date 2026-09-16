import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/subtitles/logic/binary_search_sync.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';

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
final subtitleListProvider = StateProvider<List<SubtitleBlock>>(
  (ref) => const [],
);

/// Tracks the index into [subtitleListProvider] of the currently active
/// subtitle block, or `null` when no block is active.
final activeSubtitleIndexProvider = StateProvider<int?>(
  (ref) => null,
);

/// Controls whether the subtitle overlay is visible.
final subtitleVisibilityProvider = StateProvider<bool>(
  (ref) => true,
);

/// Tracks the list of loaded external subtitle options.
final externalSubtitleOptionsProvider =
    StateProvider<List<SubtitleTrackOption>>(
  (ref) => const [],
);

/// Stream provider for all subtitle tracks discovered by media_kit.
final embeddedSubtitleTracksProvider =
    StreamProvider<List<SubtitleTrack>>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.tracks.map((tracks) => tracks.subtitle);
});

/// Combines embedded tracks and loaded external options.
final availableSubtitlesProvider = Provider<List<SubtitleTrackOption>>((ref) {
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

/// The currently selected subtitle track option (Primary).
final selectedSubtitleProvider =
    StateProvider<SubtitleTrackOption?>((ref) => null);

/// The currently selected secondary (translation) subtitle track option.
final selectedSecondarySubtitleProvider =
    StateProvider<SubtitleTrackOption?>((ref) => null);

/// Holds the currently loaded list of parsed [SubtitleBlock]s for the secondary track.
final secondarySubtitleListProvider = StateProvider<List<SubtitleBlock>>(
  (ref) => const [],
);

/// Tracks the active index into [secondarySubtitleListProvider].
final activeSecondarySubtitleIndexProvider = StateProvider<int?>(
  (ref) => null,
);

/// Controls whether the secondary subtitle (translation) is currently unhidden.
final isSecondarySubtitleVisibleProvider = StateProvider<bool>(
  (ref) => true,
);

/// Holds the current primary softsub subtitle text emitted by media_kit (lines[0]).
final softsubPrimarySubtitleTextProvider =
    StateProvider<String?>((ref) => null);

/// Holds the current secondary softsub subtitle text emitted by media_kit (lines[1]).
final softsubSecondarySubtitleTextProvider =
    StateProvider<String?>((ref) => null);

/// Alias for primary softsub text.
final softsubSubtitleTextProvider = softsubPrimarySubtitleTextProvider;

/// Helper to set the secondary subtitle track natively in mpv (`secondary-sid`).
void _setSecondaryNativeTrack(Player player, String sid) {
  try {
    final dynamic nativePlayer = player.platform;
    nativePlayer.setProperty('secondary-sid', sid);
    developer.log('Set mpv secondary-sid: $sid', name: 'SubtitleSync');
  } catch (e) {
    developer.log('Failed to set secondary-sid: $e', name: 'SubtitleSync');
  }
}

/// Derives the native (embedded) subtitle track currently being decoded by
/// media_kit for primary subtitle rendering.
final activeNativeSubtitleTrackProvider = Provider<SubtitleTrack?>((ref) {
  final primary = ref.watch(selectedSubtitleProvider);
  if (primary != null && primary.nativeTrack != null) {
    return primary.nativeTrack;
  }
  return null;
});

/// Bumped every time a primary subtitle selection changes, so slow file parsing
/// of a previously selected track cannot overwrite a newer selection.
int _primaryLoadGeneration = 0;

/// Bumped every time a secondary subtitle selection changes, so slow file parsing
/// of a previously selected track cannot overwrite a newer selection.
int _secondaryLoadGeneration = 0;

/// Holds the timestamp string of the currently active subtitle.
final activeSubtitleTimestampProvider = StateProvider<String?>((ref) => null);

/// Derives the text of the previous subtitle (for sliding window context).
final previousSubtitleTextProvider = Provider<String?>((ref) {
  final index = ref.watch(activeSubtitleIndexProvider);
  if (index == null || index <= 0) return null;

  final blocks = ref.watch(subtitleListProvider);
  if (index - 1 < 0 || index - 1 >= blocks.length) return null;
  return blocks[index - 1].text;
});

/// Derives the text of the next subtitle (for sliding window context).
final nextSubtitleTextProvider = Provider<String?>((ref) {
  final index = ref.watch(activeSubtitleIndexProvider);
  if (index == null) return null;

  final blocks = ref.watch(subtitleListProvider);
  if (index + 1 >= blocks.length) return null;
  return blocks[index + 1].text;
});

/// Listen to media_kit's subtitle stream.
final softsubListenerProvider = StreamProvider<List<String>>((ref) {
  final player = ref.watch(playerProvider);
  return player.stream.subtitle;
});

/// Derives the active primary subtitle text.
final activeSubtitleTextProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedSubtitleProvider);
  if (selected == null || selected.id == 'none') {
    return null;
  }
  if (selected.isExternal) {
    final blocks = ref.watch(subtitleListProvider);
    final index = ref.watch(activeSubtitleIndexProvider);
    if (index == null || index < 0 || index >= blocks.length) return null;
    return blocks[index].text;
  } else {
    // Embedded softsub primary
    return ref.watch(softsubPrimarySubtitleTextProvider);
  }
});

/// Derives the active secondary (translation) subtitle text.
final activeSecondarySubtitleTextProvider = Provider<String?>((ref) {
  final isVisible = ref.watch(isSecondarySubtitleVisibleProvider);
  if (!isVisible) return null;

  final selected = ref.watch(selectedSecondarySubtitleProvider);
  if (selected == null || selected.id == 'none') {
    return null;
  }
  if (selected.isExternal) {
    final loadedBlocks = ref.watch(secondarySubtitleListProvider);
    final blocks = loadedBlocks.isNotEmpty
        ? loadedBlocks
        : (selected.externalBlocks ?? const <SubtitleBlock>[]);
    var index = ref.watch(activeSecondarySubtitleIndexProvider);
    if (index != null && (index < 0 || index >= blocks.length)) {
      index = null;
    }
    if (index == null && blocks.isNotEmpty) {
      final position = ref.watch(positionProvider).valueOrNull ??
          ref.watch(playerProvider).state.position;
      index = BinarySearchSync.findActiveIndex(blocks, position);
    }
    if (index == null || index < 0 || index >= blocks.length) return null;
    return blocks[index].text;
  } else if (selected.nativeTrack != null) {
    // Embedded softsub secondary
    return ref.watch(softsubSecondarySubtitleTextProvider);
  }
  return null;
});

/// Reactively synchronizes subtitle tracks and position changes with the player.
///
/// This provider must be watched in the video player screen to ensure that
/// subtitle synchronization is active during the playback session.
final playerSubtitleSyncProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);

  // 1. Sync primary subtitle track selection with media_kit player.
  ref.listen<SubtitleTrackOption?>(selectedSubtitleProvider,
      (prev, next) async {
    // Invalidate any pending parse before handling every new selection,
    // including Off, so an old file cannot be applied after a media change.
    final generation = ++_primaryLoadGeneration;
    if (next == null || next.id == 'none') {
      await player.setSubtitleTrack(SubtitleTrack.no());
      ref.read(subtitleListProvider.notifier).state = const [];
      ref.read(activeSubtitleIndexProvider.notifier).state = null;
      ref.read(softsubPrimarySubtitleTextProvider.notifier).state = null;
    } else if (next.isExternal) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      List<SubtitleBlock> blocks = next.externalBlocks ?? const [];
      if (blocks.isEmpty && next.filePath != null) {
        try {
          blocks = await SubtitleParser.parseFile(next.filePath!);
        } catch (e) {
          developer.log('Error parsing primary subtitle: $e',
              name: 'SubtitleSync');
        }
      }
      // Ignore stale results if the user changed track while we were parsing.
      if (generation != _primaryLoadGeneration) return;
      developer.log(
        'External primary subtitle selected: "${next.name}" with ${blocks.length} blocks',
        name: 'SubtitleSync',
      );
      ref.read(subtitleListProvider.notifier).state = blocks;
      ref.read(softsubPrimarySubtitleTextProvider.notifier).state = null;

      if (blocks.isNotEmpty) {
        final posAsync = ref.read(positionProvider);
        final position = posAsync.valueOrNull ?? player.state.position;
        final idx = BinarySearchSync.findActiveIndex(blocks, position);
        ref.read(activeSubtitleIndexProvider.notifier).state = idx;
      } else {
        ref.read(activeSubtitleIndexProvider.notifier).state = null;
      }

      // ── DEFENSIVE SECONDARY RE-SYNC ──────────────────────────────────
      final secSel = ref.read(selectedSecondarySubtitleProvider);
      if (secSel != null && secSel.id != 'none' && secSel.isExternal) {
        var secBlocks = ref.read(secondarySubtitleListProvider);
        if (secBlocks.isEmpty) {
          final fallback = secSel.externalBlocks;
          if (fallback != null && fallback.isNotEmpty) {
            secBlocks = fallback;
            ref.read(secondarySubtitleListProvider.notifier).state = secBlocks;
          }
        }
        if (secBlocks.isNotEmpty) {
          final secPosAsync = ref.read(positionProvider);
          final secPosition = secPosAsync.valueOrNull ?? player.state.position;
          final secIdx =
              BinarySearchSync.findActiveIndex(secBlocks, secPosition);
          ref.read(activeSecondarySubtitleIndexProvider.notifier).state =
              secIdx;
          ref.read(isSecondarySubtitleVisibleProvider.notifier).state = true;
        }
      }
    } else if (next.nativeTrack != null) {
      ref.read(subtitleListProvider.notifier).state = const [];
      ref.read(activeSubtitleIndexProvider.notifier).state = null;
      ref.read(softsubPrimarySubtitleTextProvider.notifier).state = null;
      await player.setSubtitleTrack(next.nativeTrack!);
    }
  });

  // 2. Sync secondary subtitle track selection.
  ref.listen<SubtitleTrackOption?>(selectedSecondarySubtitleProvider,
      (prev, next) async {
    final generation = ++_secondaryLoadGeneration;
    if (next == null || next.id == 'none') {
      ref.read(secondarySubtitleListProvider.notifier).state = const [];
      ref.read(activeSecondarySubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSecondarySubtitleTextProvider.notifier).state = null;
      ref.read(isSecondarySubtitleVisibleProvider.notifier).state = true;
      _setSecondaryNativeTrack(player, 'no');
    } else if (next.isExternal) {
      ref.read(isSecondarySubtitleVisibleProvider.notifier).state = true;
      ref.read(secondarySubtitleListProvider.notifier).state = const [];
      ref.read(activeSecondarySubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSecondarySubtitleTextProvider.notifier).state = null;
      _setSecondaryNativeTrack(player, 'no');
      List<SubtitleBlock> blocks = next.externalBlocks ?? const [];
      if (blocks.isEmpty && next.filePath != null) {
        try {
          blocks = await SubtitleParser.parseFile(next.filePath!);
        } catch (e) {
          developer.log('Error parsing secondary subtitle: $e',
              name: 'SubtitleSync');
        }
      }
      if (generation != _secondaryLoadGeneration) return;
      developer.log(
        'External secondary subtitle selected: "${next.name}" with ${blocks.length} blocks',
        name: 'SubtitleSync',
      );
      ref.read(secondarySubtitleListProvider.notifier).state = blocks;

      if (blocks.isNotEmpty) {
        final posAsync = ref.read(positionProvider);
        final position = posAsync.valueOrNull ?? player.state.position;
        final idx = BinarySearchSync.findActiveIndex(blocks, position);
        ref.read(activeSecondarySubtitleIndexProvider.notifier).state = idx;
      } else {
        ref.read(activeSecondarySubtitleIndexProvider.notifier).state = null;
      }
    } else if (next.nativeTrack != null) {
      ref.read(secondarySubtitleListProvider.notifier).state = const [];
      ref.read(activeSecondarySubtitleIndexProvider.notifier).state = null;
      ref.read(softsubSecondarySubtitleTextProvider.notifier).state = null;
      ref.read(isSecondarySubtitleVisibleProvider.notifier).state = true;
      _setSecondaryNativeTrack(player, next.nativeTrack!.id);
    }
  });

  // 3. Listen to media_kit embedded subtitle updates.
  ref.listen<AsyncValue<List<String>>>(softsubListenerProvider, (prev, next) {
    next.whenData((lines) {
      final primarySelected = ref.read(selectedSubtitleProvider);
      final secondarySelected = ref.read(selectedSecondarySubtitleProvider);

      // Primary softsub text (lines[0])
      if (primarySelected != null &&
          primarySelected.nativeTrack != null &&
          lines.isNotEmpty &&
          lines[0].isNotEmpty) {
        final cleaned = SubtitleParser.cleanSubtitleText(lines[0]);
        ref.read(softsubPrimarySubtitleTextProvider.notifier).state =
            cleaned.isEmpty ? null : cleaned;
      } else {
        ref.read(softsubPrimarySubtitleTextProvider.notifier).state = null;
      }

      // Secondary softsub text (lines[1])
      if (secondarySelected != null &&
          secondarySelected.nativeTrack != null &&
          lines.length > 1 &&
          lines[1].isNotEmpty) {
        final cleaned = SubtitleParser.cleanSubtitleText(lines[1]);
        ref.read(softsubSecondarySubtitleTextProvider.notifier).state =
            cleaned.isEmpty ? null : cleaned;
      } else {
        ref.read(softsubSecondarySubtitleTextProvider.notifier).state = null;
      }
    });
  });

  // 4. Listen to player position stream to run O(log N) binary search for primary & secondary subtitles.
  ref.listen<AsyncValue<Duration>>(positionProvider, (prev, next) {
    next.whenData((position) {
      // Sync Primary Track
      final blocks = ref.read(subtitleListProvider);
      if (blocks.isNotEmpty) {
        final idx = BinarySearchSync.findActiveIndex(blocks, position);
        final currentIdx = ref.read(activeSubtitleIndexProvider);
        if (idx != currentIdx) {
          ref.read(activeSubtitleIndexProvider.notifier).state = idx;
        }
      }

      // Sync Secondary Track
      final secBlocks = ref.read(secondarySubtitleListProvider);
      if (secBlocks.isNotEmpty) {
        final secIdx = BinarySearchSync.findActiveIndex(secBlocks, position);
        final currentSecIdx = ref.read(activeSecondarySubtitleIndexProvider);
        if (secIdx != currentSecIdx) {
          ref.read(activeSecondarySubtitleIndexProvider.notifier).state =
              secIdx;
        }
      }
    });
  });

  // 4. Auto-select first available subtitle track when discovered if currently unselected or off.
  //    Prefer external (user-loaded SRT/VTT) tracks over embedded ones so a
  //    nearby subtitle file wins over the video's built-in track.
  ref.listen<List<SubtitleTrackOption>>(availableSubtitlesProvider,
      (prev, next) {
    final currentSelected = ref.read(selectedSubtitleProvider);

    final externalTracks = next.where((opt) => opt.isExternal).toList();
    final embeddedTracks =
        next.where((opt) => !opt.isExternal && opt.id != 'none').toList();

    // Nothing selected yet — pick external first, then embedded.
    if (currentSelected == null || currentSelected.id == 'none') {
      if (externalTracks.isNotEmpty) {
        ref.read(selectedSubtitleProvider.notifier).state =
            externalTracks.first;
      } else if (embeddedTracks.isNotEmpty) {
        ref.read(selectedSubtitleProvider.notifier).state =
            embeddedTracks.first;
      }
      return;
    }

    // An embedded track was auto-selected earlier but an external subtitle
    // has since been discovered — switch to it so user-loaded subtitles win.
    if (!currentSelected.isExternal && externalTracks.isNotEmpty) {
      ref.read(selectedSubtitleProvider.notifier).state = externalTracks.first;
    }
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
const String _kSmartSubtitleSeekKey = 'smart_subtitle_seek';

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

/// Controls whether forward/backward seeking targets subtitle lines (smart seek)
/// or performs fixed time-based seeking (±10s). Defaults to `true`.
final smartSubtitleSeekProvider = StateProvider<bool>((ref) => true);

/// Loads all subtitle customization options from local device persistent storage.
Future<void> hydrateSubtitleSettings(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble(_kSubtitleSizeKey);
    final color = prefs.getInt(_kSubtitleColorKey);
    final bg = prefs.getInt(_kSubtitleBgColorKey);
    final outline = prefs.getDouble(_kSubtitleOutlineWidthKey);
    final font = prefs.getString(_kSubtitleFontKey);
    final smartSeek = prefs.getBool(_kSmartSubtitleSeekKey);

    if (size != null) ref.read(subtitleSizeProvider.notifier).state = size;
    if (color != null) ref.read(subtitleColorProvider.notifier).state = color;
    if (bg != null) ref.read(subtitleBgColorProvider.notifier).state = bg;
    if (outline != null)
      ref.read(subtitleOutlineWidthProvider.notifier).state = outline;
    if (font != null)
      ref.read(subtitleFontFamilyProvider.notifier).state = font;
    if (smartSeek != null)
      ref.read(smartSubtitleSeekProvider.notifier).state = smartSeek;
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

Future<void> saveSmartSubtitleSeek(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSmartSubtitleSeekKey, enabled);
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-Video Subtitle Selection Persistence
// ─────────────────────────────────────────────────────────────────────────────

String _getSubtitleSelectionKey(String uri) {
  final normalized = uri.replaceAll('file://', '').replaceAll('\\', '/');
  final bytes = utf8.encode(normalized);
  final digest = md5.convert(bytes);
  return 'video_sub_sel_$digest';
}

/// Saves selected primary & secondary subtitle choices for a video URI to SharedPreferences.
Future<void> saveMediaSubtitleSelection({
  required String videoUri,
  SubtitleTrackOption? primaryOption,
  SubtitleTrackOption? secondaryOption,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final keyBase = _getSubtitleSelectionKey(videoUri);

    if (primaryOption != null) {
      if (primaryOption.filePath != null) {
        await prefs.setString(
            '${keyBase}_primary_path', primaryOption.filePath!);
      }
      await prefs.setString('${keyBase}_primary_id', primaryOption.id);
    }

    if (secondaryOption != null) {
      if (secondaryOption.filePath != null) {
        await prefs.setString(
            '${keyBase}_secondary_path', secondaryOption.filePath!);
      }
      await prefs.setString('${keyBase}_secondary_id', secondaryOption.id);
    }
  } catch (e) {
    developer.log('Error saving subtitle selection: $e',
        name: 'SubtitlePersistence');
  }
}

/// Restores saved subtitle choices for a video URI from SharedPreferences.
Future<void> restoreMediaSubtitleSelection({
  required String videoUri,
  required dynamic ref,
  required List<SubtitleTrackOption> availableOptions,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final keyBase = _getSubtitleSelectionKey(videoUri);

    final primaryPath = prefs.getString('${keyBase}_primary_path');
    final primaryId = prefs.getString('${keyBase}_primary_id');

    final secondaryPath = prefs.getString('${keyBase}_secondary_path');
    final secondaryId = prefs.getString('${keyBase}_secondary_id');

    if (primaryPath != null || primaryId != null) {
      SubtitleTrackOption? match;
      for (final opt in availableOptions) {
        if ((primaryPath != null && opt.filePath == primaryPath) ||
            (primaryId != null && opt.id == primaryId)) {
          match = opt;
          break;
        }
      }
      if (match != null) {
        if (ref is WidgetRef) {
          ref.read(selectedSubtitleProvider.notifier).state = match;
        } else if (ref is ProviderContainer) {
          ref.read(selectedSubtitleProvider.notifier).state = match;
        }
      }
    }

    if (secondaryPath != null || secondaryId != null) {
      SubtitleTrackOption? matchSec;
      for (final opt in availableOptions) {
        if ((secondaryPath != null && opt.filePath == secondaryPath) ||
            (secondaryId != null && opt.id == secondaryId)) {
          matchSec = opt;
          break;
        }
      }
      if (matchSec != null) {
        if (ref is WidgetRef) {
          ref.read(selectedSecondarySubtitleProvider.notifier).state = matchSec;
        } else if (ref is ProviderContainer) {
          ref.read(selectedSecondarySubtitleProvider.notifier).state = matchSec;
        }
      }
    }
  } catch (e) {
    developer.log('Error restoring subtitle selection: $e',
        name: 'SubtitlePersistence');
  }
}
