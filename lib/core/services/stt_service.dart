import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Service managing Speech-to-Text (STT) for shadowing practice.
class SttService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isAvailable = false;
  String? _lastError;

  bool get isAvailable => _isAvailable;
  bool get isListening => _speech.isListening;
  String? get lastError => _lastError;

  /// Initializes the STT engine and checks for microphone permissions.
  Future<bool> initialize() async {
    if (_isInitialized) return _isAvailable;
    try {
      _isAvailable = await _speech.initialize(
        onError: (val) {
          developer.log('STT Error: ${val.errorMsg}', name: 'SttService');
          _lastError = val.errorMsg;
        },
        onStatus: (status) {
          developer.log('STT Status: $status', name: 'SttService');
        },
      );
      _isInitialized = true;
      return _isAvailable;
    } catch (e) {
      developer.log('STT initialization failed: $e', name: 'SttService');
      _isAvailable = false;
      _isInitialized = true;
      _lastError = e.toString();
      return false;
    }
  }

  /// Begins listening for voice input, emitting recognized words through [onResult].
  Future<bool> startListening({
    required Function(String words) onResult,
    String localeId = 'en_US',
  }) async {
    final available = await initialize();
    if (!available) return false;

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
        },
        localeId: localeId,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
      return true;
    } catch (e) {
      developer.log('Failed to start STT listening: $e', name: 'SttService');
      _lastError = e.toString();
      return false;
    }
  }

  /// Stops listening while keeping recognized text intact.
  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  /// Cancels speech recognition.
  Future<void> cancel() async {
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
    } catch (_) {}
  }
}

final sttServiceProvider = Provider<SttService>((ref) {
  return SttService();
});
