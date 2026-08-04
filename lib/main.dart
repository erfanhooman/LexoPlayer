import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'dart:io';
import 'package:window_manager/window_manager.dart';

import 'package:lexo_player/core/theme/app_colors.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';

import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

import 'package:lexo_player/core/services/now_playing_service.dart';
import 'package:lexo_player/features/video_player/presentation/video_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize media_kit native engine & window manager ──────────────────────────────
  MediaKit.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // ── 2. Initialize cross-platform SQLite ────────────────────────────────
  await DatabaseService.initialize();

  // ── 3. Detect video file passed via OS file association / Open With ──
  String? initialVideoUri;
  for (final arg in args) {
    final lower = arg.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.ts')) {
      initialVideoUri = arg;
      break;
    }
  }

  // ── 4. Launch the application ──────────────────────────────────────────
  runApp(
    ProviderScope(
      child: LexoPlayerApp(initialVideoUri: initialVideoUri),
    ),
  );
}

/// Root application widget.
class LexoPlayerApp extends ConsumerStatefulWidget {
  final String? initialVideoUri;
  const LexoPlayerApp({super.key, this.initialVideoUri});

  @override
  ConsumerState<LexoPlayerApp> createState() => _LexoPlayerAppState();
}

class _LexoPlayerAppState extends ConsumerState<LexoPlayerApp> {
  @override
  void initState() {
    super.initState();
    _initializeManifestSystem();
  }

  /// Hydrates the dictionary system from persistent storage and kicks off
  /// the reactive database switcher.
  Future<void> _initializeManifestSystem() async {
    // Load previously downloaded dictionary IDs from shared_preferences.
    await hydrateDownloadedIds(ref);

    // Load persisted dictionary selections.
    await hydrateSelections(ref);

    // Load persisted subtitle settings.
    await hydrateSubtitleSettings(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Watch the switcher so it fires whenever selections change.
    ref.watch(dictionarySwitcherProvider);
    // Watch the subtitle sync globally so it runs across all routes (including native fullscreen).
    ref.watch(playerSubtitleSyncProvider);
    // Watch OS Now Playing sync globally (macOS Menu Bar / Control Center / Background Media Keys).
    ref.watch(nowPlayingSyncProvider);

    return MaterialApp(
      title: 'LexoPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E24),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2C2C35), width: 1),
          ),
          textStyle: const TextStyle(color: Colors.white70, fontSize: 12),
          waitDuration: const Duration(milliseconds: 500),
        ),
      ),
      home: widget.initialVideoUri != null
          ? VideoScreen(videoUri: widget.initialVideoUri)
          : const MainMenuScreen(),
    );
  }
}
