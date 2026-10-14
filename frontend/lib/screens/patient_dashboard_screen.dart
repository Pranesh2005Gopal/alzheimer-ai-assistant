/// Patient Dashboard Screen – reassuring, accessible, high-contrast, uncluttered design.
/// Features prominent live clock, voice assistant shortcut, daily routine, reminders,
/// familiar people, personal memories, and emergency assistance shortcut.
library;

import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

class PatientDashboardScreen extends StatelessWidget {
  const PatientDashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    final auth = AuthScope.of(context);
    final user = auth.user;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Top Header with live clock, greeting, notifications, and profile menu
                  _PatientHeader(controller: controller, user: user, onNavigate: onNavigate),
                  const SizedBox(height: 20),

                  // 2. Large "Talk to Assistant" Button
                  _TalkToAssistantCard(onTap: () => onNavigate(1)),
                  const SizedBox(height: 20),

                  // 3. Emergency Assistance Shortcut (Large, reassuring)
                  _EmergencyCard(overview: controller.overview),
                  const SizedBox(height: 20),

                  // 4. Today's Reminders & Medication
                  _PatientRemindersCard(
                    reminders: controller.overview?.reminders ?? [],
                    onComplete: (id) => controller.completeReminder(id),
                    onOpenAll: () => onNavigate(2),
                  ),
                  const SizedBox(height: 20),

                  // 5. Next Doctor Appointment
                  if (controller.overview?.nextAppointment != null) ...[
                    _NextAppointmentCard(appointment: controller.overview!.nextAppointment!),
                    const SizedBox(height: 20),
                  ],

                  // 6. Daily Routine & Schedule
                  _DailyRoutineCard(user: user),
                  const SizedBox(height: 20),

                  // 7. Familiar People & Loved Ones
                  _FamiliarPeopleCard(
                    family: controller.overview?.family ?? [],
                    onOpenFaces: () => onNavigate(4),
                  ),
                  const SizedBox(height: 20),

                  // 8. Personal Memories & Saved Thoughts
                  _MemoriesCard(
                    user: user,
                    importantDates: controller.overview?.importantDates ?? [],
                    onOpenMemory: () => onNavigate(3),
                  ),
                  const SizedBox(height: 20),

                  // 9. Quick Profile & Privacy Shortcut Footer
                  _ProfilePrivacyFooter(onNavigate: onNavigate),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Patient Header with Reusable Live Clock & Profile Menu
// ---------------------------------------------------------------------------

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({
    required this.controller,
    required this.user,
    required this.onNavigate,
  });

  final AssistantController controller;
  final AuthUser? user;
  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = user?.profile.preferredName.isNotEmpty == true
        ? user!.profile.preferredName
        : (user?.profile.fullName.isNotEmpty == true ? user!.profile.fullName : controller.patientName);
    final displayName = name.isNotEmpty ? name : 'Friend';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, AppColors.tealDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar: Avatar, Greeting, Notifications & Menu
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: Text(
                  displayName.characters.take(1).string.toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $displayName',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'You are safe, loved, and at home.',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              // Notifications
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                tooltip: 'Notifications',
                onPressed: () => _showNotifications(context),
              ),
              // Profile Menu
              _ProfilePopupMenu(onNavigate: onNavigate),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),

          // Reusable Live Clock (Real-time update)
          const LiveClockWidget(dark: false, fontSize: 40, dateFontSize: 16),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: AppColors.teal),
                const SizedBox(width: 10),
                Text('Today’s Helpful Notes', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.wb_sunny_outlined, color: Colors.amber),
              title: Text('Good day!'),
              subtitle: Text('Remember to take a sip of water and enjoy the morning.'),
            ),
            const ListTile(
              leading: Icon(Icons.check_circle_outline, color: AppColors.success),
              title: Text('Your assistant is listening'),
              subtitle: Text('Press the big green button anytime you want to talk.'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Large "Talk to Assistant" Card
// ---------------------------------------------------------------------------

class _TalkToAssistantCard extends StatelessWidget {
  const _TalkToAssistantCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.teal,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, size: 40, color: Colors.white),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Talk to Assistant',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap here to ask a question, hear a story, or check your pills.',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Emergency Card
// ---------------------------------------------------------------------------

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.overview});

  final OverviewData? overview;

  @override
  Widget build(BuildContext context) {
    final carer = overview?.caregiverName.isNotEmpty == true ? overview!.caregiverName : 'Priya';

    return AppCard(
      color: Colors.red.shade50,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emergency_outlined, color: AppColors.danger, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency Assistance',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.danger),
                ),
                const SizedBox(height: 2),
                Text(
                  'Need help immediately? Call $carer or doctor.',
                  style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.phone, size: 18),
            label: const Text('Call Help', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.contact_phone, color: AppColors.danger),
                      SizedBox(width: 8),
                      Text('Emergency Contacts'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person, color: AppColors.teal),
                        title: Text(carer),
                        subtitle: const Text('Caregiver · (555) 987-6543'),
                        trailing: const Icon(Icons.call, color: AppColors.success),
                      ),
                      const ListTile(
                        leading: Icon(Icons.local_hospital, color: Colors.blue),
                        title: Text('Dr. Sarah Connor'),
                        subtitle: Text('Doctor · (555) 234-5678'),
                        trailing: Icon(Icons.call, color: AppColors.success),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Today's Reminders & Medication
// ---------------------------------------------------------------------------

class _PatientRemindersCard extends StatelessWidget {
  const _PatientRemindersCard({
    required this.reminders,
    required this.onComplete,
    required this.onOpenAll,
  });

  final List<ReminderItem> reminders;
  final ValueChanged<String> onComplete;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, color: AppColors.teal, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Today’s Reminders & Medicine',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onOpenAll, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 12),
          if (reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'No pending reminders right now! Great job.',
                    style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            ...reminders.take(4).map((item) {
              final isDone = item.status == 'completed';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDone ? Colors.green.shade50 : Colors.teal.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDone ? Colors.green.shade200 : Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isDone ? AppColors.success : AppColors.teal,
                        size: 28,
                      ),
                      onPressed: isDone ? null : () => onComplete(item.id),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          Text(
                            '${item.time} · ${item.kindLabel}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Next Appointment Card
// ---------------------------------------------------------------------------

class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard({required this.appointment});

  final AppointmentItem appointment;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_today, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Doctor’s Appointment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('${appointment.doctor} on ${appointment.date} at ${appointment.time}',
                    style: const TextStyle(fontSize: 14)),
                if (appointment.location.isNotEmpty)
                  Text('Location: ${appointment.location}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Daily Routine Card
// ---------------------------------------------------------------------------

class _DailyRoutineCard extends StatelessWidget {
  const _DailyRoutineCard({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final routine = user?.profile.dailyRoutine ?? [];
    final items = routine.isNotEmpty
        ? routine
        : ['Morning walk at 7:30 AM', 'Breakfast at 8:30 AM', 'Medication at 9:00 AM', 'Afternoon rest at 1:30 PM', 'Dinner at 7:00 PM'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule, color: AppColors.teal, size: 22),
              SizedBox(width: 8),
              Text('Your Daily Routine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (step) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right, color: AppColors.teal, size: 22),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(step, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Familiar People & Loved Ones
// ---------------------------------------------------------------------------

class _FamiliarPeopleCard extends StatelessWidget {
  const _FamiliarPeopleCard({required this.family, required this.onOpenFaces});

  final List<PersonItem> family;
  final VoidCallback onOpenFaces;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_outline, color: Colors.pink, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('People You Love', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onOpenFaces, child: const Text('Familiar Faces')),
            ],
          ),
          const SizedBox(height: 10),
          if (family.isEmpty)
            const Text('Family & friends will appear here.', style: TextStyle(color: Colors.grey))
          else
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: family.map((person) {
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: AppColors.teal.withValues(alpha: 0.2),
                    child: Text(person.name.characters.take(1).string, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  label: Text('${person.name} (${person.relationship})', style: const TextStyle(fontWeight: FontWeight.w600)),
                  padding: const EdgeInsets.all(8),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Personal Memories Card
// ---------------------------------------------------------------------------

class _MemoriesCard extends StatelessWidget {
  const _MemoriesCard({
    required this.user,
    required this.importantDates,
    required this.onOpenMemory,
  });

  final AuthUser? user;
  final List<MemoryDate> importantDates;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final memories = user?.profile.personalMemories ?? [];
    final items = memories.isNotEmpty
        ? memories
        : ['Lived in Bristol for 30 years', 'Worked as an architect', 'Beloved golden retriever named Buster'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories, color: Colors.indigo, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Special Memories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onOpenMemory, child: const Text('Memory Book')),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (m) => Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, size: 20, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(m, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 9. Profile & Privacy Shortcut Footer
// ---------------------------------------------------------------------------

class _ProfilePrivacyFooter extends StatelessWidget {
  const _ProfilePrivacyFooter({required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_outline),
            label: const Text('My Profile'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => onNavigate(5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('Private Details'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => onNavigate(6),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable Profile Popup Menu
// ---------------------------------------------------------------------------

class _ProfilePopupMenu extends StatelessWidget {
  const _ProfilePopupMenu({required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (val) async {
        if (val == 'profile') onNavigate(5);
        if (val == 'private') onNavigate(6);
        if (val == 'settings') onNavigate(7);
        if (val == 'logout') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign Out'),
              content: const Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
          if (confirm == true && context.mounted) {
            await AuthScope.of(context).logout();
          }
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'profile',
          child: Row(children: [Icon(Icons.person_outline), SizedBox(width: 8), Text('My Profile')]),
        ),
        const PopupMenuItem(
          value: 'private',
          child: Row(children: [Icon(Icons.lock_outline), SizedBox(width: 8), Text('Private Information')]),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(children: [Icon(Icons.settings_outlined), SizedBox(width: 8), Text('Settings')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(children: [Icon(Icons.logout, color: AppColors.danger), SizedBox(width: 8), Text('Sign Out', style: TextStyle(color: AppColors.danger))]),
        ),
      ],
    );
  }
}
