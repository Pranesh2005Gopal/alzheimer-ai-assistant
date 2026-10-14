import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';

/// Play assistant speech with system tools on Linux (ffplay/paplay/pw-play)
/// or audioplayers on other platforms. Waits until playback finishes.
class SpeechPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> playWav(List<int> audioBytes) async {
    if (audioBytes.length < 45) {
      return;
    }
    
    if (kIsWeb) {
      await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/assistant_reply.wav');
    await file.writeAsBytes(audioBytes, flush: true);
    final played = await _playWithSystemTools(file.path);
    if (!played) {
      final done = Completer<void>();
      final sub = _audioPlayer.onPlayerComplete.listen((_) {
        if (!done.isCompleted) {
          done.complete();
        }
      });
      try {
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(file.path));
        await done.future.timeout(const Duration(minutes: 2), onTimeout: () {});
      } finally {
        await sub.cancel();
      }
    }
  }

  Future<bool> _playWithSystemTools(String path) async {
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

  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
