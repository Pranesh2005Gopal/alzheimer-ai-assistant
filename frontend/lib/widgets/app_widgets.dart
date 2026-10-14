import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../theme/app_colors.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? Theme.of(context).colorScheme.surface;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      StatusTone.ready => (AppColors.success, const Color(0xFFD1FAE5)),
      StatusTone.info => (AppColors.blue, const Color(0xFFDBEAFE)),
      StatusTone.warning => (AppColors.warning, const Color(0xFFFEF3C7)),
      StatusTone.danger => (AppColors.danger, const Color(0xFFFEE2E2)),
      StatusTone.neutral => (AppColors.muted, const Color(0xFFE2E8F0)),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.$2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.circle, size: 12, color: colors.$1),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: colors.$1, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusTone { ready, info, warning, danger, neutral }

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.icon = Icons.inbox_outlined});

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.danger)),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ],
      ],
    );
  }
}

class LiveClock extends StatefulWidget {
  const LiveClock({super.key, this.compact = false});

  final bool compact;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late DateTime _now;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final next = DateTime.now();
    if (next.second != _now.second) {
      setState(() => _now = next);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = _clock(_now);
    final date = _fullDate(_now);
    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          Text(date, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Text(date, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

String _clock(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _fullDate(DateTime value) {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${days[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}

class Ticker {
  Ticker(this.onTick);
  final void Function(Duration) onTick;
  bool _active = false;
  DateTime? _started;

  void start() {
    _active = true;
    _started = DateTime.now();
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!_active) {
        return false;
      }
      onTick(DateTime.now().difference(_started!));
      return _active;
    });
  }

  void dispose() {
    _active = false;
  }
}

class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.phase,
    required this.onPressed,
    this.enabled = true,
  });

  final VoicePhase phase;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final listening = phase == VoicePhase.listening;
    final processing = phase == VoicePhase.processing || phase == VoicePhase.speaking;
    final label = listening
        ? 'Stop'
        : processing
            ? 'Wait'
            : 'Talk';
    final color = listening ? AppColors.mute : AppColors.talk;
    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start talking to the assistant',
      child: SizedBox(
        width: 148,
        height: 148,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            elevation: 8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: 42),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.item, this.onComplete});

  final ReminderItem item;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(_iconFor(item.kind), color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(item.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('${item.kindLabel} · ${item.time} · ${item.status}'),
      trailing: item.status == 'pending' && onComplete != null
          ? TextButton(onPressed: onComplete, child: const Text('Done'))
          : StatusBadge(label: item.status, tone: _toneFor(item.status)),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'medication':
        return Icons.medication_outlined;
      case 'appointment':
        return Icons.event_outlined;
      case 'daily_routine':
        return Icons.wb_sunny_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  StatusTone _toneFor(String status) {
    switch (status) {
      case 'completed':
        return StatusTone.ready;
      case 'missed':
        return StatusTone.danger;
      default:
        return StatusTone.info;
    }
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(item.kind), color: Theme.of(context).colorScheme.primary),
      title: Text(item.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text('${item.kind} · ${item.time}'),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'voice':
        return Icons.record_voice_over_outlined;
      case 'reminder':
        return Icons.alarm_outlined;
      case 'vision':
        return Icons.face_outlined;
      case 'memory':
        return Icons.auto_stories_outlined;
      default:
        return Icons.history;
    }
  }
}
