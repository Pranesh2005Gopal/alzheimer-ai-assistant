/// Platform-adaptive live camera preview widget.
///
/// - **Android / iOS**: uses the `camera` plugin to display a live
///   `CameraPreview` texture directly in the Flutter widget tree.
/// - **Linux desktop** (and macOS/Windows as fallback): polls the
///   assistant backend's `GET /v1/vision/stream` MJPEG endpoint and
///   refreshes an `Image.memory` widget at ~10 fps.  No GStreamer or
///   extra native plugin is required.
library;

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Continuously-visible camera preview widget.
///
/// [apiBase] is used only on desktop to reach the MJPEG stream.
/// [onFrameAvailable] is called with JPEG bytes each time a live frame arrives
/// (used by the caller to request recognition on a captured frame).
class CameraLivePreview extends StatefulWidget {
  const CameraLivePreview({
    super.key,
    required this.apiBase,
    this.onFrameAvailable,
    this.overlayWidget,
  });

  /// Base URL of the assistant backend, e.g. `http://127.0.0.1:8080`.
  final String apiBase;

  /// Optional callback that receives the current JPEG frame bytes.
  /// Called roughly every 100 ms on desktop, on each new frame on mobile.
  final void Function(Uint8List jpeg)? onFrameAvailable;

  /// Optional widget rendered on top of the camera feed (oval guide, etc.).
  final Widget? overlayWidget;

  @override
  State<CameraLivePreview> createState() => _CameraLivePreviewState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _CameraLivePreviewState extends State<CameraLivePreview> {
  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Mobile-specific
  CameraController? _camCtrl;
  bool _mobileReady = false;
  String? _mobileError;

  // Desktop-specific
  Uint8List? _desktopFrame;
  StreamSubscription<List<int>>? _streamSub;
  http.Client? _httpClient; // kept so we can close it on dispose
  final List<int> _buf = [];
  bool _desktopError = false;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _initMobile();
    } else {
      _initDesktop();
    }
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    _streamSub?.cancel();
    _httpClient?.close();
    super.dispose();
  }

  // ---------- Mobile (camera plugin) ----------

  Future<void> _initMobile() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _mobileError = 'No camera found on this device.');
        return;
      }
      // Prefer front camera for face recognition
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _camCtrl = ctrl;
        _mobileReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _mobileError = 'Camera error: $e');
    }
  }

  // ---------- Desktop (MJPEG via HTTP) ----------

  Future<void> _initDesktop() async {
    final streamUrl = '${widget.apiBase}/v1/vision/stream';
    try {
      final client = http.Client();
      _httpClient = client; // stored so dispose() can close it
      final request = http.Request('GET', Uri.parse(streamUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        if (mounted) setState(() => _desktopError = true);
        client.close();
        _httpClient = null;
        return;
      }

      // MJPEG stream: parse "--frame\r\nContent-Type: image/jpeg\r\n\r\n<bytes>\r\n"
      _streamSub = response.stream.listen(
        (chunk) {
          _buf.addAll(chunk);
          _tryExtractFrame();
        },
        onError: (_) {
          if (mounted) setState(() => _desktopError = true);
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (mounted) setState(() => _desktopError = true);
    }
  }

  /// Scans [_buf] for JPEG SOI (0xFF 0xD8) … EOI (0xFF 0xD9) markers and
  /// extracts complete JPEG images, discarding the MJPEG boundary text.
  void _tryExtractFrame() {
    // Find JPEG SOI marker
    for (int i = 0; i < _buf.length - 1; i++) {
      if (_buf[i] == 0xFF && _buf[i + 1] == 0xD8) {
        // Find EOI
        for (int j = i + 2; j < _buf.length - 1; j++) {
          if (_buf[j] == 0xFF && _buf[j + 1] == 0xD9) {
            final jpeg = Uint8List.fromList(_buf.sublist(i, j + 2));
            _buf.removeRange(0, j + 2);
            if (mounted) {
              setState(() => _desktopFrame = jpeg);
              widget.onFrameAvailable?.call(jpeg);
            }
            return;
          }
        }
        break; // SOI found but EOI not yet arrived — wait for more data
      }
    }
    // Keep the buffer from growing unboundedly if no JPEG is found
    if (_buf.length > 512 * 1024) {
      _buf.clear();
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isMobile) {
      if (_mobileError != null) {
        content = _ErrorPlaceholder(message: _mobileError!);
      } else if (!_mobileReady || _camCtrl == null) {
        content = const _LoadingPlaceholder();
      } else {
        content = CameraPreview(_camCtrl!);
      }
    } else {
      if (_desktopError) {
        content = const _ErrorPlaceholder(
          message: 'Camera stream unavailable.\nMake sure the assistant server is running.',
        );
      } else if (_desktopFrame == null) {
        content = const _LoadingPlaceholder(label: 'Connecting to camera…');
      } else {
        content = Image.memory(
          _desktopFrame!,
          gaplessPlayback: true,
          fit: BoxFit.cover,
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (widget.overlayWidget != null) widget.overlayWidget!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper placeholders
// ---------------------------------------------------------------------------

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({this.label = 'Starting camera…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CaptureHelper — lets the scan dialog grab a still from the live feed
// ---------------------------------------------------------------------------

/// Allows the scan dialog to request a JPEG snapshot from whichever camera
/// source is currently active (CameraController on mobile, or the most recent
/// MJPEG frame on desktop).
class CaptureHelper {
  CaptureHelper(this._camCtrl, this._desktopFrame, this._isMobile);

  final CameraController? _camCtrl;
  final Uint8List? _desktopFrame;
  final bool _isMobile;

  /// Returns JPEG bytes of the most recent frame, or `null` if unavailable.
  Future<Uint8List?> captureJpeg() async {
    if (_isMobile) {
      final ctrl = _camCtrl;
      if (ctrl == null || !ctrl.value.isInitialized) return null;
      try {
        final xfile = await ctrl.takePicture();
        return await xfile.readAsBytes();
      } catch (_) {
        return null;
      }
    } else {
      return _desktopFrame;
    }
  }
}
