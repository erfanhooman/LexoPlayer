import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lexo_player/core/models/manifest_models.dart';
import 'package:lexo_player/features/dictionary/data/manifest_providers.dart';

DictionaryEntry _entry({required String id, required String md5}) =>
    DictionaryEntry(
      id: id,
      sourceLanguage: 'en',
      nativeLanguage: 'fa',
      displayName: 'Dict $id',
      description: 'test',
      remoteUrl: 'https://example.com/$id.zip',
      fileSizeBytes: 1000,
      md5Checksum: md5,
      type: DictionaryType.unified,
    );

ManifestData _manifest(List<DictionaryEntry> unified) => ManifestData(
      lastUpdated: DateTime.parse('2026-09-27T00:00:00Z'),
      version: 3,
      monolingual: const [],
      bilingual: const [],
      unified: unified,
    );

ProviderContainer _container({
  required ManifestData manifest,
  required List<String> downloaded,
  required Map<String, String> checksums,
}) =>
    ProviderContainer(
      overrides: [
        manifestDataProvider.overrideWith((ref) async => manifest),
        downloadedDictIdsProvider.overrideWith((ref) => downloaded),
        dictChecksumProvider.overrideWith((ref) => checksums),
      ],
    );

void main() {
  group('dictUpdatesAvailableProvider', () {
    test('lists installed entries whose manifest checksum changed', () async {
      final c = _container(
        manifest: _manifest([_entry(id: 'a', md5: 'NEW')]),
        downloaded: ['a'],
        checksums: {'a': 'OLD'},
      );
      addTearDown(c.dispose);
      await c.read(manifestDataProvider.future);
      expect(c.read(dictUpdatesAvailableProvider).map((e) => e.id), ['a']);
    });

    test('empty when everything matches the manifest', () {
      final c = _container(
        manifest: _manifest([_entry(id: 'a', md5: 'SAME')]),
        downloaded: ['a'],
        checksums: {'a': 'SAME'},
      );
      addTearDown(c.dispose);
      expect(c.read(dictUpdatesAvailableProvider), isEmpty);
    });

    test('empty when not downloaded or no checksum baseline', () {
      final c = _container(
        manifest: _manifest([_entry(id: 'a', md5: 'NEW')]),
        downloaded: const [],
        checksums: const {},
      );
      addTearDown(c.dispose);
      expect(c.read(dictUpdatesAvailableProvider), isEmpty);

      final c2 = _container(
        manifest: _manifest([_entry(id: 'a', md5: 'NEW')]),
        downloaded: ['a'],
        checksums: const {},
      );
      addTearDown(c2.dispose);
      // No baseline ⇒ cannot prove staleness ⇒ no false update prompt.
      expect(c2.read(dictUpdatesAvailableProvider), isEmpty);
    });

    test('only stale entries listed among several', () async {
      final c = _container(
        manifest: _manifest([
          _entry(id: 'a', md5: 'SAME'),
          _entry(id: 'b', md5: 'NEW'),
        ]),
        downloaded: ['a', 'b'],
        checksums: {'a': 'SAME', 'b': 'OLD'},
      );
      addTearDown(c.dispose);
      await c.read(manifestDataProvider.future);
      expect(c.read(dictUpdatesAvailableProvider).map((e) => e.id), ['b']);
    });
  });
}
