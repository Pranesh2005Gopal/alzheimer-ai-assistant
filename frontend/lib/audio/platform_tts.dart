import 'package:flutter/foundation.dart';

import 'platform_tts_stub.dart'
    if (dart.library.js_interop) 'platform_tts_web.dart';

abstract class PlatformTts {
  Future<void> init({
    required VoidCallback onStart,
    required VoidCallback onComplete,
    required VoidCallback onCancel,
    required void Function(String error) onError,
  });

  Future<void> speak(String text, {String? locale});
  Future<void> stop();
  void dispose();
}

PlatformTts getPlatformTts() => createPlatformTts();
