import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/core/services/dict_storage_manager.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Source language tracking
// ─────────────────────────────────────────────────────────────────────────────

/// The ISO 639-1 language code of the active subtitle track.
///
/// This is set when a subtitle file is loaded (e.g. detected from the file
/// name or manually specified by the user). It controls which dictionaries
/// appear in the selection dropdowns.
///
/// Defaults to `"en"` (English).
final activeSourceLanguageProvider = StateProvider<String>((ref) => 'en');

// ─────────────────────────────────────────────────────────────────────────────
// Active dictionary selections (persisted to shared_preferences)
// ─────────────────────────────────────────────────────────────────────────────

/// The ID of the currently selected monolingual (definition) dictionary.
///
/// `null` means no monolingual dictionary is active.
final selectedMonolingualIdProvider = StateProvider<String?>((ref) => null);

/// The ID of the currently selected bilingual (translation) dictionary.
///
/// `null` means no bilingual dictionary is active.
final selectedBilingualIdProvider = StateProvider<String?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Filtered available dictionaries
// ─────────────────────────────────────────────────────────────────────────────

/// Downloaded monolingual dictionaries whose [sourceLanguage] matches the
/// active subtitle language.
///
/// This powers the "Definition Slot" dropdown in the dictionary settings UI.
final availableMonolingualProvider = Provider<List<DictionaryEntry>>((ref) {
  final manifestAsync = ref.watch(manifestDataProvider);
  final downloadedIds = ref.watch(downloadedDictIdsProvider);
  final activeLang = ref.watch(activeSourceLanguageProvider);
  final manualEntries = ref.watch(manualDictEntriesProvider);

  final List<DictionaryEntry> list = [];

  // Add matching manually uploaded dictionaries
  for (final e in manualEntries) {
    if (e.type == DictionaryType.monolingual &&
        e.sourceLanguage == activeLang &&
        downloadedIds.contains(e.id)) {
      list.add(e);
    }
  }

  // Add matching downloaded manifest dictionaries
  final manifestList = manifestAsync.maybeWhen(
    data: (manifest) {
      return manifest.monolingual
          .where((e) =>
              downloadedIds.contains(e.id) && e.sourceLanguage == activeLang)
          .toList();
    },
    orElse: () => const <DictionaryEntry>[],
  );
  list.addAll(manifestList);

  return list;
});

/// Downloaded bilingual dictionaries whose [sourceLanguage] matches the
/// active subtitle language.
///
/// This powers the "Translation Slot" dropdown in the dictionary settings UI.
final availableBilingualProvider = Provider<List<DictionaryEntry>>((ref) {
  final manifestAsync = ref.watch(manifestDataProvider);
  final downloadedIds = ref.watch(downloadedDictIdsProvider);
  final activeLang = ref.watch(activeSourceLanguageProvider);
  final manualEntries = ref.watch(manualDictEntriesProvider);

  final List<DictionaryEntry> list = [];

  // Add matching manually uploaded dictionaries
  for (final e in manualEntries) {
    if (e.type == DictionaryType.bilingual &&
        e.sourceLanguage == activeLang &&
        downloadedIds.contains(e.id)) {
      list.add(e);
    }
  }

  // Add matching downloaded manifest dictionaries
  final manifestList = manifestAsync.maybeWhen(
    data: (manifest) {
      return manifest.bilingual
          .where((e) =>
              downloadedIds.contains(e.id) && e.sourceLanguage == activeLang)
          .toList();
    },
    orElse: () => const <DictionaryEntry>[],
  );
  list.addAll(manifestList);

  return list;
});

// ─────────────────────────────────────────────────────────────────────────────
// Hydration from persistent storage
// ─────────────────────────────────────────────────────────────────────────────

/// Loads the persisted dictionary selections from [DictStorageManager]
/// into the corresponding state providers.
///
/// Call this during app startup after [hydrateDownloadedIds].
Future<void> hydrateSelections(WidgetRef ref) async {
  final storage = ref.read(dictStorageManagerProvider);

  final monoId = await storage.getSelectedMonolingualId();
  final biId = await storage.getSelectedBilingualId();

  if (monoId != null) {
    ref.read(selectedMonolingualIdProvider.notifier).state = monoId;
  }
  if (biId != null) {
    ref.read(selectedBilingualIdProvider.notifier).state = biId;
  }

  developer.log(
    'DictSelectionProviders: Hydrated selections — '
    'mono=$monoId, bi=$biId',
    name: 'DictSelection',
  );
}

/// Saves the currently selected dictionary IDs to persistent storage.
Future<void> saveSelections(WidgetRef ref) async {
  final storage = ref.read(dictStorageManagerProvider);
  final monoId = ref.read(selectedMonolingualIdProvider);
  final biId = ref.read(selectedBilingualIdProvider);
  
  await storage.setSelectedMonolingualId(monoId == 'none' ? null : monoId);
  await storage.setSelectedBilingualId(biId == 'none' ? null : biId);
}
