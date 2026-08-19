import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/dict_storage_manager.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

const String kAutoUpdateAppKey = 'auto_update_app';
const String kAutoUpdateDictKey = 'auto_update_dict';

/// State provider for Auto Update App toggle (default: true)
final autoUpdateAppProvider = StateProvider<bool>((ref) => true);

/// State provider for Auto Update Dictionaries toggle (default: true)
final autoUpdateDictProvider = StateProvider<bool>((ref) => true);

/// State provider for app update status message
final appUpdateStatusProvider = StateProvider<String?>((ref) => null);

/// State provider for dictionary auto-update status message
final dictAutoUpdateStatusProvider = StateProvider<String?>((ref) => null);

class AutoUpdateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Initializes auto-update settings from SharedPreferences
  static Future<void> init(WidgetRef ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoApp = prefs.getBool(kAutoUpdateAppKey) ?? true;
      final autoDict = prefs.getBool(kAutoUpdateDictKey) ?? true;

      ref.read(autoUpdateAppProvider.notifier).state = autoApp;
      ref.read(autoUpdateDictProvider.notifier).state = autoDict;

      if (autoDict) {
        checkAndAutoUpdateDictionaries(ref);
      }
      if (autoApp) {
        checkAndAutoUpdateApp(ref);
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
      checkAndAutoUpdateApp(ref);
    }
  }

  /// Sets auto-update dictionaries preference
  static Future<void> setAutoUpdateDict(WidgetRef ref, bool value) async {
    ref.read(autoUpdateDictProvider.notifier).state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoUpdateDictKey, value);
    if (value) {
      checkAndAutoUpdateDictionaries(ref);
    }
  }

  /// Checks GitHub manifest for updated dictionary files and auto-replaces them
  static Future<void> checkAndAutoUpdateDictionaries(dynamic ref) async {
    try {
      final manifestService = ref.read(manifestServiceProvider);
      final storage = ref.read(dictStorageManagerProvider);
      final downloadService = ref.read(dictDownloadServiceProvider);

      final manifest = await manifestService.fetchManifest();
      final downloadedIds = await storage.getDownloadedIds();
      final prefs = await SharedPreferences.getInstance();

      for (final entry in manifest.all) {
        if (!downloadedIds.contains(entry.id)) continue;

        final savedMd5Key = 'dict_md5_${entry.id}';
        final savedMd5 = prefs.getString(savedMd5Key);

        // If saved MD5 is different or missing, or entry checksum updated
        if (savedMd5 == null || savedMd5 != entry.md5Checksum) {
          developer.log(
            'New dictionary version detected for "${entry.displayName}". Auto-updating from GitHub...',
            name: 'AutoUpdateService',
          );

          ref.read(dictAutoUpdateStatusProvider.notifier).state =
              'Auto-updating ${entry.displayName}...';

          await downloadService.downloadDictionary(entry);
          await prefs.setString(savedMd5Key, entry.md5Checksum);

          // If this dictionary is currently active, invalidate engineInitProvider to trigger reload
          final activeUnifiedId = ref.read(selectedUnifiedDictIdProvider);
          if (activeUnifiedId == entry.id) {
            ref.invalidate(engineInitProvider);
          }

          ref.read(dictAutoUpdateStatusProvider.notifier).state =
              'Dictionary "${entry.displayName}" updated to latest version!';
        }
      }
    } catch (e) {
      developer.log('Error during dictionary auto-update: $e',
          name: 'AutoUpdateService');
    }
  }

  /// Checks GitHub Releases API for app updates
  static Future<void> checkAndAutoUpdateApp(dynamic ref) async {
    try {
      const releaseUrl =
          'https://api.github.com/repos/erfanhooman/LexoPlayer/releases/latest';
      final response = await _dio.get<Map<String, dynamic>>(releaseUrl);

      if (response.statusCode == 200 && response.data != null) {
        final tagName = response.data!['tag_name'] as String? ?? '';
        final htmlUrl = response.data!['html_url'] as String? ?? '';

        if (tagName.isNotEmpty) {
          ref.read(appUpdateStatusProvider.notifier).state =
              'Latest GitHub Release: $tagName ($htmlUrl)';
        }
      }
    } catch (e) {
      developer.log('App update check skipped: $e', name: 'AutoUpdateService');
    }
  }
}
