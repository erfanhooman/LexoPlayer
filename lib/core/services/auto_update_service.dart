import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

const String kAutoUpdateAppKey = 'auto_update_app';
const String kAutoUpdateDictKey = 'auto_update_dict';
const String kSkippedAppVersionKey = 'skipped_app_version';
const String kLastSeenAppVersionKey = 'last_seen_app_version';

/// State provider for Auto Update App toggle (default: true)
final autoUpdateAppProvider = StateProvider<bool>((ref) => true);

/// State provider for Auto Update Dictionaries toggle (default: true)
final autoUpdateDictProvider = StateProvider<bool>((ref) => true);

/// Human-readable app update status (kept for backwards compatibility,
/// now actually surfaced in Settings + update dialog).
final appUpdateStatusProvider = StateProvider<String?>((ref) => null);

/// Human-readable dictionary auto-update status (surfaced in DictionaryPanel).
final dictAutoUpdateStatusProvider = StateProvider<String?>((ref) => null);

/// Structured app-update state. Null = not checked yet.
final appUpdateInfoProvider = StateProvider<AppUpdateInfo?>((ref) => null);

/// 0.0–1.0 download progress while an installer is downloading. Null = idle.
final appUpdateProgressProvider = StateProvider<double?>((ref) => null);

/// True while the installer file is being downloaded.
final appUpdateDownloadingProvider = StateProvider<bool>((ref) => false);

/// Structured description of the latest GitHub release vs the installed build.
class AppUpdateInfo {
  final String currentVersion;
  final String latestTag;
  final String latestVersion;
  final bool hasUpdate;
  final String? assetName;
  final String? assetUrl;
  final String htmlUrl;
  final String releaseNotes;
  final bool isPrerelease;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestTag,
    required this.latestVersion,
    required this.hasUpdate,
    this.assetName,
    this.assetUrl,
    required this.htmlUrl,
    required this.releaseNotes,
    required this.isPrerelease,
  });
}

/// Compares two version strings (e.g. "2.2.0-beta+4" vs "v2.3.0-beta").
///
/// Returns < 0 if [a] < [b], 0 if equal, > 0 if [a] > [b].
/// Handles leading `v`, build metadata (`+...`), and pre-release suffixes
/// (`-beta`, `-rc.1`). Unknown/non-semver tags fall back to raw comparison
/// returning 0 (treated as "no update") unless the normaliser finds numbers.
int compareVersions(String a, String b) {
  final na = _normalize(a);
  final nb = _normalize(b);
  if (na == null || nb == null) {
    // Unparseable legacy tags (e.g. "beta-2"): only equal when identical.
    if (a.trim() == b.trim()) return 0;
    return 0;
  }
  for (var i = 0; i < na.core.length || i < nb.core.length; i++) {
    final x = i < na.core.length ? na.core[i] : 0;
    final y = i < nb.core.length ? nb.core[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  // Core equal: a release beats any pre-release.
  if (na.pre == null && nb.pre != null) return 1;
  if (na.pre != null && nb.pre == null) return -1;
  if (na.pre == null && nb.pre == null) return 0;
  return na.pre!.compareTo(nb.pre!);
}

class _NormalizedVersion {
  final List<int> core;
  final String? pre;
  _NormalizedVersion(this.core, this.pre);
}

_NormalizedVersion? _normalize(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  // Strip build metadata.
  s = s.split('+').first;
  // Split pre-release.
  String corePart = s;
  String? pre;
  final dash = s.indexOf('-');
  if (dash != -1) {
    corePart = s.substring(0, dash);
    pre = s.substring(dash + 1).toLowerCase();
  }
  // Legacy "beta-2" style: core part without dots — try to find numbers.
  final numMatch = RegExp(r'\d+(\.\d+)*').firstMatch(corePart);
  if (numMatch == null) {
    // Try the whole string (covers "beta2", "beta_v2.0.1", ...).
    final fallback = RegExp(r'\d+(\.\d+)*').firstMatch(s);
    if (fallback == null) return null;
    corePart = fallback.group(0)!;
    pre ??= 'beta';
  } else {
    corePart = numMatch.group(0)!;
  }
  final core = corePart.split('.').map(int.tryParse).toList();
  if (core.any((e) => e == null)) return null;
  return _NormalizedVersion(core.cast<int>(), pre);
}

/// Picks the installer asset matching the current platform from a
/// GitHub release `assets` list.
Map<String, String>? pickPlatformAsset(List<dynamic> assets) {
  final names = assets
      .whereType<Map<String, dynamic>>()
      .map((a) => (
            name: (a['name'] as String? ?? '').toLowerCase(),
            url: a['browser_download_url'] as String? ?? '',
          ))
      .where((e) => e.url.isNotEmpty)
      .toList();
  if (names.isEmpty) return null;

  String? want;
  if (Platform.isMacOS) {
    want = '.dmg';
  } else if (Platform.isWindows) {
    want = '.exe';
  } else if (Platform.isLinux) {
    want = '.appimage';
  } else if (Platform.isAndroid) {
    want = '.apk';
  } else if (Platform.isIOS) {
    want = '.ipa';
  }
  if (want != null) {
    for (final e in names) {
      if (e.name.endsWith(want)) {
        return {'name': e.name, 'url': e.url};
      }
    }
  }
  return null;
}

String dictMd5Key(String dictId) => 'dict_md5_$dictId';

class AutoUpdateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const _releaseUrl =
      'https://api.github.com/repos/erfanhooman/LexoPlayer/releases/latest';

  /// Initializes auto-update settings from SharedPreferences
  static Future<void> init(WidgetRef ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoApp = prefs.getBool(kAutoUpdateAppKey) ?? true;
      final autoDict = prefs.getBool(kAutoUpdateDictKey) ?? true;

      ref.read(autoUpdateAppProvider.notifier).state = autoApp;
      ref.read(autoUpdateDictProvider.notifier).state = autoDict;

      // Run sequentially: dictionaries first (engine needs the DB),
      // then the app check (only populates state; UI decides to prompt).
      if (autoDict) {
        await checkAndAutoUpdateDictionaries(ref);
      }
      if (autoApp) {
        await checkAndAutoUpdateApp(ref);
      }
    } catch (e) {
      developer.log('Error initializing AutoUpdateService: $e',
          name: 'AutoUpdateService');
    }
  }

  /// Sets auto-update app preference
  static Future<void> setAutoUpdateApp(WidgetRef ref, bool value) async {
    ref.read(autoUpdateAppProvider.notifier).state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoUpdateAppKey, value);
    if (value) {
      await checkAndAutoUpdateApp(ref);
    }
  }

  /// Sets auto-update dictionaries preference
  static Future<void> setAutoUpdateDict(WidgetRef ref, bool value) async {
    ref.read(autoUpdateDictProvider.notifier).state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoUpdateDictKey, value);
    if (value) {
      await checkAndAutoUpdateDictionaries(ref);
    }
  }

  /// Persists the manifest checksum after ANY successful dictionary install
  /// (manual hub download or auto-update) so the next auto-check can diff.
  static Future<void> recordDictionaryChecksum(
      String dictId, String md5) async {
    if (md5.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dictMd5Key(dictId), md5);
  }

  /// Auto-discovery + auto-update for dictionaries:
  ///
  /// 1. Fetches the remote manifest (network-first, cache fallback).
  /// 2. If nothing is installed yet, auto-downloads the first unified
  ///    dictionary (fresh-install autodiscovery).
  /// 3. Otherwise re-downloads any installed dictionary whose manifest
  ///    MD5 differs from the last installed one.
  static Future<void> checkAndAutoUpdateDictionaries(dynamic ref) async {
    try {
      final manifestService = ref.read(manifestServiceProvider);
      final storage = ref.read(dictStorageManagerProvider);
      final downloadService = ref.read(dictDownloadServiceProvider);

      final manifest = await manifestService.fetchManifest();
      var downloadedIds = await storage.getDownloadedIds();
      final prefs = await SharedPreferences.getInstance();

      // ── Fresh install: autodiscover + auto-download the default dict ──
      if (downloadedIds.isEmpty && manifest.unified.isNotEmpty) {
        final entry = manifest.unified.first;
        developer.log(
          'No dictionaries installed. Auto-downloading "${entry.displayName}"…',
          name: 'AutoUpdateService',
        );
        ref.read(dictAutoUpdateStatusProvider.notifier).state =
            'Downloading ${entry.displayName}…';
        try {
          await downloadService.downloadDictionary(entry);
          await prefs.setString(dictMd5Key(entry.id), entry.md5Checksum);
          downloadedIds = await storage.getDownloadedIds();
          _syncDownloadedIds(ref, downloadedIds);

          // Auto-select it when nothing is selected yet.
          try {
            final current = ref.read(selectedUnifiedDictIdProvider);
            if (current == null) {
              ref.read(selectedUnifiedDictIdProvider.notifier).state = entry.id;
              await storage.setSelectedUnifiedId(entry.id);
            }
          } catch (_) {}
          try {
            ref.invalidate(engineInitProvider);
          } catch (_) {}

          ref.read(dictAutoUpdateStatusProvider.notifier).state =
              'Dictionary "${entry.displayName}" installed!';
        } catch (e) {
          developer.log('Dictionary auto-download failed: $e',
              name: 'AutoUpdateService');
          ref.read(dictAutoUpdateStatusProvider.notifier).state =
              'Dictionary auto-download failed. Open Dictionaries to retry.';
        }
        return;
      }

      // ── Steady state: update any installed dict with a new checksum ──
      var updatedAny = false;
      for (final entry in manifest.all) {
        if (!downloadedIds.contains(entry.id)) continue;

        final savedMd5 = prefs.getString(dictMd5Key(entry.id));

        // Missing saved MD5 (e.g. installed before this tracking existed):
        // record it only when it already matches, otherwise update.
        if (savedMd5 == null) {
          if (entry.md5Checksum.isEmpty) continue;
          // File on disk was verified at download time against an older
          // manifest; without a baseline we cannot prove staleness, so we
          // baseline it now instead of forcing a 30 MB re-download.
          await prefs.setString(dictMd5Key(entry.id), entry.md5Checksum);
          continue;
        }
        if (savedMd5 == entry.md5Checksum) continue;

        developer.log(
          'New dictionary version detected for "${entry.displayName}". Auto-updating from GitHub...',
          name: 'AutoUpdateService',
        );

        ref.read(dictAutoUpdateStatusProvider.notifier).state =
            'Auto-updating ${entry.displayName}...';

        await downloadService.downloadDictionary(entry);
        await prefs.setString(dictMd5Key(entry.id), entry.md5Checksum);
        updatedAny = true;

        // If this dictionary is currently active, reload the engine.
        try {
          final activeUnifiedId = ref.read(selectedUnifiedDictIdProvider);
          if (activeUnifiedId == entry.id) {
            ref.invalidate(engineInitProvider);
          }
        } catch (_) {}

        ref.read(dictAutoUpdateStatusProvider.notifier).state =
            'Dictionary "${entry.displayName}" updated to latest version!';
      }

      if (updatedAny) {
        final ids = await storage.getDownloadedIds();
        _syncDownloadedIds(ref, ids);
      }
    } catch (e) {
      developer.log('Error during dictionary auto-update: $e',
          name: 'AutoUpdateService');
    }
  }

  static void _syncDownloadedIds(dynamic ref, List<String> ids) {
    try {
      ref.read(downloadedDictIdsProvider.notifier).state = ids;
    } catch (_) {}
  }

  /// Checks GitHub Releases for a newer app build.
  ///
  /// Populates [appUpdateInfoProvider] + [appUpdateStatusProvider].
  /// Returns the info (null on network failure). Does NOT download —
  /// call [downloadAndInstallUpdate] after user confirmation.
  static Future<AppUpdateInfo?> checkAndAutoUpdateApp(dynamic ref,
      {bool manual = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version; // e.g. 2.2.0-beta+4 -> "2.2.0-beta"

      final response = await _dio.get<Map<String, dynamic>>(_releaseUrl);
      if (response.statusCode != 200 || response.data == null) {
        if (manual) {
          ref.read(appUpdateStatusProvider.notifier).state =
              'Update check failed (HTTP ${response.statusCode}).';
        }
        return ref.read(appUpdateInfoProvider);
      }

      final data = response.data!;
      final tagName = data['tag_name'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final body = data['body'] as String? ?? '';
      final prerelease = data['prerelease'] as bool? ?? false;
      final assets = data['assets'] as List<dynamic>? ?? const [];

      if (tagName.isEmpty) return ref.read(appUpdateInfoProvider);

      final latestVersion = tagName.startsWith('v') || tagName.startsWith('V')
          ? tagName.substring(1)
          : tagName;
      final cmp = compareVersions(current, tagName);
      final asset = pickPlatformAsset(assets);

      final info = AppUpdateInfo(
        currentVersion: current,
        latestTag: tagName,
        latestVersion: latestVersion,
        hasUpdate: cmp < 0,
        assetName: asset?['name'],
        assetUrl: asset?['url'],
        htmlUrl: htmlUrl,
        releaseNotes: body,
        isPrerelease: prerelease,
      );
      ref.read(appUpdateInfoProvider.notifier).state = info;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLastSeenAppVersionKey, tagName);

      if (info.hasUpdate) {
        ref.read(appUpdateStatusProvider.notifier).state =
            'Update available: $tagName (installed: $current)';
      } else if (manual) {
        ref.read(appUpdateStatusProvider.notifier).state =
            'You are on the latest version ($current).';
      } else {
        ref.read(appUpdateStatusProvider.notifier).state =
            'Latest GitHub Release: $tagName';
      }
      return info;
    } catch (e) {
      developer.log('App update check skipped: $e', name: 'AutoUpdateService');
      if (manual) {
        try {
          ref.read(appUpdateStatusProvider.notifier).state =
              'Update check failed: offline?';
        } catch (_) {}
      }
      try {
        return ref.read(appUpdateInfoProvider);
      } catch (_) {
        return null;
      }
    }
  }

  /// Downloads the platform installer for the pending update and opens it
  /// so the OS installer takes over (DMG on macOS, Setup EXE on Windows,
  /// AppImage on Linux, APK on Android).
  static Future<String?> downloadAndInstallUpdate(
    dynamic ref, {
    void Function(int received, int total)? onProgress,
  }) async {
    final info = ref.read(appUpdateInfoProvider) as AppUpdateInfo?;
    if (info == null || !info.hasUpdate) return null;
    if (info.assetUrl == null) {
      // No direct asset for this platform — open the release page instead.
      await openReleasePage(ref);
      return null;
    }
    ref.read(appUpdateDownloadingProvider.notifier).state = true;
    ref.read(appUpdateProgressProvider.notifier).state = 0.0;
    try {
      final dir =
          await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final fileName =
          info.assetName ?? 'LexoPlayer-update${_extForPlatform()}';
      final savePath = p.join(dir.path, fileName);
      await _dio.download(
        info.assetUrl!,
        savePath,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          try {
            ref.read(appUpdateProgressProvider.notifier).state = progress;
          } catch (_) {}
          onProgress?.call(received, total);
        },
      );
      ref.read(appUpdateProgressProvider.notifier).state = 1.0;
      ref.read(appUpdateStatusProvider.notifier).state =
          'Downloaded ${info.latestTag} — opening installer…';
      await _openFile(savePath);
      return savePath;
    } catch (e) {
      developer.log('App update download failed: $e',
          name: 'AutoUpdateService');
      ref.read(appUpdateStatusProvider.notifier).state =
          'Update download failed. Opening release page…';
      await openReleasePage(ref);
      return null;
    } finally {
      ref.read(appUpdateDownloadingProvider.notifier).state = false;
    }
  }

  static String _extForPlatform() {
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return '.exe';
    if (Platform.isLinux) return '.AppImage';
    if (Platform.isAndroid) return '.apk';
    return '.bin';
  }

  static Future<void> _openFile(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else if (Platform.isWindows) {
        await Process.start('explorer', [path]);
      } else {
        final uri = Uri.file(path);
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      }
    } catch (e) {
      developer.log('Could not auto-open installer $path: $e',
          name: 'AutoUpdateService');
    }
  }

  /// Opens the GitHub release page in the browser.
  static Future<void> openReleasePage(dynamic ref) async {
    final info = ref.read(appUpdateInfoProvider) as AppUpdateInfo?;
    final url = info?.htmlUrl.isNotEmpty == true
        ? info!.htmlUrl
        : 'https://github.com/erfanhooman/LexoPlayer/releases/latest';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Marks the current latest tag as "remind me later".
  static Future<void> skipThisVersion(dynamic ref) async {
    final info = ref.read(appUpdateInfoProvider) as AppUpdateInfo?;
    if (info == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSkippedAppVersionKey, info.latestTag);
  }

  /// True when the user previously dismissed this exact tag.
  static Future<bool> wasSkipped(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kSkippedAppVersionKey) == tag;
  }
}
