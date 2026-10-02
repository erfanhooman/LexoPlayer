import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Service providing offline text-to-speech pronunciation.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45); // Comfortable learning speed
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
    } catch (e) {
      developer.log('Failed to initialize FlutterTts: $e', name: 'TtsService');
    }
  }

  /// Speaks the provided [text] (typically a word or short phrase).
  Future<void> speak(String text, {String language = 'en-US'}) async {
    if (text.trim().isEmpty) return;
    try {
      await _ensureInitialized();
      await _tts.setLanguage(language);
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      developer.log('TTS speak error: $e', name: 'TtsService');
    }
  }

  /// Stops any currently playing speech.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService();
});
