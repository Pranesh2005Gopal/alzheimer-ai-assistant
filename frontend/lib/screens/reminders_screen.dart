import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../widgets/app_widgets.dart';
import 'add_reminder_sheet.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final reminders = controller.overview?.reminders ?? const <ReminderItem>[];
        final appointments = controller.overview?.appointments ?? const <AppointmentItem>[];
        final active = controller.overview?.activeReminder;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              // Header
              AppCard(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alarm_outlined, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Reminders & Medications', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Medication reminders, appointments, and daily routines.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => showAddReminderSheet(context, controller),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Reminder'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Active now
              if (active != null) ...[
                AppCard(
                  color: const Color(0xFFFEF3C7),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(color: Color(0xFFFDE68A), shape: BoxShape.circle),
                        child: const Icon(Icons.notification_important_outlined, color: Color(0xFFB45309)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Due Now', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFFB45309))),
                            Text(active.title, style: Theme.of(context).textTheme.titleMedium),
                            Text('${active.kindLabel} · ${active.time}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: active.id.isNotEmpty ? () => controller.completeReminder(active.id) : null,
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Pending reminders
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Upcoming Reminders', icon: Icons.schedule_outlined),
                    const SizedBox(height: 8),
                    if (reminders.where((r) => r.status == 'pending').isEmpty)
                      const EmptyState(
                        title: 'No upcoming reminders',
                        message: 'Add a reminder using the button above.',
                        icon: Icons.alarm_off_outlined,
                      )
                    else
                      ...reminders.where((r) => r.status == 'pending').map((item) => ReminderTile(
                            item: item,
                            onComplete: item.id.isNotEmpty ? () => controller.completeReminder(item.id) : null,
                          )),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Completed / all
              if (reminders.any((r) => r.status != 'pending')) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'All Reminders', icon: Icons.list_alt_outlined),
                      const SizedBox(height: 8),
                      ...reminders.map((item) => ReminderTile(
                            item: item,
                            onComplete: item.status == 'pending' && item.id.isNotEmpty ? () => controller.completeReminder(item.id) : null,
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Appointments
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Appointments', icon: Icons.event_outlined),
                    const SizedBox(height: 8),
                    if (appointments.isEmpty)
                      const EmptyState(
                        title: 'No appointments stored',
                        message: 'Appointments will appear here when the assistant has them.',
                        icon: Icons.event_busy_outlined,
                      )
                    else
                      ...appointments.map((item) => _AppointmentTile(item: item)),
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

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.item});

  final AppointmentItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.local_hospital_outlined, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(item.doctor, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('${item.date} · ${item.time}${item.location.isNotEmpty ? " · ${item.location}" : ""}'),
    );
  }
}
