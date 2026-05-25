/// Service responsible for fetching and caching the remote dictionary manifest.
///
/// [ManifestService] downloads the latest `manifest.json` from a configurable
/// remote URL.  On success the raw JSON is persisted locally so that the app
/// can operate offline.  When the network is unreachable the most recently
/// cached manifest is returned instead.
///
/// Usage:
/// ```dart
/// final service = ManifestService();
/// final manifest = await service.fetchManifest();
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:lexo_player/core/models/manifest_models.dart';

/// Fetches, parses, and locally caches the dictionary manifest.
///
/// The service follows a **network-first, cache-fallback** strategy:
///
/// 1. Attempt to download the manifest from [_manifestUrl].
/// 2. On success, persist the raw JSON to the application documents directory
///    and return the parsed [ManifestData].
/// 3. On any network failure, attempt to load the previously cached copy.
/// 4. If no cache exists, throw an exception so the caller can show an error.
class ManifestService {
  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Remote URL that serves the latest `manifest.json`.
  ///
  /// Change this to point to your production or staging server.
  static const String _manifestUrl = 'https://erfanhooman.github.io/LexoPlayer/dictionaries/manifest.json';

  /// File name used when persisting the manifest to local storage.
  static const String _cacheFileName = 'manifest_cache.json';

  // ---------------------------------------------------------------------------
  // Dependencies
  // ---------------------------------------------------------------------------

  /// HTTP client used for all network requests.
  final Dio _dio;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a [ManifestService] with sensible default timeouts.
  ///
  /// Provide a custom [Dio] instance in tests or when you need to configure
  /// interceptors (e.g. auth headers).
  ManifestService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetches the latest manifest, falling back to the local cache on failure.
  ///
  /// Returns a fully-parsed [ManifestData] instance.
  ///
  /// Throws an [Exception] only when *both* the network request and the local
  /// cache are unavailable.
  Future<ManifestData> fetchManifest() async {
    try {
      developer.log(
        'Fetching manifest from $_manifestUrl …',
        name: 'ManifestService',
      );

      final response = await _dio.get<String>(_manifestUrl);

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> json =
            jsonDecode(response.data!) as Map<String, dynamic>;

        final manifestData = ManifestData.fromJson(json);

        // Persist in the background – don't block the caller.
        _cacheManifest(json).catchError((Object e) {
          developer.log(
            'Non-critical: failed to cache manifest – $e',
            name: 'ManifestService',
            level: 900, // WARNING
          );
        });

        developer.log(
          'Manifest fetched successfully '
          '(version ${manifestData.version}, '
          '${manifestData.all.length} dictionaries).',
          name: 'ManifestService',
        );

        return manifestData;
      }

      // Unexpected status code – fall through to cache fallback.
      developer.log(
        'Unexpected status ${response.statusCode}. '
        'Falling back to cached manifest.',
        name: 'ManifestService',
        level: 900,
      );
    } on DioException catch (e) {
      developer.log(
        'Network error while fetching manifest: ${e.message}',
        name: 'ManifestService',
        level: 900,
      );
    } on FormatException catch (e) {
      developer.log(
        'Failed to parse remote manifest JSON: $e',
        name: 'ManifestService',
        level: 1000, // SEVERE
      );
    } catch (e) {
      developer.log(
        'Unexpected error fetching manifest: $e',
        name: 'ManifestService',
        level: 1000,
      );
    }

    // ---- Fallback: try the local cache ----
    final cached = await loadCachedManifest();
    if (cached != null) {
      developer.log(
        'Loaded manifest from local cache.',
        name: 'ManifestService',
      );
      return cached;
    }

    // Neither network nor cache is available.
    throw Exception(
      'Unable to load the dictionary manifest. '
      'Please check your internet connection and try again.',
    );
  }

  /// Loads a previously cached manifest from disk.
  ///
  /// Returns `null` when the cache file does not exist or cannot be parsed.
  Future<ManifestData?> loadCachedManifest() async {
    try {
      final path = await _getCachePath();
      final file = File(path);

      if (!file.existsSync()) {
        developer.log(
          'No cached manifest found at $path.',
          name: 'ManifestService',
        );
        return null;
      }

      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;

      developer.log(
        'Cached manifest loaded from $path.',
        name: 'ManifestService',
      );

      return ManifestData.fromJson(json);
    } catch (e) {
      developer.log(
        'Failed to load cached manifest: $e',
        name: 'ManifestService',
        level: 900,
      );
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Persists [json] to the local cache file.
  Future<void> _cacheManifest(Map<String, dynamic> json) async {
    final path = await _getCachePath();
    final file = File(path);

    await file.writeAsString(jsonEncode(json), flush: true);

    developer.log(
      'Manifest cached to $path.',
      name: 'ManifestService',
    );
  }

  /// Resolves the full filesystem path for the cache file.
  Future<String> _getCachePath() async {
    final directory = await getApplicationSupportDirectory();
    return p.join(directory.path, _cacheFileName);
  }
}
