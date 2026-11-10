import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Foreground-only voice input through the platform recognizer (fa-IR).
class VoiceService {
  VoiceService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  bool _available = false;
  String? _lastError;

  String? get lastError => _lastError;

  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          _lastError = error.errorMsg;
        },
        onStatus: (_) {},
      );
      if (!_available) _lastError ??= 'unavailable';
    } catch (e) {
      _available = false;
      _lastError = e.toString();
    }
    return _available;
  }

  Future<bool> hasPersianLocale() async {
    if (!await ensureInitialized()) return false;
    try {
      final locales = await _speech.locales();
      return locales.any((l) => l.localeId.replaceAll('-', '_').toLowerCase().startsWith('fa'));
    } catch (_) {
      return false;
    }
  }

  /// Listens once and completes with the final transcript (or null on failure/timeout).
  Future<String?> listenOnce({required String localeId, Duration timeout = const Duration(seconds: 30)}) async {
    if (!await ensureInitialized()) return null;
    final completer = Completer<String?>();
    final buffer = StringBuffer();
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          buffer
            ..clear()
            ..write(result.recognizedWords);
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(buffer.toString().trim());
          }
        },
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          onDevice: true,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
      );
      return await completer.future.timeout(timeout + const Duration(seconds: 2), onTimeout: () {
        unawaited(_speech.stop());
        final text = buffer.toString().trim();
        return text.isEmpty ? null : text;
      });
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  bool get isListening => _speech.isListening;
}
