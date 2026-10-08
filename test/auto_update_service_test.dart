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

  group('formatBytes (download progress labels)', () {
    test('zero and bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
      expect(formatBytes(300), '300 B');
    });

    test('kilobytes', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(850 * 1024), '850.0 KB');
    });

    test('megabytes and gigabytes', () {
      expect(formatBytes(12 * 1024 * 1024 + 512 * 1024), '12.5 MB');
      expect(formatBytes(245 * 1024 * 1024), '245.0 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
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
    'matchAsset (per-platform selection rules)',
    () {
      List<Map<String, String>> assets(List<String> names) => [
            for (final n in names)
              {
                'name': n,
                'browser_download_url': 'https://example.com/$n',
              }
          ];

      test('macOS: prefers ZIP over DMG', () {
        final picked = matchAsset(
          assets(['LexoPlayer-macOS.dmg', 'LexoPlayer-macOS.zip']),
          [
            (n) => n.endsWith('.zip') && n.contains('mac'),
            (n) => n.endsWith('.dmg'),
          ],
        );
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.zip'));
      });

      test('macOS: falls back to DMG when no ZIP exists', () {
        final picked = matchAsset(
          assets(['LexoPlayer-macOS.dmg']),
          [
            (n) => n.endsWith('.zip') && n.contains('mac'),
            (n) => n.endsWith('.dmg'),
          ],
        );
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.dmg'));
      });

      test('windows: picks SETUP exe', () {
        final picked = matchAsset(
          assets(['LexoPlayer-macOS.dmg', 'LexoPlayer-Setup-x64.exe']),
          [(n) => n.endsWith('.exe')],
        );
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.exe'));
      });

      test('linux: picks AppImage', () {
        final picked = matchAsset(
          assets(['LexoPlayer-macOS.dmg', 'LexoPlayer-Linux.AppImage']),
          [(n) => n.endsWith('.appimage')],
        );
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.appimage'));
      });

      test('android: picks APK', () {
        final picked = matchAsset(
          assets(['LexoPlayer-macOS.dmg', 'LexoPlayer-Android.apk']),
          [(n) => n.endsWith('.apk')],
        );
        expect(picked, isNotNull);
        expect(picked!['name'], contains('.apk'));
      });

      test('empty or no match returns null', () {
        expect(matchAsset([], [(n) => n.endsWith('.exe')]), isNull);
        expect(
            matchAsset(
                assets(['LexoPlayer-macOS.dmg']), [(n) => n.endsWith('.exe')]),
            isNull);
      });

      test('live v2.3.3-beta asset set resolves every platform', () {
        final live = assets([
          'LexoPlayer-Android.apk',
          'LexoPlayer-Linux.AppImage',
          'LexoPlayer-macOS.dmg',
          'LexoPlayer-macOS.zip',
          'LexoPlayer-Setup-x64.exe',
        ]);
        expect(matchAsset(live, [(n) => n.endsWith('.apk')])!['name'],
            contains('.apk'));
        expect(matchAsset(live, [(n) => n.endsWith('.appimage')])!['name'],
            contains('.appimage'));
        expect(matchAsset(live, [(n) => n.endsWith('.exe')])!['name'],
            contains('.exe'));
        expect(
            matchAsset(live, [
              (n) => n.endsWith('.zip') && n.contains('mac'),
              (n) => n.endsWith('.dmg'),
            ])!['name'],
            contains('.zip'));
      });
    },
  );

  group('staged downloads + linux self-install routing', () {
    test('staged downloads only on desktop', () {
      expect(stagedDownloadSupported(isAndroid: false, isIOS: false), isTrue);
      expect(stagedDownloadSupported(isAndroid: true, isIOS: false), isFalse);
      expect(stagedDownloadSupported(isAndroid: false, isIOS: true), isFalse);
    });

    test('resolveLinuxAppImagePath prefers APPIMAGE env', () {
      expect(
        resolveLinuxAppImagePath(
          environment: {'APPIMAGE': '/home/u/Apps/LexoPlayer-Linux.AppImage'},
          executablePath: '/tmp/.mount_XYZ/usr/bin/lexo_player',
        ),
        '/home/u/Apps/LexoPlayer-Linux.AppImage',
      );
    });

    test('resolveLinuxAppImagePath falls back to .AppImage executable', () {
      expect(
        resolveLinuxAppImagePath(
          environment: {},
          executablePath: '/home/u/LexoPlayer-Linux.AppImage',
        ),
        '/home/u/LexoPlayer-Linux.AppImage',
      );
    });

    test('resolveLinuxAppImagePath null for bundle/dev runs', () {
      expect(
        resolveLinuxAppImagePath(
          environment: {},
          executablePath: '/tmp/.mount_XYZ/usr/bin/lexo_player',
        ),
        isNull,
      );
      expect(
        resolveLinuxAppImagePath(
          environment: {},
          executablePath: r'C:\Program Files\LexoPlayer\lexo_player.exe',
        ),
        isNull,
      );
    });
  });
}
