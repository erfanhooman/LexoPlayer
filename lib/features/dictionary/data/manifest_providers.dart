import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/manifest_service.dart';
import 'package:lexo_player/core/services/dict_storage_manager.dart';
import 'package:lexo_player/core/services/dict_download_service.dart';

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
}
