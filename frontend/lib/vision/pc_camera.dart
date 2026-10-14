import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One still frame from the PC webcam via ffmpeg. No extra Flutter camera plugin.
class PcCamera {
  Future<File> captureJpeg() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/face_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ffmpeg = _bin('ffmpeg');
    if (ffmpeg.isEmpty) {
      throw StateError('ffmpeg is required to use the webcam on this PC.');
    }
    final devices = await _videoDevices();
    if (devices.isEmpty) {
      throw StateError('No webcam was found.');
    }
    for (final device in devices) {
      final result = await Process.run(ffmpeg, [
        '-y',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'v4l2',
        '-video_size',
        '640x480',
        '-i',
        device,
        '-frames:v',
        '1',
        path,
      ]);
      final file = File(path);
      if (result.exitCode == 0 && file.existsSync() && file.lengthSync() > 100) {
        return file;
      }
    }
    throw StateError('Could not take a webcam photo.');
  }

  Future<List<String>> listDevices() => _videoDevices();

  Future<List<String>> _videoDevices() async {
    final found = <String>[];
    for (var i = 0; i < 8; i++) {
      final path = '/dev/video$i';
      if (File(path).existsSync()) {
        found.add(path);
      }
    }
    return found;
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
}
