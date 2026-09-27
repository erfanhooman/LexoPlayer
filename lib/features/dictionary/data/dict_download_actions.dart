import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';

/// Downloads + installs [entry] with progress + snackbar feedback.
///
/// Shared by the update banner, the Download Hub UPDATE buttons, and manual
/// installs so every path refreshes download tracking, the checksum baseline
/// (update detection), and the engine when the installed dictionary is the
/// active one. Returns true on success.
Future<bool> downloadDictionaryWithUi(
  WidgetRef ref,
  BuildContext context,
  DictionaryEntry entry, {
  String? successMessage,
}) async {
  final downloadService = ref.read(dictDownloadServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  final isPersian = ref.read(appLanguageProvider) == 'fa';

  void clearProgress() {
    try {
      ref.read(downloadProgressProvider.notifier).state =
          Map<String, double>.from(ref.read(downloadProgressProvider))
            ..remove(entry.id);
    } catch (_) {}
  }

  try {
    await downloadService.downloadDictionary(
      entry,
      onProgress: (received, total) {
        final progress = total > 0 ? received / total : 0.0;
        try {
          ref.read(downloadProgressProvider.notifier).state = {
            ...ref.read(downloadProgressProvider),
            entry.id: progress,
          };
        } catch (_) {}
      },
    );

    final ids = await ref.read(dictStorageManagerProvider).getDownloadedIds();
    try {
      ref.read(downloadedDictIdsProvider.notifier).state = ids;
    } catch (_) {}
    await AutoUpdateService.recordDictionaryChecksum(
        ref, entry.id, entry.md5Checksum);
    clearProgress();

    // Auto-select a freshly installed unified dictionary when none is active.
    try {
      if (ref.read(selectedUnifiedDictIdProvider) == null &&
          entry.type == DictionaryType.unified) {
        ref.read(selectedUnifiedDictIdProvider.notifier).state = entry.id;
        await ref
            .read(dictStorageManagerProvider)
            .setSelectedUnifiedId(entry.id);
      }
      // Reload the engine when the installed dictionary is the active one.
      if (ref.read(selectedUnifiedDictIdProvider) == entry.id) {
        ref.invalidate(engineInitProvider);
      }
    } catch (_) {}

    if (!context.mounted) return true;
    messenger.showSnackBar(
      SnackBar(
        content: Text(successMessage ??
            (isPersian
                ? '"${entry.displayName}" با موفقیت نصب شد!'
                : '"${entry.displayName}" installed and ready to use')),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  } catch (e) {
    clearProgress();
    if (!context.mounted) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            isPersian ? 'خطا در دریافت واژه‌نامه: $e' : 'Download failed: $e'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
}
