import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';

void main() {
  group('compareVersions', () {
    test('equal versions', () {
      expect(compareVersions('2.2.0-beta', 'v2.2.0-beta'), 0);
      expect(compareVersions('2.2.0', '2.2.0'), 0);
    });

    test('newer patch/minor/major detected', () {
      expect(compareVersions('2.2.0-beta', 'v2.2.1-beta'), lessThan(0));
      expect(compareVersions('2.2.0-beta', 'v2.3.0-beta'), lessThan(0));
      expect(compareVersions('2.2.0-beta', 'v3.0.0'), lessThan(0));
    });

    test('older installed vs newer latest', () {
      // Installed 2.2.0-beta+4 (PackageInfo strips "+4" -> "2.2.0-beta").
      expect(compareVersions('2.2.0-beta', 'v2.2.0'), lessThan(0));
    });

    test('release beats pre-release', () {
      expect(compareVersions('2.2.0-beta', '2.2.0'), lessThan(0));
      expect(compareVersions('2.2.0', '2.2.0-beta'), greaterThan(0));
    });

    test('no false positive when up to date', () {
      expect(compareVersions('2.2.0-beta', 'v2.2.0-beta'), 0);
      expect(compareVersions('2.3.0', 'v2.2.0-beta'), greaterThan(0));
    });

    test('build metadata ignored', () {
      expect(compareVersions('2.2.0-beta+4', 'v2.2.0-beta'), 0);
    });
  });

  group('macOS bundle + staged-update helpers', () {
    test('staged-update asset detection', () {
      // On macOS hosts the ZIP is a self-installer; DMG/others are not.
      expect(
          isSelfInstallAsset('LexoPlayer-macOS.zip'), equals(Platform.isMacOS));
      expect(isSelfInstallAsset('LexoPlayer-macOS.dmg'), isFalse);
      expect(isSelfInstallAsset('LexoPlayer-Setup-x64.exe'), isFalse);

      const pending = PendingUpdate(
        tag: 'v2.3.3-beta',
        path: '/tmp/LexoPlayer-macOS.zip',
        assetName: 'LexoPlayer-macOS.zip',
      );
      expect(pending.isSelfInstall, equals(Platform.isMacOS));
    });

    test('resolves .app ancestor from executable path', () {
      expect(
        findMacAppBundle('/Applications/Lexo.app/Contents/MacOS/lexo_player'),
        '/Applications/Lexo.app',
      );
      expect(
        findMacAppBundle(
            '/Users/me/Downloads/LexoPlayer-macOS/Lexo.app/Contents/MacOS/Lexo'),
        '/Users/me/Downloads/LexoPlayer-macOS/Lexo.app',
      );
    });

    test('returns null without .app ancestor', () {
      expect(findMacAppBundle('/usr/bin/lexo_player'), isNull);
      expect(
          findMacAppBundle('C:\\Program Files\\Lexo\\lexo_player.exe'), isNull);
    });
  });

  group(
    'pickPlatformAsset (macOS self-install ZIP)',
    () {
      test('prefers macOS ZIP over DMG', () {
        final assets = [
          {
            'name': 'LexoPlayer-macOS.dmg',
            'browser_download_url': 'https://example.com/LexoPlayer-macOS.dmg'
          },
          {
            'name': 'LexoPlayer-macOS.zip',
            'browser_download_url': 'https://example.com/LexoPlayer-macOS.zip'
          },
        ];
        final picked = pickPlatformAsset(assets);
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.zip'));
      });

      test('falls back to DMG when no ZIP exists (old releases)', () {
        final assets = [
          {
            'name': 'LexoPlayer-macOS.dmg',
            'browser_download_url': 'https://example.com/LexoPlayer-macOS.dmg'
          },
        ];
        final picked = pickPlatformAsset(assets);
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.dmg'));
      });
    },
    // Asset preference is Platform-dependent; these expectations only hold
    // where Platform.isMacOS is true.
    skip: !Platform.isMacOS,
  );
}
