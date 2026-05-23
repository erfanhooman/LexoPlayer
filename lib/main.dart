import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';

import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize media_kit native engine ──────────────────────────────
  MediaKit.ensureInitialized();

  // ── 2. Initialize cross-platform SQLite ────────────────────────────────
  await DatabaseService.initialize();

  // ── 3. Launch the application ──────────────────────────────────────────
  // Dictionary databases are no longer bootstrapped from assets.
  // Instead, they are downloaded on-demand via the manifest system and
  // initialized reactively by the dictionarySwitcherProvider.
  runApp(
    ProviderScope(
      child: const LexoPlayerApp(),
    ),
  );
}

/// Root application widget.
class LexoPlayerApp extends ConsumerStatefulWidget {
  const LexoPlayerApp({super.key});

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

    // The dictionarySwitcherProvider is watched in build(), which will
    // automatically open the selected databases once the above state
    // providers are populated.
  }

  @override
  Widget build(BuildContext context) {
    // Watch the switcher so it fires whenever selections change.
    ref.watch(dictionarySwitcherProvider);
    // Watch the subtitle sync globally so it runs across all routes (including native fullscreen).
    ref.watch(playerSubtitleSyncProvider);

    return MaterialApp(
      title: 'LexoPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0C0E), // Midnight Charcoal
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5500), // Burnt Tangerine
          brightness: Brightness.dark,
          primary: const Color(0xFFFF5500),
        ),
        useMaterial3: true,
        fontFamily: 'Helvetica Neue',
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
      home: const MainMenuScreen(),
    );
  }
}
