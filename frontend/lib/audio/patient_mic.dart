import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Captures the real PC/phone microphone.
///
/// Flutter's Linux `record` plugin does not actually record, so Linux uses
/// ffmpeg / PulseAudio / PipeWire. Other platforms keep the `record` package.
class PatientMic {
  PatientMic() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  Timer? _levelTimer;
  Process? _process;
  bool _usingSystem = false;

  Future<void> start({required String path, void Function(String status)? onLevel}) async {
    _usingSystem = false;
    if (!kIsWeb && Platform.isLinux) {
      final started = await _startLinux(path);
      if (started) {
        onLevel?.call('Listening — you can pause. Press STOP when you are finished.');
        return;
      }
    }
    final device = await _preferredMic();
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 16000,
        bitRate: 256000,
        device: device,
        autoGain: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: path,
    );
    _levelTimer?.cancel();
    if (onLevel != null) {
      _levelTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        try {
          final amp = await _recorder.getAmplitude();
          if (amp.current > -42) {
            onLevel('Listening — I can hear you. Pause is okay. Press STOP when done.');
          } else {
            onLevel('Listening — speak closer to the microphone.');
          }
        } catch (_) {}
      });
    }
  }

  Future<String?> stop() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    if (_usingSystem) {
      final process = _process;
      _process = null;
      _usingSystem = false;
      if (process != null) {
        process.kill(ProcessSignal.sigint);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return null;
    }
    final path = await _recorder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return path;
  }

  Future<bool> _startLinux(String path) async {
    final source = await _pulseMicSource();
    final attempts = <List<String>>[];
    final ffmpeg = _bin('ffmpeg');
    if (ffmpeg.isNotEmpty) {
      attempts.add([
        ffmpeg,
        '-nostdin',
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'pulse',
        '-i',
        source ?? 'default',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-af',
        'highpass=f=80,volume=10dB,dynaudnorm=f=75:g=20',
        '-c:a',
        'pcm_s16le',
        path,
      ]);
      attempts.add([
        ffmpeg,
        '-nostdin',
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'pulse',
        '-i',
        source ?? 'default',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        path,
      ]);
    }
    final parecord = _bin('parecord');
    if (parecord.isNotEmpty) {
      attempts.add([
        parecord,
        '--channels=1',
        '--rate=16000',
        '--file-format=wav',
        if (source != null) '--device=$source',
        path,
      ]);
    }
    final pwRecord = _bin('pw-record');
    if (pwRecord.isNotEmpty) {
      attempts.add([
        pwRecord,
        '--rate',
        '16000',
        '--channels',
        '1',
        path,
      ]);
    }
    final arecord = _bin('arecord');
    if (arecord.isNotEmpty) {
      attempts.add([
        arecord,
        '-f',
        'S16_LE',
        '-c',
        '1',
        '-r',
        '16000',
        path,
      ]);
    }

    for (final command in attempts) {
      try {
        final process = await Process.start(command.first, command.sublist(1));
        process.stdout.drain();
        process.stderr.drain();
        final died = await process.exitCode.timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => -999,
        );
        if (died != -999) {
          continue;
        }
        _process = process;
        _usingSystem = true;
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<String?> _pulseMicSource() async {
    final pactl = _bin('pactl');
    if (pactl.isEmpty) {
      return null;
    }
    try {
      final def = await Process.run(pactl, ['get-default-source']);
      final defaultSource = (def.stdout as String).trim();
      if (defaultSource.isNotEmpty && !defaultSource.toLowerCase().contains('monitor')) {
        return defaultSource;
      }
    } catch (_) {}
    try {
      final listed = await Process.run(pactl, ['list', 'short', 'sources']);
      final lines = (listed.stdout as String).split('\n');
      for (final line in lines) {
        final parts = line.split('\t');
        if (parts.length < 2) {
          continue;
        }
        final name = parts[1];
        if (name.toLowerCase().contains('monitor')) {
          continue;
        }
        return name;
      }
    } catch (_) {}
    return null;
  }

  Future<InputDevice?> _preferredMic() async {
    try {
      final devices = await _recorder.listInputDevices();
      if (devices.isEmpty) {
        return null;
      }
      bool isMonitor(InputDevice d) {
        final blob = '${d.id} ${d.label}'.toLowerCase();
        return blob.contains('monitor') || blob.contains('loopback');
      }

      bool looksLikeMic(InputDevice d) {
        final blob = '${d.id} ${d.label}'.toLowerCase();
        return blob.contains('mic') ||
            blob.contains('input') ||
            blob.contains('headset') ||
            blob.contains('webcam') ||
            blob.contains('usb');
      }

      final live = devices.where((d) => !isMonitor(d)).toList();
      for (final device in live) {
        if (looksLikeMic(device)) {
          return device;
        }
      }
      if (live.isNotEmpty) {
        return live.first;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _bin(String name) {
    const dirs = ['/usr/bin', '/usr/local/bin', '/bin'];
    for (final dir in dirs) {
      final file = File('$dir/$name');
      if (file.existsSync()) {
        return file.path;
      }
    }
    return '';
  }

  void dispose() {
    _levelTimer?.cancel();
    final process = _process;
    _process = null;
    process?.kill(ProcessSignal.sigkill);
    _recorder.dispose();
  }
}

Future<String> recordingPath() async {
  if (kIsWeb) {
    return 'patient_turn_${DateTime.now().millisecondsSinceEpoch}.wav';
  }
  final dir = await getTemporaryDirectory();
  return '${dir.path}/patient_turn_${DateTime.now().millisecondsSinceEpoch}.wav';
}
