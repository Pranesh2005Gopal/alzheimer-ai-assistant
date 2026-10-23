import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'platform_tts.dart';

PlatformTts createPlatformTts() => PlatformTtsWeb();

class PlatformTtsWeb implements PlatformTts {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  void Function(String error)? _onError;

  web.SpeechSynthesisUtterance? _activeUtterance;
  Timer? _keepAliveTimer;
  List<web.SpeechSynthesisVoice> _voices = [];

  @override
  Future<void> init({
    required VoidCallback onStart,
    required VoidCallback onComplete,
    required VoidCallback onCancel,
    required void Function(String error) onError,
  }) async {
    _onStart = onStart;
    _onComplete = onComplete;
    _onCancel = onCancel;
    _onError = onError;

    _loadVoices();

    // In Chrome, getVoices() is asynchronous; listen to onvoiceschanged when ready
    try {
      web.window.speechSynthesis.onvoiceschanged = ((web.Event _) {
        _loadVoices();
      }).toJS;
    } catch (e) {
      debugPrint('[WebTTS] onvoiceschanged error: $e');
    }

    debugPrint('[WebTTS] Initialized browser SpeechSynthesis');
  }

  void _loadVoices() {
    try {
      final voiceList = web.window.speechSynthesis.getVoices().toDart;
      _voices = voiceList;
      debugPrint('[WebTTS] Loaded ${_voices.length} browser voices');
    } catch (e) {
      debugPrint('[WebTTS] Could not query voices: $e');
    }
  }

  web.SpeechSynthesisVoice? _selectVoice(String text, String? preferredLocale) {
    if (_voices.isEmpty) {
      _loadVoices();
    }
    if (_voices.isEmpty) {
      return null;
    }

    final isTamil = _isTamil(text);
    final targetLang = preferredLocale?.toLowerCase() ?? (isTamil ? 'ta-in' : 'en-in');

    // 1. Exact or prefix match for target locale (e.g. en-in, ta-in)
    for (final v in _voices) {
      final vLang = v.lang.toLowerCase().replaceAll('_', '-');
      if (vLang == targetLang || vLang.startsWith(targetLang)) {
        return v;
      }
    }

    // 2. Language code match (e.g. 'ta' or 'en')
    final langCode = targetLang.split('-').first;
    for (final v in _voices) {
      final vLang = v.lang.toLowerCase();
      if (vLang.startsWith(langCode)) {
        return v;
      }
    }

    // 3. Fallback English
    if (!isTamil) {
      for (final v in _voices) {
        if (v.lang.toLowerCase().startsWith('en')) {
          return v;
        }
      }
    }

    // 4. Fallback default
    for (final v in _voices) {
      if (v.default_) {
        return v;
      }
    }
    return _voices.first;
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
  Future<void> speak(String text, {String? locale}) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      debugPrint('[WebTTS] Empty text received, skipping speech');
      return;
    }

    // Cancel any ongoing or stuck speech before starting new utterance
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    try {
      web.window.speechSynthesis.cancel();
      if (web.window.speechSynthesis.paused) {
        web.window.speechSynthesis.resume();
      }
    } catch (_) {}

    // In Chrome, each utterance MUST be a fresh SpeechSynthesisUtterance instance
    final utterance = web.SpeechSynthesisUtterance(clean);
    utterance.rate = 0.9;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;

    final voice = _selectVoice(clean, locale);
    if (voice != null) {
      utterance.voice = voice;
      utterance.lang = voice.lang;
    } else {
      utterance.lang = (locale ?? (_isTamil(clean) ? 'ta-IN' : 'en-US'));
    }

    // Retain strong reference to prevent Chrome garbage-collecting the utterance mid-speech
    _activeUtterance = utterance;

    utterance.onstart = ((web.Event _) {
      debugPrint('[WebTTS] Utterance playback started (${clean.length} chars)');
      _onStart?.call();
    }).toJS;

    utterance.onend = ((web.Event _) {
      debugPrint('[WebTTS] Utterance playback completed');
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      if (_activeUtterance == utterance) {
        _activeUtterance = null;
      }
      _onComplete?.call();
    }).toJS;

    utterance.onerror = ((web.SpeechSynthesisErrorEvent e) {
      final errorType = e.error;
      debugPrint('[WebTTS] Utterance error: $errorType');
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      if (_activeUtterance == utterance) {
        _activeUtterance = null;
      }
      if (errorType == 'canceled' || errorType == 'interrupted') {
        _onCancel?.call();
      } else {
        _onError?.call(errorType);
      }
    }).toJS;

    // Workaround for Chrome bug where long speech (>15s) pauses silently
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      try {
        if (web.window.speechSynthesis.speaking) {
          web.window.speechSynthesis.pause();
          web.window.speechSynthesis.resume();
        } else {
          timer.cancel();
        }
      } catch (_) {
        timer.cancel();
      }
    });

    try {
      debugPrint('[WebTTS] Invoking window.speechSynthesis.speak() (voice: ${voice?.name ?? "default"}, lang: ${utterance.lang})');
      web.window.speechSynthesis.speak(utterance);
      if (web.window.speechSynthesis.paused) {
        web.window.speechSynthesis.resume();
      }
    } catch (e) {
      debugPrint('[WebTTS] Exception invoking speak: $e');
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      _activeUtterance = null;
      _onError?.call(e.toString());
    }
  }

  @override
  Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _activeUtterance = null;
    try {
      web.window.speechSynthesis.cancel();
    } catch (_) {}
    _onCancel?.call();
  }

  @override
  void dispose() {
    stop();
  }
}
