import 'dart:async';

import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../theme/app_colors.dart';
import '../vision/face_capture.dart';
import '../widgets/app_widgets.dart';
import 'add_reminder_sheet.dart';

// ---------------------------------------------------------------------------
// Dashboard Screen
// ---------------------------------------------------------------------------

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final compact = w < 600;
            final twoCol = w >= 1100;
            final pad = EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 28);

            Widget buildContent() {
              final header = _HeaderCard(controller: controller, compact: compact);
              final status = _AssistantStatusCard(controller: controller);
              final voice = _VoiceCard(controller: controller, onOpen: () => onNavigate(1));
              final actions = _QuickActionsCard(
                onNavigate: onNavigate,
                onAddReminder: () => showAddReminderSheet(context, controller),
              );
              final reminders = _RemindersCard(
                controller: controller,
                onOpen: () => onNavigate(2),
                onAdd: () => showAddReminderSheet(context, controller),
              );
              final memory = _MemoryCard(controller: controller, onOpen: () => onNavigate(3));
              final camera = _CameraCard(controller: controller, onOpen: () => onNavigate(4));
              final activity = _ActivityCard(controller: controller);

              if (twoCol) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          header,
                          const SizedBox(height: 16),
                          voice,
                          const SizedBox(height: 16),
                          actions,
                          const SizedBox(height: 16),
                          activity,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          status,
                          const SizedBox(height: 16),
                          reminders,
                          const SizedBox(height: 16),
                          memory,
                          const SizedBox(height: 16),
                          camera,
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Single column
              return Column(
                children: [
                  header,
                  const SizedBox(height: 16),
                  status,
                  const SizedBox(height: 16),
                  voice,
                  const SizedBox(height: 16),
                  actions,
                  const SizedBox(height: 16),
                  reminders,
                  const SizedBox(height: 16),
                  memory,
                  const SizedBox(height: 16),
                  camera,
                  const SizedBox(height: 16),
                  activity,
                ],
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: pad,
                child: buildContent(),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header: greeting, clock, patient name
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.controller, required this.compact});

  final AssistantController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final name = controller.patientName;
    final greeting = controller.overview?.greeting ?? _localGreeting();
    final title = name.isEmpty ? greeting : '$greeting, $name';
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                      _settingsButton(context),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _LiveClockWidget(dark: false),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 10),
                        const _LiveClockWidget(dark: false),
                      ],
                    ),
                  ),
                  _settingsButton(context),
                ],
              ),
      ),
    );
  }

  Widget _settingsButton(BuildContext context) {
    return IconButton(
      onPressed: () => controller.selectNav(5),
      icon: const Icon(Icons.settings_outlined, color: Colors.white),
      tooltip: 'Settings',
    );
  }

  String _localGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ---------------------------------------------------------------------------
// Live clock widget (shows H:MM:SS and full date)
// ---------------------------------------------------------------------------

class _LiveClockWidget extends StatefulWidget {
  const _LiveClockWidget({this.dark = true});

  final bool dark;

  @override
  State<_LiveClockWidget> createState() => _LiveClockWidgetState();
}

class _LiveClockWidgetState extends State<_LiveClockWidget> {
  late DateTime _now;
  // Use a plain periodic Timer so Flutter test's fake-async can drain it cleanly.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(_now);
    final dateStr = _formatDate(_now);
    final textColor = widget.dark ? Theme.of(context).colorScheme.onSurface : Colors.white;
    final mutedColor = widget.dark ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          dateStr,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: mutedColor),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m:$s $period';
  }

  String _formatDate(DateTime dt) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Assistant status card
// ---------------------------------------------------------------------------

class _AssistantStatusCard extends StatelessWidget {
  const _AssistantStatusCard({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final link = controller.link;
    final online = link == AssistantLink.ready;
    final degraded = link == AssistantLink.degraded;
    final statusColor = online
        ? AppColors.success
        : degraded
            ? AppColors.warning
            : AppColors.danger;
    final statusLabel = online
        ? 'Assistant Online'
        : degraded
            ? 'Limited Mode'
            : link == AssistantLink.initializing
                ? 'Connecting…'
                : 'Assistant Offline';
    final patientName = controller.patientName;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.support_agent_outlined, color: Theme.of(context).colorScheme.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName.isEmpty ? 'Patient Profile' : patientName, style: Theme.of(context).textTheme.titleMedium),
                if (controller.overview?.caregiverName.isNotEmpty == true)
                  Text('Care team: ${controller.overview!.caregiverName}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
              if (controller.loadError != null)
                Text(
                  'Check settings',
                  style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voice Assistant card
// ---------------------------------------------------------------------------

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({required this.controller, required this.onOpen});

  final AssistantController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final phase = controller.voicePhase;
    final listening = phase == VoicePhase.listening;
    final processing = phase == VoicePhase.processing || phase == VoicePhase.speaking;

    return AppCard(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.mic_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Voice Assistant', style: Theme.of(context).textTheme.titleLarge)),
              TextButton(onPressed: onOpen, child: const Text('Full screen')),
            ],
          ),
          const SizedBox(height: 16),
          // Mic button + status row
          Row(
            children: [
              _MicButtonCompact(
                phase: phase,
                enabled: !(controller.busy && !controller.listening),
                onPressed: controller.onTalkPressed,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PhaseIndicator(phase: phase),
                    const SizedBox(height: 6),
                    Text(
                      controller.statusText,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (listening)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ListeningWave(),
                      ),
                    if (processing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (controller.lastHeard != null && controller.lastHeard!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            _ConversationSnippet(
              label: 'You said',
              text: controller.lastHeard!,
              fromYou: true,
            ),
          ],
          if (controller.lastReply != null && controller.lastReply!.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ConversationSnippet(
              label: 'Assistant replied',
              text: controller.lastReply!,
              fromYou: false,
            ),
          ],
          if (controller.blockedAudio != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: controller.playBlockedAudio,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play reply'),
            ),
          ],
          if (controller.voiceError != null) ...[
            const SizedBox(height: 8),
            ErrorState(message: controller.voiceError!, onRetry: controller.onTalkPressed),
          ],
        ],
      ),
    );
  }
}

class _MicButtonCompact extends StatelessWidget {
  const _MicButtonCompact({required this.phase, required this.onPressed, this.enabled = true});

  final VoicePhase phase;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final listening = phase == VoicePhase.listening;
    final processing = phase == VoicePhase.processing || phase == VoicePhase.speaking;
    final bgColor = listening ? AppColors.mute : AppColors.talk;

    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start talking to assistant',
      child: SizedBox(
        width: 80,
        height: 80,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: bgColor.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            elevation: 6,
            padding: EdgeInsets.zero,
          ),
          child: processing
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: 32),
        ),
      ),
    );
  }
}

class _PhaseIndicator extends StatelessWidget {
  const _PhaseIndicator({required this.phase});

  final VoicePhase phase;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (phase) {
      VoicePhase.idle => (AppColors.success, 'Ready'),
      VoicePhase.listening => (AppColors.mute, 'Listening'),
      VoicePhase.processing => (AppColors.blue, 'Processing'),
      VoicePhase.speaking => (AppColors.teal, 'Speaking'),
      VoicePhase.error => (AppColors.danger, 'Error'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class _ListeningWave extends StatefulWidget {
  @override
  State<_ListeningWave> createState() => _ListeningWaveState();
}

class _ListeningWaveState extends State<_ListeningWave> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              Container(
                width: 4,
                height: 8 + (16 * (0.4 + 0.6 * (((_anim.value + i * 0.2) % 1.0))).abs()),
                decoration: BoxDecoration(
                  color: AppColors.mute.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (i < 4) const SizedBox(width: 4),
            ],
          ],
        );
      },
    );
  }
}

class _ConversationSnippet extends StatelessWidget {
  const _ConversationSnippet({required this.label, required this.text, required this.fromYou});

  final String label;
  final String text;
  final bool fromYou;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromYou ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fromYou ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(text, style: Theme.of(context).textTheme.bodyMedium, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Actions
// ---------------------------------------------------------------------------

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.onNavigate, required this.onAddReminder});

  final void Function(int) onNavigate;
  final VoidCallback onAddReminder;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.mic_rounded, 'Talk', Colors.teal, () => onNavigate(1)),
      (Icons.add_alert_outlined, 'Reminder', Colors.indigo, onAddReminder),
      (Icons.auto_stories_rounded, 'Memory', Colors.purple, () => onNavigate(3)),
      (Icons.event_rounded, 'Schedule', Colors.blue, () => onNavigate(2)),
      (Icons.face_outlined, 'Faces', Colors.orange, () => onNavigate(4)),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Quick Actions', icon: Icons.flash_on_outlined),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 360 ? 2 : (constraints.maxWidth < 560 ? 3 : 5);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.1,
                ),
                itemCount: actions.length,
                itemBuilder: (context, i) {
                  final (icon, label, color, onTap) = actions[i];
                  return _ActionTile(icon: icon, label: label, color: color, onTap: onTap);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reminders card
// ---------------------------------------------------------------------------

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.controller, required this.onOpen, required this.onAdd});

  final AssistantController controller;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final reminders = controller.overview?.reminders ?? const <ReminderItem>[];
    final upcoming = reminders.where((r) => r.status == 'pending').take(3).toList();
    final active = controller.overview?.activeReminder;
    final nextAppt = controller.overview?.nextAppointment;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Reminders & Medications',
            icon: Icons.alarm_outlined,
            actionLabel: 'View all',
            onAction: onOpen,
          ),
          if (active != null) ...[
            const SizedBox(height: 8),
            StatusBadge(
              label: 'Due now: ${active.title}',
              tone: StatusTone.warning,
              icon: Icons.notification_important_outlined,
            ),
          ],
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            const EmptyState(
              title: 'No upcoming reminders',
              message: 'Add a reminder to get started.',
              icon: Icons.alarm_off_outlined,
            )
          else
            ...upcoming.map((item) => ReminderTile(
                  item: item,
                  onComplete: item.id.isNotEmpty ? () => controller.completeReminder(item.id) : null,
                )),
          if (nextAppt != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.local_hospital_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next Appointment', style: Theme.of(context).textTheme.bodySmall),
                      Text('${nextAppt.doctor} · ${nextAppt.date} · ${nextAppt.time}',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Reminder')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Memory card
// ---------------------------------------------------------------------------

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.controller, required this.onOpen});

  final AssistantController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final data = controller.overview;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Memory Assistance', icon: Icons.auto_stories_outlined, actionLabel: 'Open', onAction: onOpen),
          const SizedBox(height: 8),
          if (data == null)
            const EmptyState(
              title: 'Memory not loaded',
              message: 'Connect to the assistant to see stored people, dates, and preferences.',
            )
          else if (data.family.isEmpty && data.importantDates.isEmpty && data.preferences.isEmpty)
            const EmptyState(
              title: 'No memories stored',
              message: 'The assistant will remember important people and dates as you use it.',
            )
          else ...[
            if (data.family.isNotEmpty) ...[
              _MemorySection(
                icon: Icons.people_outlined,
                label: 'Familiar People',
                children: data.family
                    .map((p) => _MemoryChip(label: '${p.name} (${p.relationship})'))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (data.importantDates.isNotEmpty) ...[
              _MemorySection(
                icon: Icons.calendar_today_outlined,
                label: 'Important Dates',
                children: data.importantDates
                    .map((d) => _MemoryChip(label: '${d.title}: ${d.date}'))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (data.preferences.isNotEmpty)
              _MemorySection(
                icon: Icons.favorite_border,
                label: 'Preferences',
                children: data.preferences
                    .take(3)
                    .map((p) => _MemoryChip(label: '${p.key}: ${p.value}'))
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }
}

class _MemorySection extends StatelessWidget {
  const _MemorySection({required this.icon, required this.label, required this.children});

  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: children),
      ],
    );
  }
}

class _MemoryChip extends StatelessWidget {
  const _MemoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera card
// ---------------------------------------------------------------------------

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.controller, required this.onOpen});

  final AssistantController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final camera = controller.camera;
    final (tone, label) = switch (camera.availability) {
      CameraAvailability.available => (StatusTone.ready, 'Camera Available'),
      CameraAvailability.permissionRequired => (StatusTone.warning, 'Permission Required'),
      CameraAvailability.unknown => (StatusTone.neutral, 'Status Unknown'),
      CameraAvailability.unavailable => (StatusTone.warning, 'Camera Unavailable'),
      CameraAvailability.error => (StatusTone.danger, 'Camera Error'),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Camera & Face Recognition', icon: Icons.face_outlined, actionLabel: 'Open', onAction: onOpen),
          const SizedBox(height: 8),
          StatusBadge(label: label, tone: tone),
          const SizedBox(height: 8),
          Text(
            camera.detail.isEmpty ? 'No status available yet.' : camera.detail,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (controller.lastFace != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  controller.lastFace!.recognized ? Icons.check_circle_outline : Icons.help_outline,
                  color: controller.lastFace!.recognized ? AppColors.success : AppColors.muted,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    controller.lastFace!.recognized
                        ? 'Recognized: ${controller.lastFace!.personName}'
                        : 'Person not recognized',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity card
// ---------------------------------------------------------------------------

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.overview?.activity ?? const <ActivityItem>[];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Recent Activity', icon: Icons.history),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const EmptyState(
              title: 'No recent activity',
              message: 'Voice, reminder, and recognition events will appear here.',
            )
          else
            ...items.take(5).map((item) => ActivityTile(item: item)),
        ],
      ),
    );
  }
}
