import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/dict_download_actions.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';
import 'package:lexo_player/core/services/saved_review_service.dart';
import 'package:lexo_player/core/services/tts_service.dart';

Color get _accent => AppColors.primary;

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Dictionary Panel — top-level container
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DictionaryPanel extends ConsumerStatefulWidget {
  const DictionaryPanel({super.key});

  @override
  ConsumerState<DictionaryPanel> createState() => _DictionaryPanelState();
}

class _DictionaryPanelState extends ConsumerState<DictionaryPanel> {
  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.book_rounded, color: _accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPersian ? 'واژه‌نامه‌ها' : 'Dictionaries',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Dictionary update banner (installed but stale) ──────────
          const _DictUpdateBanner(),

          _DictionaryMainBox(),
          const SizedBox(height: 24),

          // ── Auto-Update Card on Dictionary Hub ───────────────────────
          GlassContainer(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync_rounded, color: _accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPersian
                                ? 'بروزرسانی خودکار واژه‌نامه و زیرنویس'
                                : 'Auto Update Dictionaries & Subtitles',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPersian
                                ? 'دانلود و جایگزینی خودکار آخرین نسخه گیت‌هاب'
                                : 'Auto-download & replace database from GitHub',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9E9D9F),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: ref.watch(autoUpdateDictProvider),
                      activeColor: _accent,
                      onChanged: (val) {
                        AutoUpdateService.setAutoUpdateDict(ref, val);
                      },
                    ),
                  ],
                ),
                // Live auto-update status (was previously written but never shown).
                Builder(builder: (context) {
                  final status = ref.watch(dictAutoUpdateStatusProvider);
                  if (status == null || status.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9E9D9F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Saved Vocabulary Section ─────────────────────────────────
          const _SavedWordsSection(),
          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                  child: _buildSectionLabel(
                      isPersian ? 'مرکز دانلود' : 'Download Hub')),
              _CheckDictUpdatesButton(onCheck: _checkDictionaryUpdates),
            ],
          ),
          const SizedBox(height: 12),
          _DownloadHubBox(),
        ],
      ),
    );
  }

  Future<void> _checkDictionaryUpdates() async {
    final isPersian = ref.read(appLanguageProvider) == 'fa';
    ref.read(dictAutoUpdateStatusProvider.notifier).state = isPersian
        ? 'در حال بررسی بروزرسانی واژه‌نامه‌ها…'
        : 'Checking for dictionary updates…';
    ref.invalidate(manifestDataProvider);
    try {
      final manifest = await ref.read(manifestDataProvider.future);
      final stale = ref.read(dictUpdatesAvailableProvider);
      if (!mounted) return;
      ref.read(dictAutoUpdateStatusProvider.notifier).state = stale.isEmpty
          ? (isPersian
              ? 'واژه‌نامه‌ها به‌روز هستند.'
              : 'Dictionaries are up to date (v${manifest.version}).')
          : (isPersian
              ? '${stale.length} بروزرسانی واژه‌نامه آماده نصب است.'
              : '${stale.length} dictionary update(s) ready to install.');
    } catch (_) {
      if (!mounted) return;
      ref.read(dictAutoUpdateStatusProvider.notifier).state = isPersian
          ? 'بررسی ناموفق بود — اتصال اینترنت را بررسی کنید.'
          : 'Check failed — are you offline?';
    }
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF9E9D9F),
        letterSpacing: 0.8,
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Dictionary Update Banner — tells the user a used dictionary has an update
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Shows when one or more installed dictionaries are stale vs the manifest.
/// The active dictionary is highlighted first; every stale entry gets its own
/// Update button that downloads + installs the new version in place.
class _DictUpdateBanner extends ConsumerWidget {
  const _DictUpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(dictUpdatesAvailableProvider);
    if (stale.isEmpty) return const SizedBox.shrink();
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final activeId = ref.watch(selectedUnifiedDictIdProvider);
    final progressMap = ref.watch(downloadProgressProvider);

    // Active dictionary first so the one in use is impossible to miss.
    final ordered = [...stale]..sort((a, b) =>
        ((b.id == activeId) ? 1 : 0).compareTo((a.id == activeId) ? 1 : 0));

    return Column(
      children: [
        GlassContainer(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.update_rounded,
                        color: Colors.amber, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPersian
                          ? 'بروزرسانی واژه‌نامه موجود است'
                          : 'Dictionary update available',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${stale.length}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...ordered.map((entry) {
                final isActive = entry.id == activeId;
                final progress = progressMap[entry.id];
                final isDownloading = progress != null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    entry.displayName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isPersian ? 'فعال' : 'ACTIVE',
                                      style: TextStyle(
                                        color: _accent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.formattedFileSize} • ${isPersian ? 'نسخه جدید آماده نصب است' : 'new version ready to install'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9D9F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isDownloading)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 2.5,
                            color: _accent,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => downloadDictionaryWithUi(
                            ref,
                            context,
                            entry,
                            successMessage: isPersian
                                ? '"${entry.displayName}" به آخرین نسخه بروز شد!'
                                : '"${entry.displayName}" updated to the latest version!',
                          ),
                          icon: const Icon(Icons.download_rounded, size: 14),
                          label: Text(isPersian ? 'بروزرسانی' : 'Update'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            textStyle: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Small "check for updates" action next to the Download Hub header.
class _CheckDictUpdatesButton extends ConsumerWidget {
  final Future<void> Function() onCheck;
  const _CheckDictUpdatesButton({required this.onCheck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    return OutlinedButton.icon(
      onPressed: onCheck,
      icon: const Icon(Icons.refresh_rounded, size: 13),
      label: Text(isPersian ? 'بررسی بروزرسانی' : 'Check for updates'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Color(0xFF2C2C35)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Main Dictionary Box — Active dict + downloaded list + import
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DictionaryMainBox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedUnifiedDictIdProvider);
    final downloadedIds = ref.watch(downloadedDictIdsProvider);
    final manifestAsync = ref.watch(manifestDataProvider);
    final manualEntries = ref.watch(manualDictEntriesProvider);

    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    String displayName = isPersian
        ? 'هیچ واژه‌نامه‌ای انتخاب نشده است'
        : 'No dictionary selected';
    String subtitle = isPersian
        ? 'یک واژه‌نامه را از زیر انتخاب یا وارد کنید'
        : 'Select or import a dictionary below';
    if (selectedId != null && selectedId != 'none') {
      final manifest = manifestAsync.valueOrNull;
      final manifestEntry =
          manifest?.unified.where((e) => e.id == selectedId).firstOrNull;
      final manualEntry =
          manualEntries.where((e) => e.id == selectedId).firstOrNull;
      if (manifestEntry != null) {
        displayName = manifestEntry.displayName;
        subtitle = manifestEntry.description;
      } else if (manualEntry != null) {
        displayName = manualEntry.displayName;
        subtitle = manualEntry.description;
      } else {
        displayName = selectedId;
        subtitle = isPersian ? 'واژه‌نامه شخصی' : 'Custom dictionary';
      }
    }

    final entries = <_DictEntryInfo>[];
    final manifest = manifestAsync.valueOrNull;
    for (final id in downloadedIds) {
      final mEntry = manifest?.all.where((e) => e.id == id).firstOrNull;
      final manEntry = manualEntries.where((e) => e.id == id).firstOrNull;
      entries.add(_DictEntryInfo(
        id: id,
        name: mEntry?.displayName ?? manEntry?.displayName ?? id,
        description: mEntry?.description ??
            manEntry?.description ??
            (isPersian ? 'واژه‌نامه شخصی' : 'Custom dictionary'),
        type: mEntry?.type ?? manEntry?.type ?? DictionaryType.unified,
        isSelected: id == selectedId,
      ));
    }

    return GlassContainer(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _accent.withValues(alpha: 0.15),
                  border: Border.all(color: _accent.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  Icons.psychology_rounded,
                  color: _accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9D9F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF2C2C35), height: 1),
            const SizedBox(height: 12),
            ...entries.map((entry) => _DownloadedDictTile(entry: entry)),
          ],
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2C2C35), height: 1),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _importLocalDictionary(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: const Icon(Icons.upload_file_rounded,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isPersian
                            ? 'افزودن واژه‌نامه محلی (.db)'
                            : 'Import Local Dictionary (.db)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Icon(Icons.add_rounded,
                        color: Colors.white.withValues(alpha: 0.3), size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalDictionary(
      BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'Select Dictionary Database File',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        final defaultName =
            name.endsWith('.db') ? name.substring(0, name.length - 3) : name;

        if (context.mounted) {
          _showImportDialog(context, ref, path, defaultName);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showImportDialog(BuildContext context, WidgetRef ref, String filePath,
      String defaultName) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ImportDictDialog(
        filePath: filePath,
        defaultName: defaultName,
        onImportComplete: () async {
          final storage = ref.read(dictStorageManagerProvider);
          final ids = await storage.getDownloadedIds();
          ref.read(downloadedDictIdsProvider.notifier).state = ids;
        },
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Downloaded Dict Tile (inside the main box)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DownloadedDictTile extends ConsumerWidget {
  final _DictEntryInfo entry;
  const _DownloadedDictTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ref.read(selectedUnifiedDictIdProvider.notifier).state = entry.id;
            ref.read(dictStorageManagerProvider).setSelectedUnifiedId(entry.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.isSelected
                        ? _accent
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: entry.isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _confirmDelete(context, ref, entry),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.delete_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, _DictEntryInfo entry) {
    final isPersian = ref.read(appLanguageProvider) == 'fa';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16151E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Text(isPersian ? 'حذف واژه‌نامه' : 'Delete Dictionary',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            isPersian
                ? 'آیا واژه‌نامه "${entry.name}" حذف شود؟'
                : 'Remove "${entry.name}"?',
            style: const TextStyle(color: Color(0xFF9E9D9F))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isPersian ? 'انصراف' : 'Cancel',
                  style: const TextStyle(color: Color(0xFF8E8D94)))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final storage = ref.read(dictStorageManagerProvider);
              await storage.deleteDict(entry.id);
              final ids = await storage.getDownloadedIds();
              ref.read(downloadedDictIdsProvider.notifier).state = ids;
              if (entry.isSelected) {
                ref.read(selectedUnifiedDictIdProvider.notifier).state = null;
                await storage.setSelectedUnifiedId(null);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: Text(isPersian ? 'حذف' : 'Delete',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Download Hub Box (manifest dictionaries)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DownloadHubBox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifestAsync = ref.watch(manifestDataProvider);
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return GlassContainer(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(20),
      child: manifestAsync.when(
        data: (manifest) {
          if (manifest.unified.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  isPersian
                      ? 'هنوز واژه‌نامه‌ای برای دانلود آماده نیست.'
                      : 'No dictionaries available for download yet.',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF9E9D9F)),
                ),
              ),
            );
          }
          final downloadedIds = ref.watch(downloadedDictIdsProvider);
          final progressMap = ref.watch(downloadProgressProvider);
          final staleIds =
              ref.watch(dictUpdatesAvailableProvider).map((e) => e.id).toSet();

          return Column(
            children: manifest.unified.map((entry) {
              final isDownloaded = downloadedIds.contains(entry.id);
              final isStale = isDownloaded && staleIds.contains(entry.id);
              final progress = progressMap[entry.id];
              final isDownloading = progress != null;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isStale
                      ? Colors.amber.withValues(alpha: 0.06)
                      : isDownloaded
                          ? Colors.teal.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: isStale
                        ? Colors.amber.withValues(alpha: 0.3)
                        : isDownloaded
                            ? Colors.teal.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                    width: isStale ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isStale
                                ? Colors.amber.withValues(alpha: 0.15)
                                : isDownloaded
                                    ? Colors.teal.withValues(alpha: 0.15)
                                    : _accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: isStale
                                  ? Colors.amber.withValues(alpha: 0.4)
                                  : isDownloaded
                                      ? Colors.teal.withValues(alpha: 0.4)
                                      : _accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            isStale
                                ? Icons.update_rounded
                                : isDownloaded
                                    ? Icons.check_circle_rounded
                                    : Icons.cloud_download_outlined,
                            color: isStale
                                ? Colors.amber
                                : isDownloaded
                                    ? Colors.tealAccent
                                    : _accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    entry.displayName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  // Size Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.folder_zip_outlined,
                                            size: 11, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Text(
                                          entry.formattedFileSize,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isStale)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: Colors.amber.withValues(alpha: 0.5)),
                                      ),
                                      child: Text(
                                        isPersian ? 'بروزرسانی جدید' : 'UPDATE AVAILABLE',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.amber,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.description,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFFB0B0B8),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Action footer
                    if (isDownloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          backgroundColor: Colors.white10,
                          color: _accent,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isPersian ? 'در حال دریافت…' : 'Downloading…',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9E9D9F)),
                          ),
                          Text(
                            progress > 0
                                ? '${(progress * 100).toStringAsFixed(0)}%'
                                : '',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isStale)
                            ElevatedButton.icon(
                              onPressed: () => downloadDictionaryWithUi(
                                ref,
                                context,
                                entry,
                                successMessage: isPersian
                                    ? '"${entry.displayName}" به آخرین نسخه بروز شد!'
                                    : '"${entry.displayName}" updated to the latest version!',
                              ),
                              icon: const Icon(Icons.upgrade_rounded, size: 16),
                              label: Text(
                                isPersian
                                    ? 'بروزرسانی واژه‌نامه (${entry.formattedFileSize})'
                                    : 'Update Dictionary (${entry.formattedFileSize})',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                textStyle: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 3,
                              ),
                            )
                          else if (isDownloaded) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.teal.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.tealAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPersian
                                        ? 'نصب شده و به‌روز است'
                                        : 'Installed & Up to Date',
                                    style: const TextStyle(
                                      color: Colors.tealAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _downloadDictionary(ref, context, entry),
                              icon: const Icon(Icons.refresh_rounded, size: 13),
                              label: Text(isPersian ? 'نصب مجدد' : 'Reinstall'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white60,
                                side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.15)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                textStyle: const TextStyle(fontSize: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ] else
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _downloadDictionary(ref, context, entry),
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: Text(
                                isPersian
                                    ? 'دانلود واژه‌نامه (${entry.formattedFileSize})'
                                    : 'Download Dictionary (${entry.formattedFileSize})',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                textStyle: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: Text('Error: $e',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.redAccent))),
        ),
      ),
    );
  }

  Future<void> _downloadDictionary(
      WidgetRef ref, BuildContext context, DictionaryEntry entry) async {
    final downloadService = ref.read(dictDownloadServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final isPersian = ref.read(appLanguageProvider) == 'fa';

    try {
      await downloadService.downloadDictionary(
        entry,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          ref.read(downloadProgressProvider.notifier).state = {
            ...ref.read(downloadProgressProvider),
            entry.id: progress,
          };
        },
      );

      final ids = await ref.read(dictStorageManagerProvider).getDownloadedIds();
      ref.read(downloadedDictIdsProvider.notifier).state = ids;

      // Persist checksum baseline so auto-update can diff next launch.
      await AutoUpdateService.recordDictionaryChecksum(
        ref,
        entry.id,
        entry.md5Checksum,
      );

      ref.read(downloadProgressProvider.notifier).state =
          Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(entry.id);

      // Auto-select downloaded unified dictionary if none selected
      if (ref.read(selectedUnifiedDictIdProvider) == null) {
        ref.read(selectedUnifiedDictIdProvider.notifier).state = entry.id;
        await ref
            .read(dictStorageManagerProvider)
            .setSelectedUnifiedId(entry.id);
      }

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isPersian
              ? '"${entry.displayName}" با موفقیت نصب شد!'
              : '"${entry.displayName}" installed and ready to use'),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ref.read(downloadProgressProvider.notifier).state =
          Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(entry.id);

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isPersian
              ? 'خطا در دریافت واژه‌نامه: $e'
              : 'Download failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Import Dict Dialog
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ImportDictDialog extends ConsumerStatefulWidget {
  final String filePath;
  final String defaultName;
  final VoidCallback onImportComplete;

  const _ImportDictDialog({
    required this.filePath,
    required this.defaultName,
    required this.onImportComplete,
  });

  @override
  ConsumerState<_ImportDictDialog> createState() => _ImportDictDialogState();
}

class _ImportDictDialogState extends ConsumerState<_ImportDictDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _importing = true);

    try {
      final storage = ref.read(dictStorageManagerProvider);
      final id = 'local_${DateTime.now().millisecondsSinceEpoch}';

      await storage.importLocalDbFile(widget.filePath, id);

      final entry = DictionaryEntry(
        id: id,
        sourceLanguage: 'en',
        nativeLanguage: 'fa',
        displayName: _nameController.text.trim(),
        description: 'Manually imported dictionary database.',
        remoteUrl: '',
        fileSizeBytes: File(widget.filePath).lengthSync(),
        md5Checksum: '',
        type: DictionaryType.unified,
      );

      await storage.addManualDictEntry(entry);
      ref.read(selectedUnifiedDictIdProvider.notifier).state = id;
      await storage.setSelectedUnifiedId(id);
      widget.onImportComplete();

      if (mounted) {
        final isPersian = ref.read(appLanguageProvider) == 'fa';
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPersian
                ? 'واژه‌نامه با موفقیت اضافه شد!'
                : 'Dictionary imported successfully!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isPersian = ref.read(appLanguageProvider) == 'fa';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(isPersian ? 'خطا در افزودن: $e' : 'Import failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return AlertDialog(
      backgroundColor: const Color(0xFF16151E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      title: Text(
        isPersian ? 'افزودن واژه‌نامه' : 'Import Dictionary',
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: isPersian ? 'نام واژه‌نامه' : 'Display Name',
                labelStyle: const TextStyle(color: Color(0xFF9E9D9F)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _accent),
                ),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? (isPersian ? 'الزامی است' : 'Required')
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: Text(isPersian ? 'انصراف' : 'Cancel',
              style: const TextStyle(color: Color(0xFF8E8D94))),
        ),
        ElevatedButton(
          onPressed: _importing ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(isPersian ? 'افزودن' : 'Import',
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Dict Entry Info — lightweight data class
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _DictEntryInfo {
  final String id;
  final String name;
  final String description;
  final DictionaryType type;
  final bool isSelected;

  const _DictEntryInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.isSelected,
  });
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Saved Words Section
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SavedWordsSection extends ConsumerWidget {
  const _SavedWordsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final savedWords = ref.watch(savedWordsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isPersian ? 'واژه‌های ذخیره شده' : 'Saved Vocabulary',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${savedWords.length}',
                style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (savedWords.isEmpty)
          GlassContainer(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.bookmark_border_rounded, color: Colors.white38, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    isPersian
                        ? 'هیچ واژه‌ای ذخیره نشده است. هنگام مشاهده زیرنویس، روی کلمه کلیک کرده و "ذخیره کلمه" را بزنید.'
                        : 'No saved words yet. Click on any word in subtitles and choose "Save Word" to add vocabulary here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          GlassContainer(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: savedWords.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF282732), height: 16),
              itemBuilder: (context, index) {
                final w = savedWords[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                w.word,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (w.lemma != null && w.lemma!.isNotEmpty)
                                Text(
                                  w.lemma!,
                                  style: const TextStyle(
                                    color: Color(0xFF8A8A93),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              if (w.pos != null && w.pos!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    w.pos!,
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (w.translation != null && w.translation!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              w.translation!,
                              style: const TextStyle(
                                color: Color(0xFFD2D1DD),
                                fontSize: 13,
                                fontFamily: 'Parastoo',
                              ),
                            ),
                          ],
                          if (w.contextSentence != null && w.contextSentence!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '"${w.contextSentence!}"',
                              style: const TextStyle(
                                color: Color(0xFF757480),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isPersian ? 'تلفظ کلمه' : 'Pronounce word',
                      icon: Icon(Icons.volume_up_rounded, color: _accent, size: 20),
                      onPressed: () {
                        ref.read(ttsServiceProvider).speak(w.word);
                      },
                    ),
                    IconButton(
                      tooltip: isPersian ? 'حذف کلمه' : 'Delete word',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                      onPressed: () {
                        if (w.id != null) {
                          ref.read(savedWordsProvider.notifier).removeWord(w.id!);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

