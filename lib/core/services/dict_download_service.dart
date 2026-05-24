/// Service responsible for downloading, verifying, and extracting dictionary
/// archives.
///
/// [DictDownloadService] orchestrates the complete acquisition pipeline for a
/// single dictionary entry:
///
/// 1. **Download** the `.zip` archive from the remote URL.
/// 2. **Verify** the file's MD5 checksum against the manifest value.
/// 3. **Extract** the first `.db` file from the archive.
/// 4. **Persist** the extracted database to the dictionaries directory.
/// 5. **Register** the dictionary as downloaded via [DictStorageManager].
///
/// Usage:
/// ```dart
/// final service = DictDownloadService(storageManager);
/// await service.downloadDictionary(
///   entry,
///   onProgress: (received, total) => print('$received / $total'),
/// );
/// ```
library;

import 'dart:io';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/dict_storage_manager.dart';

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Thrown when the MD5 checksum of a downloaded file does not match the
/// expected value from the manifest.
///
/// This typically indicates a corrupted or tampered download and the caller
/// should prompt the user to retry.
class ChecksumMismatchException implements Exception {
  /// The checksum declared in the manifest.
  final String expected;

  /// The checksum computed from the downloaded bytes.
  final String actual;

  const ChecksumMismatchException({
    required this.expected,
    required this.actual,
  });

  @override
  String toString() => 'ChecksumMismatchException: expected MD5 "$expected", '
      'but computed "$actual".';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Downloads, verifies, and extracts dictionary archives.
///
/// Each instance holds its own [Dio] client and a reference to the
/// [DictStorageManager] used for tracking downloads.
class DictDownloadService {
  // ---------------------------------------------------------------------------
  // Dependencies
  // ---------------------------------------------------------------------------

  /// HTTP client configured for potentially large file downloads.
  ///
  /// Timeouts are intentionally generous (or disabled) because dictionary
  /// archives can be several hundred megabytes.
  final Dio _dio;

  /// Storage manager used to resolve paths and track download state.
  final DictStorageManager _storageManager;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a [DictDownloadService].
  ///
  /// [storageManager] is required for path resolution and download tracking.
  /// An optional [dio] instance can be injected for testing; by default a
  /// client with generous timeouts is created.
  DictDownloadService(
    this._storageManager, {
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 10),
              ),
            );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Deletes an installed dictionary and updates local state.
  Future<void> deleteDictionary(String dictId) async {
    await _storageManager.deleteDict(dictId);
  }

  /// Downloads and installs the dictionary described by [entry].
  ///
  /// The full pipeline:
  /// 1. Download the `.zip` to a temporary path.
  /// 2. Read the file and verify its MD5 against [DictionaryEntry.md5Checksum].
  /// 3. Decode the archive and locate the first `.db` file.
  /// 4. Write the `.db` to its final location.
  /// 5. Clean up the temporary `.zip`.
  /// 6. Mark the dictionary as downloaded.
  ///
  /// [onProgress] is called periodically with `(receivedBytes, totalBytes)`.
  /// If the server does not send a `Content-Length` header, `totalBytes` will
  /// be `-1`.
  ///
  /// Throws:
  /// * [ChecksumMismatchException] if the MD5 does not match.
  /// * [Exception] if the archive does not contain a `.db` file.
  /// * [DioException] on unrecoverable network errors.
  Future<void> downloadDictionary(
    DictionaryEntry entry, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dictsDir = await _storageManager.getDictsDirectory();
    final tempZipPath = p.join(dictsDir, '${entry.id}.zip');
    final finalDbPath = p.join(dictsDir, '${entry.id}.db');

    try {
      // ------------------------------------------------------------------
      // 1. Download the archive
      // ------------------------------------------------------------------
      developer.log(
        'Downloading "${entry.displayName}" from ${entry.remoteUrl} …',
        name: 'DictDownloadService',
      );

      await _dio.download(
        entry.remoteUrl,
        tempZipPath,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total);
        },
      );

      developer.log(
        'Download complete. Verifying checksum …',
        name: 'DictDownloadService',
      );

      // ------------------------------------------------------------------
      // 2. Verify MD5 checksum (skip if placeholder or empty)
      // ------------------------------------------------------------------
      final tempFile = File(tempZipPath);
      final bytes = await tempFile.readAsBytes();
      final computedMd5 = md5.convert(bytes).toString();

      final isPlaceholder =
          entry.md5Checksum.isEmpty || entry.md5Checksum.contains('REPLACE');

      if (!isPlaceholder && computedMd5 != entry.md5Checksum) {
        // Clean up the corrupt download before throwing.
        await _safeDelete(tempFile);

        developer.log(
          'Checksum mismatch for "${entry.id}": '
          'expected ${entry.md5Checksum}, got $computedMd5.',
          name: 'DictDownloadService',
          level: 1000,
        );

        throw ChecksumMismatchException(
          expected: entry.md5Checksum,
          actual: computedMd5,
        );
      }

      if (isPlaceholder) {
        developer.log(
          'Skipping checksum verification for "${entry.id}" '
          '(placeholder MD5 in manifest).',
          name: 'DictDownloadService',
        );
      }

      developer.log(
        'Checksum verified. Extracting archive …',
        name: 'DictDownloadService',
      );

      // ------------------------------------------------------------------
      // 3. Decode ZIP and locate the .db file
      // ------------------------------------------------------------------
      final archive = ZipDecoder().decodeBytes(bytes);

      final dbFile = archive.files.cast<ArchiveFile?>().firstWhere(
            (f) => f != null && f.name.endsWith('.db') && f.isFile,
            orElse: () => null,
          );

      if (dbFile == null) {
        await _safeDelete(tempFile);
        throw Exception(
          'Archive for "${entry.id}" does not contain a .db file.',
        );
      }

      developer.log(
        'Found database file "${dbFile.name}" '
        '(${dbFile.size} bytes) in archive.',
        name: 'DictDownloadService',
      );

      // ------------------------------------------------------------------
      // 4. Write the extracted .db to its final path
      // ------------------------------------------------------------------
      final outputFile = File(finalDbPath);
      await outputFile.writeAsBytes(dbFile.content as List<int>, flush: true);

      developer.log(
        'Extracted database to $finalDbPath.',
        name: 'DictDownloadService',
      );

      // ------------------------------------------------------------------
      // 5. Clean up the temporary ZIP
      // ------------------------------------------------------------------
      await _safeDelete(tempFile);

      // ------------------------------------------------------------------
      // 6. Register the download
      // ------------------------------------------------------------------
      await _storageManager.markDownloaded(entry.id);

      developer.log(
        'Dictionary "${entry.displayName}" installed successfully.',
        name: 'DictDownloadService',
      );
    } catch (e) {
      // Ensure the temp file is cleaned up on *any* failure.
      await _safeDelete(File(tempZipPath));

      developer.log(
        'Failed to download/install "${entry.id}": $e',
        name: 'DictDownloadService',
        level: 1000,
      );

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Deletes [file] if it exists, swallowing any errors.
  Future<void> _safeDelete(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      developer.log(
        'Warning: could not delete temp file ${file.path}: $e',
        name: 'DictDownloadService',
        level: 900,
      );
    }
  }
}
