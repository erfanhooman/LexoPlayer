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
const String kPendingUpdateTagKey = 'pending_update_tag';
const String kPendingUpdatePathKey = 'pending_update_path';
const String kPendingUpdateAssetKey = 'pending_update_asset';

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

/// A fully downloaded update file waiting for the user to install it.
/// Null = nothing staged. Survives restarts via SharedPreferences.
final pendingUpdateProvider = StateProvider<PendingUpdate?>((ref) => null);

/// A downloaded installer file staged in the updates folder.
class PendingUpdate {
  /// Release tag the file belongs to (e.g. `v2.3.3-beta`).
  final String tag;

  /// Absolute file path of the staged installer.
  final String path;

  /// Original asset file name (e.g. `LexoPlayer-macOS.zip`).
  final String assetName;

  const PendingUpdate({
    required this.tag,
    required this.path,
    required this.assetName,
  });

  /// True for the macOS ZIP flow that installs itself + relaunches.
  bool get isSelfInstall => isSelfInstallAsset(assetName);

  /// True for a Linux AppImage staged on a Linux device (in-place replace +
  /// relaunch, mirroring the macOS ZIP flow).
  bool get isInPlaceAppImage =>
      Platform.isLinux && assetName.toLowerCase().endsWith('.appimage');
}

/// True when [fileName] is a macOS self-install archive (ZIP picked by
/// [pickPlatformAsset] that the app can install + relaunch from).
bool isSelfInstallAsset(String fileName) =>
    Platform.isMacOS && fileName.toLowerCase().endsWith('.zip');

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

/// Pure core of [pickPlatformAsset]: returns the first asset (lowercased
/// name + url) matching the first satisfied preference test.
///
/// Split out so every platform's selection rule is unit-testable without
/// running on that OS.
Map<String, String>? matchAsset(
  List<dynamic> assets,
  List<bool Function(String name)> preferences,
) {
  final names = assets
      .whereType<Map<String, dynamic>>()
      .map((a) => (
            name: (a['name'] as String? ?? '').toLowerCase(),
            url: a['browser_download_url'] as String? ?? '',
          ))
      .where((e) => e.url.isNotEmpty)
      .toList();
  if (names.isEmpty) return null;
  for (final test in preferences) {
    for (final e in names) {
      if (test(e.name)) return {'name': e.name, 'url': e.url};
    }
  }
  return null;
}

/// Picks the installer asset matching the current platform from a
/// GitHub release `assets` list.
Map<String, String>? pickPlatformAsset(List<dynamic> assets) {
  if (Platform.isMacOS) {
    // Prefer the self-install ZIP (auto-install + relaunch, no drag needed).
    // Fall back to the DMG (manual drag-to-Applications) when no ZIP exists
    // — e.g. releases published before the ZIP asset was added.
    return matchAsset(assets, [
      (n) => n.endsWith('.zip') && n.contains('mac'),
      (n) => n.endsWith('.dmg'),
    ]);
  } else if (Platform.isWindows) {
    return matchAsset(assets, [(n) => n.endsWith('.exe')]);
  } else if (Platform.isLinux) {
    return matchAsset(assets, [(n) => n.endsWith('.appimage')]);
  } else if (Platform.isAndroid) {
    return matchAsset(assets, [(n) => n.endsWith('.apk')]);
  } else if (Platform.isIOS) {
    return matchAsset(assets, [(n) => n.endsWith('.ipa')]);
  }
  return null;
}

/// True when staged in-app downloads are supported on a platform.
///
/// Android/iOS are excluded: shared Downloads is not writable via raw file
/// APIs (scoped storage, Android 10+) and installing a package needs native
/// FileProvider + install-intent code — so those platforms hand the asset
/// URL to the system browser/Download Manager instead.
bool stagedDownloadSupported({required bool isAndroid, required bool isIOS}) =>
    !isAndroid && !isIOS;

/// Resolves the running `<Name>.app` bundle from an executable path.
///
/// E.g. `/Applications/Lexo.app/Contents/MacOS/lexo_player` →
/// `/Applications/Lexo.app`. Returns null when no `.app` ancestor exists
/// (Windows/Linux/Android layouts).
String? findMacAppBundle(String executablePath) {
  final parts = p.split(executablePath);
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].toLowerCase().endsWith('.app')) {
      return p.joinAll(parts.sublist(0, i + 1));
    }
  }
  return null;
}

/// Resolves the currently running Linux AppImage file, if any.
///
/// Prefers the `APPIMAGE` env var set by the AppImage runtime; otherwise
/// accepts the resolved executable itself when it is an `.AppImage` file.
/// Returns null for dev/bundle runs (nothing to replace in place).
/// [environment]/[executablePath] are injectable for unit tests.
String? resolveLinuxAppImagePath(
    {Map<String, String>? environment, String? executablePath}) {
  final env = environment ?? Platform.environment;
  final fromEnv = env['APPIMAGE'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final exe = executablePath ?? Platform.resolvedExecutable;
  if (exe.toLowerCase().endsWith('.appimage')) return exe;
  return null;
}

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
      await loadPendingUpdate(ref);
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
  ///
  /// Also syncs [dictChecksumProvider] so the updates-available list and
  /// Dictionary UI react immediately (no restart needed).
  static Future<void> recordDictionaryChecksum(
      dynamic ref, String dictId, String md5) async {
    if (md5.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dictMd5Key(dictId), md5);
    try {
      ref.read(dictChecksumProvider.notifier).state = {
        ...ref.read(dictChecksumProvider),
        dictId: md5,
      };
    } catch (_) {}
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
          await recordDictionaryChecksum(ref, entry.id, entry.md5Checksum);
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
        if (savedMd5 != null && savedMd5 == entry.md5Checksum) continue;

        developer.log(
          'New dictionary version detected for "${entry.displayName}". Auto-updating from GitHub...',
          name: 'AutoUpdateService',
        );

        ref.read(dictAutoUpdateStatusProvider.notifier).state =
            'Auto-updating ${entry.displayName}...';

        await downloadService.downloadDictionary(entry);
        await recordDictionaryChecksum(ref, entry.id, entry.md5Checksum);
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
      await _reconcilePending(ref, tagName);

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

  /// Folder where downloaded updates are staged, so the user can always find
  /// them in Finder: `~/Downloads/LexoPlayer-Updates/`.
  static Future<Directory> updatesDirectory() async {
    final base = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'LexoPlayer-Updates'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Restores a previously staged update file (if it still exists on disk).
  static Future<void> loadPendingUpdate(dynamic ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tag = prefs.getString(kPendingUpdateTagKey);
      final path = prefs.getString(kPendingUpdatePathKey);
      final asset = prefs.getString(kPendingUpdateAssetKey) ?? '';
      if (tag != null && path != null && File(path).existsSync()) {
        ref.read(pendingUpdateProvider.notifier).state =
            PendingUpdate(tag: tag, path: path, assetName: asset);
      } else if (tag != null || path != null) {
        await _clearPendingRecord();
        ref.read(pendingUpdateProvider.notifier).state = null;
      }
    } catch (_) {}
  }

  static Future<void> _savePendingRecord(PendingUpdate pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingUpdateTagKey, pending.tag);
    await prefs.setString(kPendingUpdatePathKey, pending.path);
    await prefs.setString(kPendingUpdateAssetKey, pending.assetName);
  }

  static Future<void> _clearPendingRecord() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPendingUpdateTagKey);
    await prefs.remove(kPendingUpdatePathKey);
    await prefs.remove(kPendingUpdateAssetKey);
  }

  /// Drops a staged update that no longer matches the latest release
  /// (deletes the stale file so the folder never fills with old installers).
  static Future<void> _reconcilePending(dynamic ref, String latestTag) async {
    try {
      final pending = ref.read(pendingUpdateProvider) as PendingUpdate?;
      if (pending != null && pending.tag != latestTag) {
        try {
          final f = File(pending.path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
        await _clearPendingRecord();
        ref.read(pendingUpdateProvider.notifier).state = null;
      }
    } catch (_) {}
  }

  /// Reveals [path] in the OS file manager (Finder on macOS).
  static Future<void> revealInFinder(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.start('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.start('explorer', ['/select,', path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [p.dirname(path)]);
      } else {
        final uri = Uri.file(p.dirname(path));
        if (await canLaunchUrl(uri)) await launchUrl(uri);
      }
    } catch (e) {
      developer.log('Could not reveal $path: $e', name: 'AutoUpdateService');
    }
  }

  /// Step 1 — downloads the pending update into the `LexoPlayer-Updates`
  /// folder, records it, and reveals it in Finder.
  ///
  /// When the file for this tag is already staged, it is NOT re-downloaded —
  /// the existing file is simply revealed and reported as ready.
  static Future<String?> downloadUpdate(
    dynamic ref, {
    void Function(int received, int total)? onProgress,
  }) async {
    final info = ref.read(appUpdateInfoProvider) as AppUpdateInfo?;
    if (info == null || !info.hasUpdate) return null;
    if (info.assetUrl == null) {
      await openReleasePage(ref);
      return null;
    }
    if (!stagedDownloadSupported(
        isAndroid: Platform.isAndroid, isIOS: Platform.isIOS)) {
      // Mobile: no reliable in-app staging (scoped storage blocks raw writes
      // to shared Downloads; installing needs native FileProvider code).
      // Hand the asset URL to the system browser/Download Manager — the OS
      // package installer takes it from there (tap the APK, allow
      // "install unknown apps" once when asked).
      ref.read(appUpdateStatusProvider.notifier).state =
          'Opening browser to download ${info.latestTag} — tap the downloaded file to install.';
      await _openWebUrl(info.assetUrl!);
      return null;
    }
    ref.read(appUpdateDownloadingProvider.notifier).state = true;
    ref.read(appUpdateProgressProvider.notifier).state = 0.0;
    try {
      final dir = await updatesDirectory();
      final fileName =
          info.assetName ?? 'LexoPlayer-update${_extForPlatform()}';
      final savePath = p.join(dir.path, fileName);

      if (File(savePath).existsSync()) {
        // Already downloaded (e.g. from a previous launch) — reuse it.
        final pending = PendingUpdate(
            tag: info.latestTag, path: savePath, assetName: fileName);
        await _savePendingRecord(pending);
        ref.read(pendingUpdateProvider.notifier).state = pending;
        ref.read(appUpdateStatusProvider.notifier).state =
            'Update ${info.latestTag} is already downloaded — ready to install.';
        await revealInFinder(savePath);
        return savePath;
      }

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

      // Linux: a downloaded AppImage has no executable bit — without this
      // neither double-click nor xdg-open can launch it.
      if (Platform.isLinux && savePath.toLowerCase().endsWith('.appimage')) {
        try {
          await Process.run('chmod', ['+x', savePath]);
        } catch (e) {
          developer.log('chmod +x failed for $savePath: $e',
              name: 'AutoUpdateService');
        }
      }

      final pending = PendingUpdate(
          tag: info.latestTag, path: savePath, assetName: fileName);
      await _savePendingRecord(pending);
      ref.read(pendingUpdateProvider.notifier).state = pending;
      ref.read(appUpdateStatusProvider.notifier).state =
          'Downloaded ${info.latestTag} — ready to install from LexoPlayer-Updates.';
      await revealInFinder(savePath);
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

  /// Step 2 — installs a previously staged update (no re-download).
  ///
  /// macOS ZIP: swaps the running bundle in place and relaunches the app.
  /// Anything else: opens the staged file so the OS installer takes over.
  /// Returns true when an install was started.
  static Future<bool> installPendingUpdate(dynamic ref) async {
    final pending = ref.read(pendingUpdateProvider) as PendingUpdate?;
    if (pending == null) return false;
    if (!File(pending.path).existsSync()) {
      await _clearPendingRecord();
      ref.read(pendingUpdateProvider.notifier).state = null;
      ref.read(appUpdateStatusProvider.notifier).state =
          'Staged update file is gone — please download again.';
      return false;
    }
    if (pending.isSelfInstall) {
      ref.read(appUpdateStatusProvider.notifier).state =
          'Installing ${pending.tag} & restarting…';
      final newBundle = await _installMacZipUpdate(ref, pending.path);
      if (newBundle != null) {
        await _clearPendingRecord();
        await Process.start('open', [newBundle]);
        exit(0);
      }
      // Self-install not possible here — fall through to reveal for manual.
      ref.read(appUpdateStatusProvider.notifier).state =
          'Automatic install needs write access — opening the file for manual install…';
      await revealInFinder(pending.path);
      return true;
    }
    if (pending.isInPlaceAppImage) {
      ref.read(appUpdateStatusProvider.notifier).state =
          'Installing ${pending.tag} & restarting…';
      final launched = await _installLinuxAppImageUpdate(ref, pending.path);
      if (launched != null) {
        await _clearPendingRecord();
        await Process.start(launched, const [],
            mode: ProcessStartMode.detached);
        exit(0);
      }
      ref.read(appUpdateStatusProvider.notifier).state =
          'Automatic install needs write access — opening the file for manual install…';
      await revealInFinder(pending.path);
      return true;
    }
    // Windows EXE / DMG / APK etc: open the staged file so the OS
    // installer (Inno wizard, disk image mounter, package installer)
    // takes over. The wizard handles the running-app case itself.
    await _openFile(pending.path);
    return true;
  }

  /// Replaces the currently running Linux AppImage with [newPath] and
  /// returns its path for the caller to launch (then exit).
  ///
  /// Returns null when self-install isn't possible (not running as an
  /// AppImage, or its folder isn't writable).
  static Future<String?> _installLinuxAppImageUpdate(
      dynamic ref, String newPath) async {
    try {
      final current = resolveLinuxAppImagePath();
      if (current == null || !File(current).existsSync()) return null;
      final dir = p.dirname(current);

      final probe = File(p.join(
          dir, '.lexo_write_test_${DateTime.now().millisecondsSinceEpoch}'));
      try {
        await probe.create();
        await probe.delete();
      } catch (_) {
        developer.log('Self-install skipped: $dir not writable',
            name: 'AutoUpdateService');
        return null;
      }

      // Rename aside first (same dir ⇒ same volume, and avoids ETXTBSY from
      // overwriting a running executable), then copy the new file in.
      final backupPath = '$current.before-update';
      try {
        if (File(backupPath).existsSync()) await File(backupPath).delete();
        await File(current).rename(backupPath);
        await File(newPath).copy(current);
        await Process.run('chmod', ['+x', current]);
      } catch (e) {
        try {
          if (File(backupPath).existsSync() && !File(current).existsSync()) {
            await File(backupPath).rename(current);
          }
        } catch (_) {}
        developer.log('Linux self-install swap failed: $e',
            name: 'AutoUpdateService');
        return null;
      }

      try {
        ref.read(appUpdateStatusProvider.notifier).state =
            'Installed — restarting…';
      } catch (_) {}
      try {
        if (File(backupPath).existsSync()) await File(backupPath).delete();
      } catch (_) {}
      try {
        await File(newPath).delete();
      } catch (_) {}
      return current;
    } catch (e) {
      developer.log('Linux self-install failed: $e', name: 'AutoUpdateService');
      return null;
    }
  }

  /// Replaces the currently running macOS bundle with the app from [zipPath].
  ///
  /// Returns the new bundle path on success (the caller launches it and
  /// exits), or null when self-install isn't possible (the caller falls back
  /// to opening the file for a manual install).
  static Future<String?> _installMacZipUpdate(
      dynamic ref, String zipPath) async {
    try {
      final bundlePath = findMacAppBundle(Platform.resolvedExecutable);
      if (bundlePath == null) return null;
      // Running straight from a mounted DMG — can't replace in place.
      if (bundlePath.startsWith('/Volumes/')) return null;
      final parentDir = p.dirname(bundlePath);

      // The bundle's parent must be writable (no admin rights to escalate to
      // silently — a password prompt here would be worse than the old drag).
      final probe = File(p.join(parentDir,
          '.lexo_write_test_${DateTime.now().millisecondsSinceEpoch}'));
      try {
        await probe.create();
        await probe.delete();
      } catch (_) {
        developer.log('Self-install skipped: $parentDir not writable',
            name: 'AutoUpdateService');
        return null;
      }

      final tmp = await Directory.systemTemp.createTemp('lexo_update_');
      try {
        // ditto preserves symlinks, permissions and resource forks inside
        // the .app bundle — safer than a pure-Dart unzip for app bundles.
        final extract =
            await Process.run('ditto', ['-x', '-k', zipPath, tmp.path]);
        if (extract.exitCode != 0) return null;

        Directory? newApp;
        for (final e in tmp.listSync()) {
          if (e is Directory && e.path.toLowerCase().endsWith('.app')) {
            newApp = e;
            break;
          }
        }
        if (newApp == null) return null;

        // Belt-and-braces: in-app downloads carry no quarantine flag, but if
        // one is present the relaunched app would hit Gatekeeper.
        try {
          await Process.run(
              'xattr', ['-dr', 'com.apple.quarantine', newApp.path]);
        } catch (_) {}

        // Swap aside → copy new in (ditto, same fidelity as extract).
        final backupPath = '$bundlePath.before-update';
        try {
          if (Directory(backupPath).existsSync()) {
            await Directory(backupPath).delete(recursive: true);
          }
          await Directory(bundlePath).rename(backupPath);
          final copy = await Process.run('ditto', [newApp.path, bundlePath]);
          if (copy.exitCode != 0) throw Exception('ditto copy failed');
        } catch (e) {
          // Restore the old bundle so the user is never left app-less.
          try {
            if (Directory(backupPath).existsSync() &&
                !Directory(bundlePath).existsSync()) {
              await Directory(backupPath).rename(bundlePath);
            }
          } catch (_) {}
          developer.log('Self-install swap failed: $e',
              name: 'AutoUpdateService');
          return null;
        }

        try {
          ref.read(appUpdateStatusProvider.notifier).state =
              'Installed — restarting…';
        } catch (_) {}

        try {
          if (Directory(backupPath).existsSync()) {
            await Directory(backupPath).delete(recursive: true);
          }
        } catch (_) {}
        try {
          await File(zipPath).delete();
        } catch (_) {}
        return bundlePath;
      } finally {
        try {
          if (tmp.existsSync()) await tmp.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      developer.log('macOS self-install failed: $e', name: 'AutoUpdateService');
      return null;
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
    await _openWebUrl(url);
  }

  /// Opens an https URL in the system browser (used for release pages and
  /// mobile asset downloads handed to the OS Download Manager).
  static Future<void> _openWebUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      developer.log('Could not open $url: $e', name: 'AutoUpdateService');
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
