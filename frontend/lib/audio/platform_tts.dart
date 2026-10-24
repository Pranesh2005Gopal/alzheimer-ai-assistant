import 'platform_tts_stub.dart'
    if (dart.library.js_interop) 'platform_tts_web.dart';

abstract class PlatformTts {
  Future<void> init({
    required void Function(int playbackId) onStart,
    required void Function(int playbackId) onComplete,
    required void Function(int playbackId) onCancel,
    required void Function(int playbackId, String error) onError,
  });

  Future<void> speak(String text, {String? locale, required int playbackId});
  Future<void> stop();
  void dispose();
}

PlatformTts getPlatformTts() => createPlatformTts();
