import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'platform_tts.dart';

PlatformTts createPlatformTts() => PlatformTtsStub();

class PlatformTtsStub implements PlatformTts {
  final FlutterTts _flutterTts = FlutterTts();
  void Function(int playbackId)? _onStart;
  void Function(int playbackId)? _onComplete;
  void Function(int playbackId)? _onCancel;
  void Function(int playbackId, String error)? _onError;
  int _activePlaybackId = 0;

  @override
  Future<void> init({
    required void Function(int playbackId) onStart,
    required void Function(int playbackId) onComplete,
    required void Function(int playbackId) onCancel,
    required void Function(int playbackId, String error) onError,
  }) async {
    _onStart = onStart;
    _onComplete = onComplete;
    _onCancel = onCancel;
    _onError = onError;

    try {
      if (!Platform.isLinux) {
        await _flutterTts.awaitSpeakCompletion(true);
      }
      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);

      _flutterTts.setStartHandler(() {
        debugPrint('[NativeTTS] Started speech');
        _onStart?.call(_activePlaybackId);
      });

      _flutterTts.setCompletionHandler(() {
        debugPrint('[NativeTTS] Completed speech');
        _onComplete?.call(_activePlaybackId);
      });

      _flutterTts.setCancelHandler(() {
        debugPrint('[NativeTTS] Canceled speech');
        _onCancel?.call(_activePlaybackId);
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[NativeTTS] Error from engine: $msg');
        _onError?.call(_activePlaybackId, msg.toString());
      });
    } catch (e) {
      debugPrint('[NativeTTS] init failed: $e');
    }
  }

  bool _isTamil(String text) {
    for (final unit in text.codeUnits) {
      if (unit >= 0x0B80 && unit <= 0x0BFF) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> speak(
    String text, {
    String? locale,
    required int playbackId,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    try {
      _activePlaybackId = playbackId;
      final isTamil = _isTamil(clean);
      final preferredLang = locale ?? (isTamil ? 'ta-IN' : 'en-IN');
      bool languageSet = false;

      try {
        final dynamic isSupported = await _flutterTts.isLanguageAvailable(
          preferredLang,
        );
        if (isSupported == 1 || isSupported == true) {
          await _flutterTts.setLanguage(preferredLang);
          languageSet = true;
        }
      } catch (_) {}

      if (!languageSet) {
        try {
          await _flutterTts.setLanguage(isTamil ? 'ta' : 'en-US');
        } catch (_) {}
      }

      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);

      await _flutterTts.speak(clean);
    } catch (e) {
      debugPrint('[NativeTTS] speak exception: $e');
      _onError?.call(playbackId, e.toString());
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
    _onCancel?.call(_activePlaybackId);
  }

  @override
  void dispose() {
    stop();
  }
}
