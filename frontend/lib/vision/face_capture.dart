import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pc_camera.dart';

enum CameraAvailability { unknown, available, unavailable, permissionRequired, error }

class CameraSnapshot {
  CameraSnapshot({required this.availability, this.detail = '', this.lastError = ''});

  final CameraAvailability availability;
  final String detail;
  final String lastError;
}

class FaceCapture {
  FaceCapture() : _pc = PcCamera(), _picker = ImagePicker();

  final PcCamera _pc;
  final ImagePicker _picker;

  Future<CameraSnapshot> probe() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.camera.status;
      if (status.isDenied || status.isRestricted) {
        return CameraSnapshot(
          availability: CameraAvailability.permissionRequired,
          detail: 'Camera permission has not been granted yet.',
        );
      }
      if (status.isPermanentlyDenied) {
        return CameraSnapshot(
          availability: CameraAvailability.permissionRequired,
          detail: 'Camera permission is blocked. Enable it in system settings.',
        );
      }
      return CameraSnapshot(
        availability: CameraAvailability.available,
        detail: 'Phone camera can be used for a still photo.',
      );
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      try {
        final devices = await _pc.listDevices();
        if (devices.isEmpty) {
          return CameraSnapshot(
            availability: CameraAvailability.unavailable,
            detail: 'No webcam was found on this computer.',
          );
        }
        return CameraSnapshot(
          availability: CameraAvailability.available,
          detail: 'Webcam ready (${devices.first}).',
        );
      } catch (error) {
        return CameraSnapshot(
          availability: CameraAvailability.error,
          detail: 'Could not check the webcam.',
          lastError: '$error',
        );
      }
    }
    return CameraSnapshot(
      availability: CameraAvailability.unavailable,
      detail: 'Camera capture is not supported on this platform.',
    );
  }

  Future<File?> capturePhoto() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        throw StateError('Camera permission is required to take a photo.');
      }
      final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1280);
      if (picked == null) {
        return null;
      }
      return File(picked.path);
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return _pc.captureJpeg();
    }
    throw StateError('Camera capture is not supported on this platform.');
  }
}
