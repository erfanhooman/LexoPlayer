import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/features/dictionary/data/dict_selection_providers.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';
import 'package:lexo_player/features/dictionary/data/unified_dictionary_repository.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';

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

          _DictionaryMainBox(),
          const SizedBox(height: 24),

          // ── Auto-Update Card on Dictionary Hub ───────────────────────
          GlassContainer(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.sync_rounded, color: _accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPersian ? 'بروزرسانی خودکار واژه‌نامه و زیرنویس' : 'Auto Update Dictionaries & Subtitles',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPersian ? 'دانلود و جایگزینی خودکار آخرین نسخه گیت‌هاب' : 'Auto-download & replace database from GitHub',
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
          ),
          const SizedBox(height: 28),

          _buildSectionLabel(isPersian ? 'مرکز دانلود' : 'Download Hub'),
          const SizedBox(height: 12),
          _DownloadHubBox(),
        ],
      ),
    );
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

    String displayName = isPersian ? 'هیچ واژه‌نامه‌ای انتخاب نشده است' : 'No dictionary selected';
    String subtitle = isPersian ? 'یک واژه‌نامه را از زیر انتخاب یا وارد کنید' : 'Select or import a dictionary below';
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
        description:
            mEntry?.description ?? manEntry?.description ?? (isPersian ? 'واژه‌نامه شخصی' : 'Custom dictionary'),
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
                        isPersian ? 'افزودن واژه‌نامه محلی (.db)' : 'Import Local Dictionary (.db)',
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

  void _showImportDialog(
      BuildContext context, WidgetRef ref, String filePath, String defaultName) {
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

  void _confirmDelete(BuildContext context, WidgetRef ref, _DictEntryInfo entry) {
    final isPersian = ref.read(appLanguageProvider) == 'fa';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16151E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Text(
            isPersian ? 'حذف واژه‌نامه' : 'Delete Dictionary',
            style:
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            isPersian ? 'آیا واژه‌نامه "${entry.name}" حذف شود؟' : 'Remove "${entry.name}"?',
            style: const TextStyle(color: Color(0xFF9E9D9F))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                  isPersian ? 'انصراف' : 'Cancel',
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
            child:
                Text(isPersian ? 'حذف' : 'Delete', style: const TextStyle(color: Colors.white)),
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
                  isPersian ? 'هنوز واژه‌نامه‌ای برای دانلود آماده نیست.' : 'No dictionaries available for download yet.',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF9E9D9F)),
                ),
              ),
            );
          }
          final downloadedIds = ref.watch(downloadedDictIdsProvider);
          final progressMap = ref.watch(downloadProgressProvider);

          return Column(
            children: manifest.unified.map((entry) {
              final isDownloaded = downloadedIds.contains(entry.id);
              final progress = progressMap[entry.id];
              final isDownloading = progress != null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: _accent.withValues(alpha: 0.12),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        isDownloaded
                            ? Icons.check_circle_rounded
                            : Icons.cloud_download_outlined,
                        color: isDownloaded ? Colors.tealAccent : _accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.displayName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text('${entry.description} • ${entry.formattedFileSize}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9E9D9F)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isDownloaded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          isPersian ? 'نصب شده' : 'Installed',
                          style: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    else if (isDownloading)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 2.5,
                          color: _accent,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => _downloadDictionary(ref, context, entry),
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: Text(isPersian ? 'دانلود' : 'Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: CircularProgressIndicator(
                  color: _accent, strokeWidth: 2)),
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

  Future<void> _downloadDictionary(WidgetRef ref, BuildContext context, DictionaryEntry entry) async {
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

      ref.read(downloadProgressProvider.notifier).state = Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(entry.id);

      // Auto-select downloaded unified dictionary if none selected
      if (ref.read(selectedUnifiedDictIdProvider) == null) {
        ref.read(selectedUnifiedDictIdProvider.notifier).state = entry.id;
        await ref.read(dictStorageManagerProvider).setSelectedUnifiedId(entry.id);
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
      ref.read(downloadProgressProvider.notifier).state = Map<String, double>.from(
        ref.read(downloadProgressProvider),
      )..remove(entry.id);

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isPersian ? 'خطا در دریافت واژه‌نامه: $e' : 'Download failed: $e'),
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
            content: Text(isPersian ? 'واژه‌نامه با موفقیت اضافه شد!' : 'Dictionary imported successfully!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isPersian = ref.read(appLanguageProvider) == 'fa';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPersian ? 'خطا در افزودن: $e' : 'Import failed: $e'),
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
              validator: (v) =>
                  v == null || v.trim().isEmpty ? (isPersian ? 'الزامی است' : 'Required') : null,
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
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
