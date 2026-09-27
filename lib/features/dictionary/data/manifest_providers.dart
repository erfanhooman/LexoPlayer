import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/manifest_service.dart';
import 'package:lexo_player/core/services/dict_storage_manager.dart';
import 'package:lexo_player/core/services/dict_download_service.dart';

/// SharedPreferences key prefix for installed manifest checksums
/// (`dict_md5_<dictId>` → md5 hex of the installed file).
const kDictMd5Prefix = 'dict_md5_';

/// Builds the checksum prefs key for [dictId].
String dictMd5Key(String dictId) => '$kDictMd5Prefix$dictId';

// ─────────────────────────────────────────────────────────────────────────────
// Service singletons
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton [ManifestService] for fetching the remote dictionary manifest.
final manifestServiceProvider = Provider<ManifestService>((ref) {
  return ManifestService();
});

/// Singleton [DictStorageManager] for path routing and download tracking.
final dictStorageManagerProvider = Provider<DictStorageManager>((ref) {
  return DictStorageManager();
});

/// Singleton [DictDownloadService] for downloading and extracting dictionaries.
final dictDownloadServiceProvider = Provider<DictDownloadService>((ref) {
  final storageManager = ref.watch(dictStorageManagerProvider);
  return DictDownloadService(storageManager);
});

// ─────────────────────────────────────────────────────────────────────────────
// Manifest data (async fetch with cache fallback)
// ─────────────────────────────────────────────────────────────────────────────

/// Fetches the remote manifest, with local cache fallback.
///
/// Watch this provider to get the list of available dictionaries.
/// Use `ref.invalidate(manifestDataProvider)` to force a re-fetch
/// (e.g. on pull-to-refresh).
final manifestDataProvider = FutureProvider<ManifestData>((ref) async {
  final service = ref.watch(manifestServiceProvider);
  final manifest = await service.fetchManifest();
  developer.log(
    'ManifestProviders: Loaded manifest v${manifest.version} '
    '(${manifest.monolingual.length} mono, ${manifest.bilingual.length} bi)',
    name: 'ManifestProviders',
  );
  return manifest;
});

// ─────────────────────────────────────────────────────────────────────────────
// Download tracking
// ─────────────────────────────────────────────────────────────────────────────

/// The list of dictionary IDs that have been downloaded locally.
///
/// Initialised from [DictStorageManager.getDownloadedIds] and updated
/// whenever a dictionary is downloaded or deleted.
final downloadedDictIdsProvider =
    StateProvider<List<String>>((ref) => const []);

/// The list of manually loaded dictionary entries.
final manualDictEntriesProvider =
    StateProvider<List<DictionaryEntry>>((ref) => const []);

/// Tracks download progress for each actively downloading dictionary.
///
/// Key = dictionary ID, value = progress fraction (0.0 – 1.0).
/// Entries are added when a download starts and removed on completion/error.
final downloadProgressProvider =
    StateProvider<Map<String, double>>((ref) => const {});

/// Manifest MD5 recorded at install time, per downloaded dictionary ID.
///
/// Compared against the remote manifest to detect available updates.
/// Hydrated at startup; updated on every successful install.
final dictChecksumProvider =
    StateProvider<Map<String, String>>((ref) => const {});

// ─────────────────────────────────────────────────────────────────────────────
// Available updates (installed but stale vs the remote manifest)
// ─────────────────────────────────────────────────────────────────────────────

/// Dictionaries that are installed locally but whose manifest checksum has
/// changed since install — i.e. a newer version is available to install.
///
/// Empty while the manifest is loading, when nothing is installed, or when
/// everything is up to date (including right after a silent auto-update).
final dictUpdatesAvailableProvider = Provider<List<DictionaryEntry>>((ref) {
  final manifest = ref.watch(manifestDataProvider).valueOrNull;
  if (manifest == null) return const [];
  final downloaded = ref.watch(downloadedDictIdsProvider);
  if (downloaded.isEmpty) return const [];
  final checksums = ref.watch(dictChecksumProvider);
  return manifest.all
      .where((e) =>
          downloaded.contains(e.id) &&
          e.md5Checksum.isNotEmpty &&
          (checksums[e.id] == null || checksums[e.id] != e.md5Checksum))
      .toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// Download helper actions
// ─────────────────────────────────────────────────────────────────────────────

/// Initialises the [downloadedDictIdsProvider] and manual dictionaries from persistent storage.
///
/// Call this during app startup to hydrate the providers.
Future<void> hydrateDownloadedIds(WidgetRef ref) async {
  final storageManager = ref.read(dictStorageManagerProvider);

  final ids = await storageManager.getDownloadedIds();
  ref.read(downloadedDictIdsProvider.notifier).state = ids;

  final manualEntries = await storageManager.getManualDictEntries();
  ref.read(manualDictEntriesProvider.notifier).state = manualEntries;

  // Installed manifest checksums (baseline for update detection).
  try {
    final prefs = await SharedPreferences.getInstance();
    final checksums = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(kDictMd5Prefix)) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          checksums[key.substring(kDictMd5Prefix.length)] = value;
        }
      }
    }
    ref.read(dictChecksumProvider.notifier).state = checksums;
  } catch (e) {
    developer.log('Failed to hydrate dictionary checksums: $e',
        name: 'ManifestProviders');
  }
}
