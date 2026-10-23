import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';

/// Play assistant speech with system tools on Linux (ffplay/paplay/pw-play)
/// or audioplayers on other platforms. Waits until playback finishes.
class SpeechPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Completer<void>? _activeCompleter;
  StreamSubscription? _completeSub;
  StreamSubscription? _stateSub;

  Future<void> playWav(List<int> audioBytes) async {
    if (audioBytes.length < 45) {
      return;
    }
    await stop();

    final completer = Completer<void>();
    _activeCompleter = completer;

    void finish() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) => finish());
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        finish();
      }
    });

    try {
      if (kIsWeb) {
        debugPrint('[SpeechPlayer] Playing ${audioBytes.length} audio bytes in browser');
        await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
        await completer.future.timeout(const Duration(seconds: 45), onTimeout: () {});
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/assistant_reply.wav');
      await file.writeAsBytes(audioBytes, flush: true);
      final played = await _playWithSystemTools(file.path);
      if (!played) {
        debugPrint('[SpeechPlayer] Playing via AudioPlayer device file fallback');
        await _audioPlayer.play(DeviceFileSource(file.path));
        await completer.future.timeout(const Duration(seconds: 45), onTimeout: () {});
      }
    } catch (e) {
      debugPrint('[SpeechPlayer] Playback error: $e');
      rethrow;
    } finally {
      await _completeSub?.cancel();
      await _stateSub?.cancel();
      _completeSub = null;
      _stateSub = null;
      if (_activeCompleter == completer) {
        _activeCompleter = null;
      }
    }
  }

  Future<bool> _playWithSystemTools(String path) async {
    if (kIsWeb) return false;
    final attempts = <List<String>>[
      [_bin('ffplay'), '-nodisp', '-autoexit', '-loglevel', 'quiet', path],
      [_bin('paplay'), path],
      [_bin('pw-play'), path],
      [_bin('aplay'), '-q', path],
      [
        _bin('ffmpeg'),
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        path,
        '-f',
        'pulse',
        'default',
      ],
    ];
    for (final command in attempts) {
      final executable = command.first;
      if (executable.isEmpty || !File(executable).existsSync()) {
        continue;
      }
      try {
        final result = await Process.run(executable, command.sublist(1));
        if (result.exitCode == 0) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  static String _bin(String name) {
    if (kIsWeb) return '';
    const dirs = ['/usr/bin', '/usr/local/bin', '/bin'];
    for (final dir in dirs) {
      final file = File('$dir/$name');
      if (file.existsSync()) {
        return file.path;
      }
    }
    final paths = (Platform.environment['PATH'] ?? '').split(':');
    for (final folder in paths) {
      if (folder.isEmpty) {
        continue;
      }
      final file = File('$folder/$name');
      if (file.existsSync()) {
        return file.path;
      }
    }
    return '';
  }

  Future<void> stop() async {
    try {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        _activeCompleter!.complete();
      }
      _activeCompleter = null;
      await _completeSub?.cancel();
      await _stateSub?.cancel();
      _completeSub = null;
      _stateSub = null;
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}
