// Guards the shadowing-crash fix: macOS kills the process on first
// microphone / speech-recognition use when these Info.plist descriptions
// are missing (tapping Shadow then instantly quits the app).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS privacy descriptions for shadowing', () {
    test('Info.plist declares microphone + speech recognition usage', () async {
      final text = await File('macos/Runner/Info.plist').readAsString();
      for (final key in [
        'NSMicrophoneUsageDescription',
        'NSSpeechRecognitionUsageDescription',
      ]) {
        final match = RegExp(
          '<key>$key</key>\\s*<string>([^<]+)</string>',
        ).firstMatch(text);
        expect(match, isNotNull,
            reason: '$key missing — tapping Shadow will kill the app');
        expect(match!.group(1)!.trim().isNotEmpty, isTrue,
            reason: '$key must have a non-empty message');
      }
    });
  });
}
