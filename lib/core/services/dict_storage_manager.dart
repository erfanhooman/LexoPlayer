/// Manages dictionary file paths, download tracking, and active-dictionary
/// selection via shared_preferences and the local filesystem.
///
/// [DictStorageManager] is the single source of truth for:
///
/// * **Where** dictionary `.db` files are stored on disk.
/// * **Which** dictionaries have been downloaded (persisted in
///   `SharedPreferences` and cross-checked against the filesystem).
/// * **Which** monolingual / bilingual dictionary is currently selected by
///   the user.
///
/// Usage:
/// ```dart
/// final manager = DictStorageManager();
/// final isReady = await manager.isDictDownloaded('eng_oxford');
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lexo_player/core/models/manifest_models.dart';

/// Tracks downloaded dictionaries and user selections.
///
/// All methods are asynchronous because they interact with
/// [SharedPreferences] and / or the filesystem.
class DictStorageManager {
  // ---------------------------------------------------------------------------
  // SharedPreferences keys
  // ---------------------------------------------------------------------------

  /// Key for the `List<String>` of downloaded dictionary IDs.
  static const String _prefsKey = 'downloaded_dict_ids';

  /// Key for the currently selected monolingual dictionary ID.
  static const String _selectedMonoKey = 'selected_monolingual_id';

  /// Key for the currently selected bilingual dictionary ID.
  static const String _selectedBiKey = 'selected_bilingual_id';

  // ---------------------------------------------------------------------------
  // Filesystem constants
  // ---------------------------------------------------------------------------

  /// Subdirectory under the app documents folder where `.db` files are stored.
  static const String _dictSubdir = 'dicts';

  // ---------------------------------------------------------------------------
  // Directory & path helpers
  // ---------------------------------------------------------------------------

  /// Returns the absolute path to the dictionaries directory, creating it if
  /// necessary.
  ///
  /// Path: `<appDocumentsDir>/dicts/`
  Future<String> getDictsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dictsDir = Directory(p.join(appDir.path, _dictSubdir));

    if (!dictsDir.existsSync()) {
      await dictsDir.create(recursive: true);
      developer.log(
        'Created dictionaries directory at ${dictsDir.path}.',
        name: 'DictStorageManager',
      );
    }

    return dictsDir.path;
  }

  /// Returns the expected path for a dictionary file with the given [dictId].
  ///
  /// Path: `<appDocumentsDir>/dicts/<dictId>.db`
  Future<String> getDictPath(String dictId) async {
    final dictsPath = await getDictsDirectory();
    return p.join(dictsPath, '$dictId.db');
  }

  // ---------------------------------------------------------------------------
  // Download tracking
  // ---------------------------------------------------------------------------

  /// Returns `true` when [dictId] is registered in shared_preferences **and**
  /// the corresponding `.db` file exists on disk.
  ///
  /// This double-check guards against stale preference entries caused by
  /// manual file deletion or incomplete cleanup.
  Future<bool> isDictDownloaded(String dictId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_prefsKey) ?? <String>[];

      if (!ids.contains(dictId)) {
        return false;
      }

      final filePath = await getDictPath(dictId);
      final exists = File(filePath).existsSync();

      if (!exists) {
        developer.log(
          'Dictionary "$dictId" is in prefs but missing from disk. '
          'Removing stale entry.',
          name: 'DictStorageManager',
          level: 900,
        );
        await markRemoved(dictId);
      }

      return exists;
    } catch (e) {
      developer.log(
        'Error checking download status for "$dictId": $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      return false;
    }
  }

  /// Registers [dictId] as downloaded in shared_preferences.
  ///
  /// Duplicate IDs are silently ignored.
  Future<void> markDownloaded(String dictId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_prefsKey) ?? <String>[];

      if (!ids.contains(dictId)) {
        ids.add(dictId);
        await prefs.setStringList(_prefsKey, ids);
        developer.log(
          'Marked "$dictId" as downloaded.',
          name: 'DictStorageManager',
        );
      }
    } catch (e) {
      developer.log(
        'Failed to mark "$dictId" as downloaded: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Removes [dictId] from the downloaded-IDs list in shared_preferences.
  Future<void> markRemoved(String dictId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_prefsKey) ?? <String>[];

      if (ids.remove(dictId)) {
        await prefs.setStringList(_prefsKey, ids);
        developer.log(
          'Removed "$dictId" from downloaded list.',
          name: 'DictStorageManager',
        );
      }
    } catch (e) {
      developer.log(
        'Failed to remove "$dictId" from prefs: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Returns the full list of dictionary IDs currently registered as
  /// downloaded.
  ///
  /// **Note:** This reflects the shared_preferences state and may include
  /// stale entries if files were removed externally.  Use [isDictDownloaded]
  /// for a verified check.
  Future<List<String>> getDownloadedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsKey) ?? <String>[];
    } catch (e) {
      developer.log(
        'Failed to read downloaded IDs: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      return <String>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Dictionary deletion
  // ---------------------------------------------------------------------------

  /// Deletes the `.db` file for [dictId] from disk and removes the
  /// corresponding shared_preferences entry.
  ///
  /// If the file does not exist the preference entry is still cleaned up.
  Future<void> deleteDict(String dictId) async {
    try {
      final filePath = await getDictPath(dictId);
      final file = File(filePath);

      if (file.existsSync()) {
        await file.delete();
        developer.log(
          'Deleted dictionary file at $filePath.',
          name: 'DictStorageManager',
        );
      } else {
        developer.log(
          'Dictionary file for "$dictId" not found on disk – '
          'cleaning prefs only.',
          name: 'DictStorageManager',
          level: 900,
        );
      }

      // Also clean up manual entries metadata if it exists there
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_manualDictsKey) ?? [];
      final originalLength = list.length;
      list.removeWhere((jsonStr) {
        try {
          final map = jsonDecode(jsonStr);
          return map['id'] == dictId;
        } catch (_) {
          return false;
        }
      });
      if (list.length != originalLength) {
        await prefs.setStringList(_manualDictsKey, list);
        developer.log(
          'Removed manual dictionary metadata for $dictId.',
          name: 'DictStorageManager',
        );
      }

      await markRemoved(dictId);
    } catch (e) {
      developer.log(
        'Error deleting dictionary "$dictId": $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Active selection persistence
  // ---------------------------------------------------------------------------

  /// Returns the ID of the currently selected monolingual dictionary, or
  /// `null` if none is selected.
  Future<String?> getSelectedMonolingualId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedMonoKey);
    } catch (e) {
      developer.log(
        'Failed to read selected monolingual ID: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      return null;
    }
  }

  /// Persists [id] as the currently selected monolingual dictionary.
  ///
  /// Pass `null` to clear the selection.
  Future<void> setSelectedMonolingualId(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (id == null) {
        await prefs.remove(_selectedMonoKey);
      } else {
        await prefs.setString(_selectedMonoKey, id);
      }

      developer.log(
        'Selected monolingual dictionary set to ${id ?? '(none)'}.',
        name: 'DictStorageManager',
      );
    } catch (e) {
      developer.log(
        'Failed to set selected monolingual ID: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Returns the ID of the currently selected bilingual dictionary, or
  /// `null` if none is selected.
  Future<String?> getSelectedBilingualId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedBiKey);
    } catch (e) {
      developer.log(
        'Failed to read selected bilingual ID: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      return null;
    }
  }

  /// Persists [id] as the currently selected bilingual dictionary.
  ///
  /// Pass `null` to clear the selection.
  Future<void> setSelectedBilingualId(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (id == null) {
        await prefs.remove(_selectedBiKey);
      } else {
        await prefs.setString(_selectedBiKey, id);
      }

      developer.log(
        'Selected bilingual dictionary set to ${id ?? '(none)'}.',
        name: 'DictStorageManager',
      );
    } catch (e) {
      developer.log(
        'Failed to set selected bilingual ID: $e',
        name: 'DictStorageManager',
        level: 1000,
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Manual Dictionary Import & Tracking
  // ---------------------------------------------------------------------------

  /// Key for storing manual dictionary entry JSON strings.
  static const String _manualDictsKey = 'manual_dict_entries';

  /// Copies a local database file to the dictionaries directory.
  Future<String> importLocalDbFile(
      String sourceFilePath, String targetDictId) async {
    final dictsDir = await getDictsDirectory();
    final targetPath = p.join(dictsDir, '$targetDictId.db');
    final sourceFile = File(sourceFilePath);
    await sourceFile.copy(targetPath);
    return targetPath;
  }

  /// Retrieves the metadata list of manually imported dictionaries.
  Future<List<DictionaryEntry>> getManualDictEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_manualDictsKey) ?? [];
      final List<DictionaryEntry> entries = [];
      final List<String> updatedList = [];

      final dictsDir = await getDictsDirectory();

      for (final jsonStr in list) {
        try {
          final map = Map<String, dynamic>.from(
            jsonDecode(jsonStr) as Map,
          );
          final id = map['id'] as String;
          final typeStr = map['type'] as String;
          final type = typeStr == 'monolingual'
              ? DictionaryType.monolingual
              : DictionaryType.bilingual;

          final file = File(p.join(dictsDir, '$id.db'));
          if (file.existsSync()) {
            entries.add(DictionaryEntry(
              id: id,
              sourceLanguage: map['source_language'] as String,
              nativeLanguage: map['native_language'] as String?,
              displayName: map['display_name'] as String,
              description:
                  map['description'] as String? ?? 'Manually added dictionary.',
              remoteUrl: '',
              fileSizeBytes: file.lengthSync(),
              md5Checksum: '',
              type: type,
            ));
            updatedList.add(jsonStr);
          }
        } catch (e) {
          developer.log('Error parsing manual dictionary: $e');
        }
      }

      if (updatedList.length != list.length) {
        await prefs.setStringList(_manualDictsKey, updatedList);
      }

      return entries;
    } catch (e) {
      developer.log('Error getting manual dictionaries: $e');
      return [];
    }
  }

  /// Adds a manually imported dictionary's metadata to storage.
  Future<void> addManualDictEntry(DictionaryEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_manualDictsKey) ?? [];

      // Remove any existing manual entry with same ID.
      list.removeWhere((jsonStr) {
        try {
          final map = jsonDecode(jsonStr);
          return map['id'] == entry.id;
        } catch (_) {
          return false;
        }
      });

      final entryMap = entry.toJson();
      entryMap['type'] = entry.type == DictionaryType.monolingual
          ? 'monolingual'
          : 'bilingual';

      list.add(jsonEncode(entryMap));
      await prefs.setStringList(_manualDictsKey, list);
      await markDownloaded(entry.id);
    } catch (e) {
      developer.log('Error adding manual dictionary: $e');
    }
  }
}
