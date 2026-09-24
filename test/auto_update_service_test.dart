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
}
