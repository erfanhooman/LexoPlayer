import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'dart:io';
import 'dart:ui';
import 'package:window_manager/window_manager.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';

import 'package:lexo_player/core/database/database_service.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';

import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/services/now_playing_service.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize media_kit native engine & window manager ──────────
  MediaKit.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(360, 480));
    await windowManager.setSize(const Size(1200, 800));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  // ── 2. Initialize cross-platform SQLite ────────────────────────────
  await DatabaseService.initialize();

  // ── 3. Detect video file passed via OS file association / Open With ──
  String? initialVideoUri;
  for (final arg in args) {
    final cleaned = cleanVideoPathOrUri(arg);
    if (cleaned != null) {
      initialVideoUri = cleaned;
      break;
    }
  }

  if (initialVideoUri == null && Platform.isMacOS) {
    try {
      const channel = MethodChannel('com.lexoplayer/open_file');
      final String? nativePath =
          await channel.invokeMethod<String>('getInitialFile');
      if (nativePath != null) {
        initialVideoUri = cleanVideoPathOrUri(nativePath);
      }
    } catch (_) {}
  }

  // ── 4. Launch the application ──────────────────────────────────────
  runApp(
    ProviderScope(
      child: LexoPlayerApp(initialVideoUri: initialVideoUri),
    ),
  );
}

/// Cleans and normalizes a raw file path or URI string passed via command-line
/// or OS open file event, returning a normalized local file path or URL.
String? cleanVideoPathOrUri(String rawArg) {
  var cleaned = rawArg.trim();
  if (cleaned.isEmpty) return null;

  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
      (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
    cleaned = cleaned.substring(1, cleaned.length - 1);
  }

  // 1. Direct file existence check on raw string
  if (File(cleaned).existsSync()) {
    return File(cleaned).absolute.path;
  }

  // 2. Process file:// scheme
  if (cleaned.startsWith('file://')) {
    try {
      final uri = Uri.parse(cleaned);
      final filePath = uri.toFilePath();
      if (File(filePath).existsSync()) {
        return File(filePath).absolute.path;
      }
      cleaned = filePath;
    } catch (_) {
      try {
        final stripped = cleaned.replaceFirst('file://', '');
        final decoded = Uri.decodeFull(stripped);
        if (File(decoded).existsSync()) {
          return File(decoded).absolute.path;
        }
        cleaned = decoded;
      } catch (_) {}
    }
  } else {
    try {
      final decoded = Uri.decodeFull(cleaned);
      if (File(decoded).existsSync()) {
        return File(decoded).absolute.path;
      }
      cleaned = decoded;
    } catch (_) {}
  }

  // 3. File existence check after decoding
  if (File(cleaned).existsSync()) {
    return File(cleaned).absolute.path;
  }

  // 4. Remote network URLs
  final lower = cleaned.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('rtsp://') ||
      lower.startsWith('rtmp://')) {
    return cleaned;
  }

  // 5. Video extension check for non-existent or relative paths
  final extensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.flv',
    '.m4v',
    '.3gp',
    '.ts',
    '.wmv',
    '.mpg',
    '.mpeg',
    '.vob',
    '.ogv',
    '.m2ts',
    '.divx'
  ];

  if (extensions.any((ext) => lower.endsWith(ext))) {
    return cleaned;
  }
  return null;
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

  /// Hydrates the dictionary system from persistent storage.
  Future<void> _initializeManifestSystem() async {
    await hydrateDownloadedIds(ref);
    await hydrateSelections(ref);
    await hydrateSubtitleSettings(ref);
    await AutoUpdateService.init(ref);
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers that need to run globally.
    ref.watch(unifiedDictSwitcherProvider);
    ref.watch(playerSubtitleSyncProvider);
    ref.watch(nowPlayingSyncProvider);
    // Eagerly initialize the LexoEngine.
    ref.watch(engineInitProvider);

    final lang = ref.watch(appLanguageProvider);
    final isPersian = lang == 'fa';

    return MaterialApp(
      title: 'LexoPlayer',
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      builder: (context, child) {
        return Directionality(
          textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        textTheme: (isPersian
                ? GoogleFonts.vazirmatnTextTheme(ThemeData.dark().textTheme)
                    .apply(fontFamilyFallback: [
                    'Parastoo',
                    'IRANSans',
                    'sans-serif'
                  ])
                : GoogleFonts.mulishTextTheme(ThemeData.dark().textTheme))
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
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
      home: _EngineLoadingGate(
        child: MainMenuScreen(initialVideoUri: widget.initialVideoUri),
      ),
    );
  }
}

/// Shows a loading screen while the engine initializes, then reveals
/// the actual content. Prevents the user from seeing an empty/broken UI
/// while vocab, ONNX model, and idiom cache are loading.
class _EngineLoadingGate extends ConsumerWidget {
  final Widget child;
  const _EngineLoadingGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineInit = ref.watch(engineInitProvider);

    return engineInit.when(
      data: (_) => child,
      loading: () => const _EngineLoadingScreen(),
      error: (e, _) {
        // Engine init failed — still show the app (subtitle interaction
        // won't work but the user can still browse and open videos).
        return child;
      },
    );
  }
}

/// Luxury glassmorphic loading screen shown during engine initialization.
class _EngineLoadingScreen extends ConsumerWidget {
  const _EngineLoadingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final rawStatus = ref.watch(dictLoadingStatusProvider);
    final statusMsg = rawStatus ??
        (isPersian
            ? 'در حال آماده‌سازی موتور هوشمند و واژه‌نامه...'
            : 'Initializing ONNX Engine & Vocabulary...');

    return Scaffold(
      backgroundColor: const Color(0xFF0D0C12),
      body: Stack(
        children: [
          // Ambient Glow Background Orbs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryDark.withValues(alpha: 0.15),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: const SizedBox.expand(),
          ),

          // Main Glass Card Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Icon Box
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryDark,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: -2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.psychology_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // App Title
                    RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Lexo',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextSpan(
                            text: 'Player',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w300,
                              color: AppColors.primaryLight,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtitle Status
                    Text(
                      statusMsg,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Smooth Spinner
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
