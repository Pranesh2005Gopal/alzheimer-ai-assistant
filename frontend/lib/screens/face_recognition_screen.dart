import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/assistant_api.dart';
import '../state/assistant_controller.dart';
import '../vision/camera_live_preview.dart';
import '../vision/face_capture.dart';
import '../vision/pc_camera.dart';
import '../widgets/app_widgets.dart';

// =============================================================================
// Main Screen
// =============================================================================

class FaceRecognitionScreen extends StatelessWidget {
  const FaceRecognitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _FaceRecognitionBody(controller: controller),
    );
  }
}

class _FaceRecognitionBody extends StatelessWidget {
  const _FaceRecognitionBody({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller.camera;
    final (tone, statusLabel) = switch (camera.availability) {
      CameraAvailability.available => (StatusTone.ready, 'Camera Available'),
      CameraAvailability.permissionRequired => (StatusTone.warning, 'Permission Required'),
      CameraAvailability.unknown => (StatusTone.neutral, 'Status Unknown'),
      CameraAvailability.unavailable => (StatusTone.warning, 'Camera Unavailable'),
      CameraAvailability.error => (StatusTone.danger, 'Camera Error'),
    };

    final result = controller.lastRecognitionResult;
    final showUnknownBanner =
        result != null && !result.recognized && controller.shouldNotifyUnknownFace;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          AppCard(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.face_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Face Recognition',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Identify people and manage known faces. Tap Scan Face to begin.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Camera status ────────────────────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                    title: 'Camera Status', icon: Icons.camera_outlined),
                const SizedBox(height: 10),
                StatusBadge(label: statusLabel, tone: tone),
                if (camera.detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(camera.detail,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (camera.lastError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${camera.lastError}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Scan action ──────────────────────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                    title: 'Scan a Face',
                    icon: Icons.face_retouching_natural_outlined),
                const SizedBox(height: 8),
                Text(
                  'Point the camera at a person to identify them.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openScanDialog(context),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan Face'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Last result ──────────────────────────────────────────────────────
          if (result != null) ...[
            _LastResultCard(result: result),
            const SizedBox(height: 16),
          ],

          // ── Unknown-face banner ──────────────────────────────────────────────
          if (showUnknownBanner) ...[
            _UnknownPersonBanner(
              controller: controller,
              onAddPicture: () => _openAddPersonDialog(context,
                  withCamera: false, prefillBytes: null),
              onRegisterCamera: () =>
                  _openAddPersonDialog(context, withCamera: true, prefillBytes: null),
            ),
            const SizedBox(height: 16),
          ],

          // ── Error state ──────────────────────────────────────────────────────
          if (controller.voiceError != null &&
              controller.voiceError!.startsWith('Camera')) ...[
            AppCard(
              child: ErrorState(
                message: controller.voiceError!,
                onRetry: () => controller.recognizeFace(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Management buttons ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openManageFaces(context),
                  icon: const Icon(Icons.people_outlined),
                  label: const Text('Manage Known Faces'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openAddPersonDialog(context, withCamera: false, prefillBytes: null),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add Person'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Tips ─────────────────────────────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                    title: 'Tips', icon: Icons.lightbulb_outline),
                const SizedBox(height: 8),
                _Tip(text: 'Ensure the face is well-lit and clearly visible.'),
                _Tip(text: 'Look directly at the camera for best results.'),
                _Tip(
                    text:
                        'If a person is not recognized, register their face.'),
                _Tip(
                    text:
                        'On desktop, the PC webcam is used via the assistant server.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openScanDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LiveScanDialog(controller: controller),
    );
  }

  void _openAddPersonDialog(
    BuildContext context, {
    required bool withCamera,
    required List<int>? prefillBytes,
    String? personId,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddPersonDialog(
        controller: controller,
        startWithCamera: withCamera,
        prefillBytes: prefillBytes,
        existingPersonId: personId,
      ),
    );
  }

  void _openManageFaces(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManageFacesPage(controller: controller),
      ),
    );
  }
}

// =============================================================================
// Small utility widgets
// =============================================================================

class _Tip extends StatelessWidget {
  const _Tip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle,
              size: 6, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _LastResultCard extends StatelessWidget {
  const _LastResultCard({required this.result});

  final FaceRecognitionResult result;

  @override
  Widget build(BuildContext context) {
    final recognized = result.recognized;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Last Recognition Result',
            icon: Icons.assignment_turned_in_outlined,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: recognized
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  recognized ? Icons.check_rounded : Icons.close_rounded,
                  color: recognized
                      ? const Color(0xFF047857)
                      : const Color(0xFFB91C1C),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recognized ? result.personName : 'Unknown Person',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (recognized && result.relationship.isNotEmpty)
                      Text(result.relationship,
                          style: Theme.of(context).textTheme.bodySmall),
                    if (recognized && result.notes.isNotEmpty)
                      Text(result.notes,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    if (result.score > 0)
                      Text(
                        'Confidence: ${(result.score * 100).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              StatusBadge(
                label: recognized ? 'Recognized' : 'Unknown',
                tone: recognized ? StatusTone.ready : StatusTone.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnknownPersonBanner extends StatelessWidget {
  const _UnknownPersonBanner({
    required this.controller,
    required this.onAddPicture,
    required this.onRegisterCamera,
  });

  final AssistantController controller;
  final VoidCallback onAddPicture;
  final VoidCallback onRegisterCamera;

  @override
  Widget build(BuildContext context) {
    final warnColor = Theme.of(context).colorScheme.errorContainer;
    return Card(
      color: warnColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text('Unknown person detected',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                            color: Theme.of(context).colorScheme.onErrorContainer)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Would you like to add this person to known faces?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onAddPicture,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Add Using Picture'),
                ),
                FilledButton.icon(
                  onPressed: onRegisterCamera,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Register Using Camera'),
                ),
                OutlinedButton(
                  onPressed: controller.acknowledgeUnknownFace,
                  child: const Text('Not Now'),
                ),
                OutlinedButton(
                  onPressed: controller.ignoreUnknownFace,
                  child: const Text('Ignore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section B: Live Scan Dialog — with continuously visible camera preview
// =============================================================================

enum _ScanPhase { idle, scanning, matching, done, failed }

class _LiveScanDialog extends StatefulWidget {
  const _LiveScanDialog({required this.controller});

  final AssistantController controller;

  @override
  State<_LiveScanDialog> createState() => _LiveScanDialogState();
}

class _LiveScanDialogState extends State<_LiveScanDialog> {
  _ScanPhase _phase = _ScanPhase.idle;
  String _statusMessage = 'Position the face in the oval and tap Scan.';
  FaceRecognitionResult? _result;
  String? _errorMessage;
  bool _cancelled = false;

  // Adaptive multi-frame scanning state
  final List<Uint8List> _samples = [];
  Timer? _captureTimer;
  int _elapsed = 0; // seconds since scan started
  static const _maxScanSeconds = 15;
  static const _targetSamples = 5;

  // Key to access CaptureHelper from the live preview widget
  final GlobalKey<_LivePreviewWithCaptureState> _previewKey =
      GlobalKey<_LivePreviewWithCaptureState>();

  @override
  void dispose() {
    _cancelled = true;
    _captureTimer?.cancel();
    super.dispose();
  }

  // ---------- Adaptive scan ----------

  void _startScan() {
    if (_phase == _ScanPhase.scanning) return;
    setState(() {
      _phase = _ScanPhase.scanning;
      _statusMessage = 'Looking for a face…';
      _samples.clear();
      _elapsed = 0;
      _errorMessage = null;
      _result = null;
    });

    // Capture a frame every 2 seconds; stop after _targetSamples or _maxScanSeconds
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_cancelled || !mounted) return;

      _elapsed += 2;

      if (_samples.length >= _targetSamples || _elapsed >= _maxScanSeconds) {
        _captureTimer?.cancel();
        await _runMatch();
        return;
      }

      setState(() => _statusMessage =
          'Collecting samples… (${_samples.length}/$_targetSamples)');

      final jpeg = await _previewKey.currentState?.capture();
      if (jpeg != null && jpeg.isNotEmpty) {
        _samples.add(jpeg);
        setState(() => _statusMessage =
            'Sample ${_samples.length}/$_targetSamples captured – hold still…');
      }
    });
  }

  Future<void> _runMatch() async {
    if (_cancelled || !mounted) return;
    if (_samples.isEmpty) {
      setState(() {
        _phase = _ScanPhase.failed;
        _errorMessage =
            'Could not capture any frames. Check camera access and try again.';
      });
      return;
    }

    setState(() {
      _phase = _ScanPhase.matching;
      _statusMessage = 'Matching identity…';
    });

    try {
      // Send all samples; use best-confidence result
      FaceRecognitionResult? best;
      for (final jpeg in _samples) {
        if (_cancelled || !mounted) break;
        try {
          final r =
              await widget.controller.api.recognizeFace(jpeg.toList());
          if (best == null || r.score > best.score) best = r;
          if (best.recognized && best.score >= 0.85) break; // early exit
        } catch (_) {
          continue;
        }
      }

      if (_cancelled || !mounted) return;
      if (best == null) throw Exception('All recognition attempts failed.');
      widget.controller.lastRecognitionResult = best;

      if (mounted) {
        setState(() {
          _phase = _ScanPhase.done;
          _result = best;
          _statusMessage =
              best!.recognized ? 'Identified!' : 'No match found.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _ScanPhase.failed;
          _errorMessage = 'Recognition error: $e';
        });
      }
    }
  }

  void _reset() {
    _captureTimer?.cancel();
    setState(() {
      _phase = _ScanPhase.idle;
      _statusMessage = 'Position the face in the oval and tap Scan.';
      _samples.clear();
      _elapsed = 0;
      _result = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTall = MediaQuery.of(context).size.height > 600;
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Scan Face',
              style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              _cancelled = true;
              _captureTimer?.cancel();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── Live camera feed with oval overlay ──────────────────────
              Expanded(
                child: _LivePreviewWithCapture(
                  key: _previewKey,
                  apiBase: widget.controller.apiBase,
                  phase: _phase,
                ),
              ),

              // ── Status & controls ───────────────────────────────────────
              Container(
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Phase progress bar
                    if (_phase == _ScanPhase.scanning ||
                        _phase == _ScanPhase.matching)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(
                          value: _phase == _ScanPhase.scanning
                              ? _samples.length / _targetSamples
                              : null,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      ),

                    // Status message
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),

                    if (_phase == _ScanPhase.scanning && isTall)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$_elapsed s / $_maxScanSeconds s max',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ),

                    // Error
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                              color: Colors.red[300], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Result chip
                    if (_result != null && _phase == _ScanPhase.done)
                      _InlineScanResult(result: _result!),

                    const SizedBox(height: 12),

                    // Action buttons
                    _ScanActions(
                      phase: _phase,
                      result: _result,
                      controller: widget.controller,
                      onScan: _startScan,
                      onReset: _reset,
                      onDone: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LivePreviewWithCapture – wraps CameraLivePreview + oval guide + capture
// ---------------------------------------------------------------------------

class _LivePreviewWithCapture extends StatefulWidget {
  const _LivePreviewWithCapture({
    super.key,
    required this.apiBase,
    required this.phase,
  });

  final String apiBase;
  final _ScanPhase phase;

  @override
  State<_LivePreviewWithCapture> createState() =>
      _LivePreviewWithCaptureState();
}

class _LivePreviewWithCaptureState extends State<_LivePreviewWithCapture> {
  Uint8List? _lastFrame;

  /// Called by the parent scan dialog to grab a JPEG frame for recognition.
  Future<Uint8List?> capture() async => _lastFrame;

  @override
  Widget build(BuildContext context) {
    final ovalColor = switch (widget.phase) {
      _ScanPhase.done => Colors.green,
      _ScanPhase.failed => Colors.red,
      _ScanPhase.scanning => Theme.of(context).colorScheme.primary,
      _ScanPhase.matching => Colors.orange,
      _ScanPhase.idle => Colors.white54,
    };

    return CameraLivePreview(
      apiBase: widget.apiBase,
      onFrameAvailable: (jpeg) => _lastFrame = jpeg,
      overlayWidget: IgnorePointer(
        child: CustomPaint(
          painter: _OvalGuidePainter(color: ovalColor),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OvalGuidePainter – transparent oval cutout over the camera feed
// ---------------------------------------------------------------------------

class _OvalGuidePainter extends CustomPainter {
  const _OvalGuidePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final ovalW = size.width * 0.62;
    final ovalH = size.height * 0.72;

    // Dim the area outside the oval
    final dimPaint = Paint()..color = Colors.black54;
    final ovalRect = Rect.fromCenter(
        center: Offset(cx, cy), width: ovalW, height: ovalH);
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), dimPaint);
    canvas.drawOval(ovalRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Oval border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(ovalRect, borderPaint);

    // Corner label
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Centre your face',
        style: TextStyle(color: color, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, cy + ovalH / 2 + 10),
    );
  }

  @override
  bool shouldRepaint(_OvalGuidePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Inline result shown inside the scan dialog
// ---------------------------------------------------------------------------

class _InlineScanResult extends StatelessWidget {
  const _InlineScanResult({required this.result});

  final FaceRecognitionResult result;

  @override
  Widget build(BuildContext context) {
    final recognized = result.recognized;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: recognized
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: recognized ? Colors.green : Colors.orange, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            recognized ? result.personName : 'Unknown Person',
            style: TextStyle(
              color: recognized ? Colors.green[300] : Colors.orange[300],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (recognized && result.relationship.isNotEmpty)
            Text(result.relationship,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
          if (recognized && result.notes.isNotEmpty)
            Text(result.notes,
                style:
                    const TextStyle(color: Colors.white60, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          if (result.score > 0)
            Text(
              'Confidence: ${(result.score * 100).toStringAsFixed(1)}%',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan action buttons
// ---------------------------------------------------------------------------

class _ScanActions extends StatelessWidget {
  const _ScanActions({
    required this.phase,
    required this.result,
    required this.controller,
    required this.onScan,
    required this.onReset,
    required this.onDone,
  });

  final _ScanPhase phase;
  final FaceRecognitionResult? result;
  final AssistantController controller;
  final VoidCallback onScan;
  final VoidCallback onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    if (phase == _ScanPhase.scanning || phase == _ScanPhase.matching) {
      return const SizedBox.shrink();
    }

    if (phase == _ScanPhase.done && result != null) {
      return Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (!result!.recognized)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showDialog<void>(
                  context: context,
                  builder: (_) => _AddPersonDialog(
                    controller: controller,
                    startWithCamera: false,
                    prefillBytes: null,
                    existingPersonId: null,
                  ),
                );
              },
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Register Person'),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: onReset,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      );
    }

    // idle or failed
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onScan,
        icon: const Icon(Icons.radar),
        label: const Text('Start Scan  (5–15 s)'),
      ),
    );
  }
}

// =============================================================================
// Section C: Add Person Dialog
// =============================================================================

class _AddPersonDialog extends StatefulWidget {
  const _AddPersonDialog({
    required this.controller,
    required this.startWithCamera,
    required this.prefillBytes,
    required this.existingPersonId,
  });

  final AssistantController controller;
  final bool startWithCamera;
  final List<int>? prefillBytes;
  final String? existingPersonId;

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final _nameCtrl = TextEditingController();
  final _relCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _pc = PcCamera();

  List<int>? _photoBytes;
  bool _saving = false;
  String? _error;
  String? _successMessage;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.startWithCamera) _tabs.index = 1;
    if (widget.prefillBytes != null) {
      _photoBytes = widget.prefillBytes;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _relCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      setState(() {
        _photoBytes = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open gallery: $e');
    }
  }

  Future<void> _captureFromCamera() async {
    try {
      if (_isDesktop) {
        final file = await _pc.captureJpeg();
        final bytes = await file.readAsBytes();
        setState(() {
          _photoBytes = bytes;
          _error = null;
        });
      } else {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1280,
        );
        if (picked == null) return;
        final bytes = await File(picked.path).readAsBytes();
        setState(() {
          _photoBytes = bytes;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    if (_photoBytes == null) {
      setState(() => _error = 'Please provide a photo first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.api.registerFace(
        imageBytes: _photoBytes!,
        name: name,
        personId: widget.existingPersonId ?? '',
        relationship: _relCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _successMessage = '$name has been registered.';
        });
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Registration failed: $e';
        });
      }
    }
  }

  Future<void> _createOnly() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.createPerson(
        name: name,
        relationship: _relCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _successMessage = '$name has been added.';
        });
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not create person: $e';
        });
      }
    }
  }

  Widget _buildForm(BuildContext context, {required bool showPhotoSection}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPhotoSection) ...[
            // Photo picker
            Center(
              child: GestureDetector(
                onTap: _tabs.index == 0 ? _pickFromGallery : _captureFromCamera,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(70),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2),
                  ),
                  child: _photoBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(70),
                          child: Image.memory(
                            Uint8List.fromList(_photoBytes!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 36,
                                color:
                                    Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 6),
                            Text(
                              _tabs.index == 0
                                  ? 'Pick from gallery'
                                  : _isDesktop
                                      ? 'Capture photo'
                                      : 'Take photo',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed:
                    _tabs.index == 0 ? _pickFromGallery : _captureFromCamera,
                icon: Icon(
                  _tabs.index == 0
                      ? Icons.photo_library_outlined
                      : Icons.camera_alt_outlined,
                  size: 18,
                ),
                label: Text(_tabs.index == 0
                    ? 'Choose Photo'
                    : _isDesktop
                        ? 'Capture from Webcam'
                        : 'Take Photo'),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Form fields
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _relCtrl,
            decoration: const InputDecoration(
              labelText: 'Relationship / Role',
              hintText: 'e.g. Son, Nurse, Neighbour',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (_successMessage != null) ...[
            Text(_successMessage!,
                style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 8),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving
                  ? null
                  : showPhotoSection
                      ? _register
                      : _createOnly,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(showPhotoSection
                      ? Icons.save_outlined
                      : Icons.person_add_outlined),
              label: Text(showPhotoSection ? 'Register' : 'Add Person'),
            ),
          ),
          if (showPhotoSection) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _saving ? null : _createOnly,
                child: const Text('Add without face photo'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Person'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Gallery'),
              Tab(icon: Icon(Icons.camera_alt_outlined), text: 'Camera'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _buildForm(context, showPhotoSection: true),
            _buildForm(context, showPhotoSection: true),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section D: Manage Faces Page
// =============================================================================

class _ManageFacesPage extends StatefulWidget {
  const _ManageFacesPage({required this.controller});

  final AssistantController controller;

  @override
  State<_ManageFacesPage> createState() => _ManageFacesPageState();
}

class _ManageFacesPageState extends State<_ManageFacesPage> {
  List<KnownPerson>? _people;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await widget.controller.api.listPeople();
      if (mounted) setState(() { _people = people; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _confirmDelete(KnownPerson person) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Person'),
        content: Text(
            'Are you sure you want to permanently delete ${person.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.deletePerson(person.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _removeFace(KnownPerson person) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Face Photo'),
        content: Text(
            'Remove the face profile for ${person.name}? The person record will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.deletePersonFace(person.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Remove face failed: $e');
    }
  }

  void _editPerson(KnownPerson person) {
    showDialog<void>(
      context: context,
      builder: (_) => _EditPersonDialog(
        controller: widget.controller,
        person: person,
        onSaved: _load,
      ),
    );
  }

  void _addFace(KnownPerson person) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddPersonDialog(
        controller: widget.controller,
        startWithCamera: false,
        prefillBytes: null,
        existingPersonId: person.id,
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Known Faces'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (_) => _AddPersonDialog(
              controller: widget.controller,
              startWithCamera: false,
              prefillBytes: null,
              existingPersonId: null,
            ),
          ).then((_) => _load());
        },
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add New Person'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorState(
                        message: _error!, onRetry: _load),
                  ),
                )
              : _people == null || _people!.isEmpty
                  ? const Center(
                      child: EmptyState(
                        title: 'No people registered',
                        message:
                            'Tap the button below to add a new person.',
                        icon: Icons.people_outline,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: _people!.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final person = _people![i];
                          return _PersonTile(
                            person: person,
                            onEdit: () => _editPerson(person),
                            onDelete: () => _confirmDelete(person),
                            onRemoveFace: () => _removeFace(person),
                            onAddFace: () => _addFace(person),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.onEdit,
    required this.onDelete,
    required this.onRemoveFace,
    required this.onAddFace,
  });

  final KnownPerson person;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRemoveFace;
  final VoidCallback onAddFace;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              person.name.isNotEmpty
                  ? person.name[0].toUpperCase()
                  : '?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(person.relationship,
                    style: Theme.of(context).textTheme.bodySmall),
                if (person.notes.isNotEmpty)
                  Text(
                    person.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                StatusBadge(
                  label: person.hasFaceProfile
                      ? 'Face registered'
                      : 'No face',
                  tone: person.hasFaceProfile
                      ? StatusTone.ready
                      : StatusTone.neutral,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'add_face':
                  onAddFace();
                case 'remove_face':
                  onRemoveFace();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!person.hasFaceProfile)
                const PopupMenuItem(
                  value: 'add_face',
                  child: ListTile(
                    leading: Icon(Icons.add_a_photo_outlined),
                    title: Text('Add face photo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (person.hasFaceProfile)
                const PopupMenuItem(
                  value: 'add_face',
                  child: ListTile(
                    leading: Icon(Icons.refresh_outlined),
                    title: Text('Replace face photo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (person.hasFaceProfile)
                const PopupMenuItem(
                  value: 'remove_face',
                  child: ListTile(
                    leading: Icon(Icons.no_photography_outlined),
                    title: Text('Remove face only'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outlined, color: Colors.red),
                  title: Text('Delete person',
                      style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Edit Person Dialog
// =============================================================================

class _EditPersonDialog extends StatefulWidget {
  const _EditPersonDialog({
    required this.controller,
    required this.person,
    required this.onSaved,
  });

  final AssistantController controller;
  final KnownPerson person;
  final VoidCallback onSaved;

  @override
  State<_EditPersonDialog> createState() => _EditPersonDialogState();
}

class _EditPersonDialogState extends State<_EditPersonDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _relCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.person.name);
    _relCtrl = TextEditingController(text: widget.person.relationship);
    _notesCtrl = TextEditingController(text: widget.person.notes);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _relCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updatePerson(
        id: widget.person.id,
        name: name,
        relationship: _relCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Update failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Person'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _relCtrl,
              decoration: const InputDecoration(
                  labelText: 'Relationship',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
