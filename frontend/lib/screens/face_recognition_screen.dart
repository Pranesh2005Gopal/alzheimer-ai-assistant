import 'package:flutter/material.dart';

import '../api/assistant_api.dart';
import '../state/assistant_controller.dart';
import '../vision/face_capture.dart';
import '../widgets/app_widgets.dart';

class FaceRecognitionScreen extends StatelessWidget {
  const FaceRecognitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final camera = controller.camera;
        final (tone, statusLabel) = switch (camera.availability) {
          CameraAvailability.available => (StatusTone.ready, 'Camera Available'),
          CameraAvailability.permissionRequired => (StatusTone.warning, 'Permission Required'),
          CameraAvailability.unknown => (StatusTone.neutral, 'Status Unknown'),
          CameraAvailability.unavailable => (StatusTone.warning, 'Camera Unavailable'),
          CameraAvailability.error => (StatusTone.danger, 'Camera Error'),
        };

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              // Header card
              AppCard(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.face_outlined, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Face Recognition', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Point the camera at a person and the assistant will try to identify them.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Camera status
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Camera Status', icon: Icons.camera_outlined),
                    const SizedBox(height: 10),
                    StatusBadge(label: statusLabel, tone: tone),
                    if (camera.detail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(camera.detail, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    if (camera.lastError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Error: ${camera.lastError}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Recognize action
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Recognize a Face', icon: Icons.face_retouching_natural_outlined),
                    const SizedBox(height: 8),
                    Text(
                      'Take a photo to identify who is in front of the camera.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: controller.busy ? null : () => controller.recognizeFace(offerRegister: true),
                            icon: controller.busy && controller.statusText.contains('camera')
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.camera_alt_outlined),
                            label: const Text('Identify Person'),
                          ),
                        ),
                      ],
                    ),
                    if (controller.busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(controller.statusText, style: Theme.of(context).textTheme.bodyMedium),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Last result
              if (controller.lastFace != null) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Recognition Result', icon: Icons.assignment_turned_in_outlined),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: controller.lastFace!.recognized
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              controller.lastFace!.recognized ? Icons.check_rounded : Icons.close_rounded,
                              color: controller.lastFace!.recognized ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.lastFace!.recognized
                                      ? controller.lastFace!.personName
                                      : 'Person not recognized',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(controller.lastFace!.message, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Register pending face
              if (controller.pendingRegisterPhoto != null) ...[
                _RegisterFaceCard(controller: controller),
                const SizedBox(height: 16),
              ],

              // Error state
              if (controller.voiceError != null && controller.voiceError!.startsWith('Camera')) ...[
                AppCard(child: ErrorState(message: controller.voiceError!, onRetry: () => controller.recognizeFace())),
                const SizedBox(height: 16),
              ],

              // Tips card
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Tips', icon: Icons.lightbulb_outline),
                    const SizedBox(height: 8),
                    _Tip(text: 'Ensure the face is well-lit and clearly visible.'),
                    _Tip(text: 'Look directly at the camera for best results.'),
                    _Tip(text: 'If a person is not recognized, you can register their face.'),
                    _Tip(text: 'On desktop, the PC camera is used via the assistant server.'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
          Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _RegisterFaceCard extends StatefulWidget {
  const _RegisterFaceCard({required this.controller});

  final AssistantController controller;

  @override
  State<_RegisterFaceCard> createState() => _RegisterFaceCardState();
}

class _RegisterFaceCardState extends State<_RegisterFaceCard> {
  List<KnownPerson>? _people;
  bool _loading = true;
  KnownPerson? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await widget.controller.peopleForRegistration();
      if (mounted) setState(() { _people = people; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final person = _selected;
    if (person == null) return;
    setState(() => _saving = true);
    try {
      await widget.controller.registerPendingFace(person);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Register this Face', icon: Icons.person_add_alt_1_outlined),
          const SizedBox(height: 8),
          Text('The person in the photo was not recognized. You can register them now.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (_loading)
            const CircularProgressIndicator()
          else if (_people == null || _people!.isEmpty)
            Text('No known people to associate. Add people via the assistant.', style: Theme.of(context).textTheme.bodyMedium)
          else ...[
            DropdownButtonFormField<KnownPerson>(
              initialValue: _selected,
              hint: const Text('Select a person'),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _people!.map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (${p.relationship})'))).toList(),
              onChanged: (v) => setState(() => _selected = v),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving || _selected == null ? null : _register,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('Register Face'),
            ),
          ],
        ],
      ),
    );
  }
}
