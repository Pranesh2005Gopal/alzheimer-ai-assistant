/// Caretaker Dashboard Screen – Task-oriented care-management interface.
/// Includes assigned patient overview, care task & reminder management, medication tracking,
/// appointment scheduler, care observations, activity timeline, face recognition events,
/// PIN-gated medical records, notification preferences, and security access audit history.
library;

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../models/auth_models.dart';
import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';
import 'add_reminder_sheet.dart';

class CaretakerDashboardScreen extends StatefulWidget {
  const CaretakerDashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  State<CaretakerDashboardScreen> createState() =>
      _CaretakerDashboardScreenState();
}

class _CaretakerDashboardScreenState extends State<CaretakerDashboardScreen> {
  int _activeTab = 0; // 0: Overview, 1: Care Management, 2: Monitoring, 3: Patient Profile, 4: Settings & Audit
  final _careNoteCtrl = TextEditingController();
  bool _savingNote = false;

  // Audit logs & assigned patients state
  List<Map<String, dynamic>> _assignedPatients = [];
  List<Map<String, dynamic>> _auditLogs = [];
  bool _loadingCareData = false;

  @override
  void initState() {
    super.initState();
    _loadCaregiverData();
  }

  @override
  void dispose() {
    _careNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCaregiverData() async {
    setState(() => _loadingCareData = true);
    try {
      final auth = AuthScope.of(context);
      final patients = await auth.api.getAssignedPatients();
      final logs = await auth.api.getAuditLogs();
      if (mounted) {
        setState(() {
          _assignedPatients = patients;
          _auditLogs = logs;
          _loadingCareData = false;
        });
        final controller = AssistantScope.of(context);
        if (patients.isNotEmpty && controller.selectedPatientId == null) {
          await controller.selectCaregiverPatient(
            patients.first['id'] as String?,
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCareData = false);
    }
  }

  Future<void> _submitCareNote() async {
    final text = _careNoteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingNote = true);
    final controller = AssistantScope.of(context);
    final ok = await controller.api.addCareNote(
      note: text,
      category: 'observation',
    );
    if (mounted) {
      setState(() => _savingNote = false);
      if (ok) {
        _careNoteCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Care observation note recorded.')),
        );
        controller.refresh();
      }
    }
  }

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
                  // 1. Caretaker Header with Live Clock & Profile Menu
                  _CaretakerHeader(
                    user: user,
                    onNavigate: widget.onNavigate,
                    onRefresh: () {
                      controller.refresh();
                      _loadCaregiverData();
                    },
                  ),
                  const SizedBox(height: 18),

                  // 2. Navigation Tabs (Overview, Care Tasks, Monitoring, Patient Profile, Settings)
                  _CareNavTabs(
                    activeTab: _activeTab,
                    onSelectTab: (idx) => setState(() => _activeTab = idx),
                  ),
                  const SizedBox(height: 20),

                  // 3. Dynamic Section Content Based on Active Tab
                  if (_activeTab == 0) ...[
                    _OverviewSection(
                      controller: controller,
                      assignedPatients: _assignedPatients,
                      selectedPatientId: controller.selectedPatientId,
                      onSelectPatient: controller.selectCaregiverPatient,
                      onNavigate: widget.onNavigate,
                      onGoToCare: () => setState(() => _activeTab = 1),
                    ),
                  ] else if (_activeTab == 1) ...[
                    _CareManagementSection(
                      controller: controller,
                      noteCtrl: _careNoteCtrl,
                      savingNote: _savingNote,
                      onSubmitNote: _submitCareNote,
                    ),
                  ] else if (_activeTab == 2) ...[
                    _PatientMonitoringSection(
                      controller: controller,
                      onNavigate: widget.onNavigate,
                    ),
                  ] else if (_activeTab == 3) ...[
                    _PatientProfileMemorySection(
                      controller: controller,
                      onNavigate: widget.onNavigate,
                    ),
                  ] else ...[
                    _SettingsAuditSection(
                      auditLogs: _auditLogs,
                      onRefreshLogs: _loadCaregiverData,
                    ),
                  ],

                  const SizedBox(height: 24),
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
// 1. Caretaker Header
// ---------------------------------------------------------------------------

class _CaretakerHeader extends StatelessWidget {
  const _CaretakerHeader({
    required this.user,
    required this.onNavigate,
    required this.onRefresh,
  });

  final AuthUser? user;
  final void Function(int index) onNavigate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = user?.profile.fullName.isNotEmpty == true
        ? user!.profile.fullName
        : (user?.profile.preferredName.isNotEmpty == true
              ? user!.profile.preferredName
              : 'Priya Pendelton');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.teal,
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.teal),
                          ),
                          child: const Text(
                            'CAREGIVER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Clinical Care & Patient Management Dashboard',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh data',
                onPressed: onRefresh,
              ),
              _CaregiverPopupMenu(onNavigate: onNavigate),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),

          // Reusable Live Clock
          const LiveClockWidget(dark: false, fontSize: 38, dateFontSize: 15),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Navigation Tabs
// ---------------------------------------------------------------------------

class _CareNavTabs extends StatelessWidget {
  const _CareNavTabs({required this.activeTab, required this.onSelectTab});

  final int activeTab;
  final ValueChanged<int> onSelectTab;

  static const _tabs = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.checklist_rtl_outlined, 'Care Tasks'),
    (Icons.timeline_outlined, 'Monitoring'),
    (Icons.folder_shared_outlined, 'Patient Records'),
    (Icons.security_outlined, 'Settings & Audit'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final idx = entry.key;
          final tab = entry.value;
          final isSelected = activeTab == idx;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                tab.$1,
                size: 18,
                color: isSelected ? Colors.white : AppColors.teal,
              ),
              label: Text(tab.$2),
              selected: isSelected,
              selectedColor: AppColors.teal,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (_) => onSelectTab(idx),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Tab 0: Overview Section
// ---------------------------------------------------------------------------

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.controller,
    required this.assignedPatients,
    required this.selectedPatientId,
    required this.onSelectPatient,
    required this.onNavigate,
    required this.onGoToCare,
  });

  final AssistantController controller;
  final List<Map<String, dynamic>> assignedPatients;
  final String? selectedPatientId;
  final ValueChanged<String?> onSelectPatient;
  final void Function(int index) onNavigate;
  final VoidCallback onGoToCare;

  @override
  Widget build(BuildContext context) {
    final reminders = controller.overview?.reminders ?? [];
    final completed = reminders.where((r) => r.status == 'completed').length;
    final pending = reminders.where((r) => r.status == 'pending').length;
    final missed = reminders.where((r) => r.status == 'missed').length;
    final nextAppt = controller.overview?.nextAppointment;

    final selected = assignedPatients
        .where((p) => p['id'] == selectedPatientId)
        .firstOrNull;
    final patientName = selected != null
        ? selected['name'] as String? ?? 'Patient'
        : (controller.patientName.isNotEmpty
              ? controller.patientName
              : 'Arthur Pendelton');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Assigned-patient selector. This response deliberately contains no
        // medical records; those are fetched only after backend authorization.
        if (assignedPatients.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: selectedPatientId,
            decoration: const InputDecoration(
              labelText: 'Selected patient',
              prefixIcon: Icon(Icons.people_outline),
              border: OutlineInputBorder(),
            ),
            items: assignedPatients
                .map(
                  (patient) => DropdownMenuItem<String>(
                    value: patient['id'] as String?,
                    child: Text(patient['name'] as String? ?? 'Patient'),
                  ),
                )
                .toList(),
            onChanged: onSelectPatient,
          ),
          const SizedBox(height: 16),
        ] else
          const AppCard(
            child: Text('No patients are currently assigned to your account.'),
          ),

        // Selected patient banner
        AppCard(
          color: Colors.blue.shade50.withValues(alpha: 0.7),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.teal,
                child: Text(
                  patientName.characters.take(1).string,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          patientName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ACTIVE PATIENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Diagnosis: Early-stage Alzheimer’s · Primary Care assigned',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: selectedPatientId == null
                    ? null
                    : () => onNavigate(5),
                child: const Text('Medical Info'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Care Task Metric Pills
        Row(
          children: [
            Expanded(
              child: _metricPill(
                'Total Tasks',
                '${reminders.length}',
                Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricPill('Completed', '$completed', AppColors.success),
            ),
            const SizedBox(width: 10),
            Expanded(child: _metricPill('Pending', '$pending', Colors.orange)),
            const SizedBox(width: 10),
            Expanded(child: _metricPill('Missed', '$missed', AppColors.danger)),
          ],
        ),
        const SizedBox(height: 16),

        // Missed Reminder Attention Banner (if any)
        if (missed > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: AppColors.danger),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Attention: $missed care task(s) were missed today. Please verify with patient.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
                TextButton(onPressed: onGoToCare, child: const Text('Resolve')),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Upcoming Appointment Card
        if (nextAppt != null) ...[
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.blue, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next Scheduled Appointment',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${nextAppt.doctor} on ${nextAppt.date} at ${nextAppt.time}',
                      ),
                      if (nextAppt.location.isNotEmpty)
                        Text(
                          'Location: ${nextAppt.location}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Recent Activity Teaser
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: AppColors.teal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recent Patient Interaction Log',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onNavigate(1),
                    child: const Text('Live Assistant'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (controller.overview?.activity.isEmpty ?? true)
                const Text(
                  'No recent activity recorded.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...controller.overview!.activity
                    .take(4)
                    .map(
                      (act) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chevron_right, size: 18),
                        title: Text(
                          act.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${act.kind} · ${act.time}'),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricPill(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Tab 1: Care Management Section
// ---------------------------------------------------------------------------

class _CareManagementSection extends StatelessWidget {
  const _CareManagementSection({
    required this.controller,
    required this.noteCtrl,
    required this.savingNote,
    required this.onSubmitNote,
  });

  final AssistantController controller;
  final TextEditingController noteCtrl;
  final bool savingNote;
  final VoidCallback onSubmitNote;

  @override
  Widget build(BuildContext context) {
    final reminders = controller.overview?.reminders ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action Bar: Add Reminder & Schedule Appointment
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_alarm),
                label: const Text('Add Reminder'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => showAddReminderSheet(context, controller),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('Schedule Clinic'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _showScheduleDialog(context, controller),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Care Observations Box
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_note, color: AppColors.teal, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Record Care Observation',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. Arthur ate a full lunch, mood is positive, completed exercises.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  icon: savingNote
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Save Note'),
                  onPressed: savingNote ? null : onSubmitNote,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Reminders & Medication Management List
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Active Care Tasks & Medications',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 12),
              if (reminders.isEmpty)
                const Text(
                  'No tasks recorded.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...reminders.map((r) {
                  final isDone = r.status == 'completed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(
                        isDone ? Icons.check_circle : Icons.alarm,
                        color: isDone
                            ? AppColors.success
                            : (r.kind == 'medication'
                                  ? Colors.purple
                                  : AppColors.teal),
                      ),
                      title: Text(
                        r.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${r.time} · ${r.kindLabel} ${r.medicationName != null ? "(${r.medicationName})" : ""}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isDone)
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: AppColors.success,
                              ),
                              tooltip: 'Mark Complete',
                              onPressed: () =>
                                  controller.completeReminder(r.id),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.danger,
                            ),
                            tooltip: 'Delete',
                            onPressed: () async {
                              await controller.api.deleteReminder(r.id);
                              controller.refresh();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  void _showScheduleDialog(
    BuildContext context,
    AssistantController controller,
  ) {
    final docCtrl = TextEditingController(text: 'Dr. Sarah Connor');
    final dateCtrl = TextEditingController(text: '2026-10-20');
    final timeCtrl = TextEditingController(text: '10:30 AM');
    final locCtrl = TextEditingController(text: 'Springfield Memory Clinic');
    final purpCtrl = TextEditingController(text: 'Cognitive follow-up');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule Doctor Appointment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: docCtrl,
                decoration: const InputDecoration(labelText: 'Doctor Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(labelText: 'Time'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: locCtrl,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: purpCtrl,
                decoration: const InputDecoration(labelText: 'Purpose'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await controller.api.createAppointment(
                doctor: docCtrl.text.trim(),
                dateIso: dateCtrl.text.trim(),
                timeIso: timeCtrl.text.trim(),
                location: locCtrl.text.trim(),
                purpose: purpCtrl.text.trim(),
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Appointment scheduled.')),
                );
                controller.refresh();
              }
            },
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Tab 2: Patient Monitoring Section
// ---------------------------------------------------------------------------

class _PatientMonitoringSection extends StatelessWidget {
  const _PatientMonitoringSection({
    required this.controller,
    required this.onNavigate,
  });

  final AssistantController controller;
  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final activity = controller.overview?.activity ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Care monitoring events. Vision remains patient-only.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.face_retouching_natural,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Care monitoring events',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (controller.lastFace != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Last Recognition: ${controller.lastFace!.personName} (${controller.lastFace!.message})',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                  'No recent monitoring events.',
                  style: TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Activity Timeline
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patient Activity & Interaction Timeline',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (activity.isEmpty)
                const Text(
                  'No activity events logged.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...activity.map((item) => ActivityTile(item: item)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Tab 3: Patient Profile & Memory Section
// ---------------------------------------------------------------------------

class _PatientProfileMemorySection extends StatelessWidget {
  const _PatientProfileMemorySection({
    required this.controller,
    required this.onNavigate,
  });

  final AssistantController controller;
  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final family = controller.overview?.family ?? [];
    final dates = controller.overview?.importantDates ?? [];
    final prefs = controller.overview?.preferences ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gated Medical Records Shortcut
        AppCard(
          color: Colors.amber.shade50.withValues(alpha: 0.6),
          child: Row(
            children: [
              const Icon(Icons.lock, color: AppColors.warning, size: 28),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Passcode-Protected Medical Records',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'View verified medical conditions, medications, and allergies.',
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                onPressed: () => onNavigate(5),
                child: const Text('Unlock with PIN'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Authorized Loved Ones & Familiar People
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Familiar People & Contacts',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (family.isEmpty)
                const Text(
                  'None recorded.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: family
                      .map(
                        (p) => Chip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text('${p.name} (${p.relationship})'),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Important Dates
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Important Dates & Anniversaries',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (dates.isEmpty)
                const Text(
                  'None recorded.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...dates.map(
                  (d) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.event, color: AppColors.teal),
                    title: Text(d.title),
                    subtitle: Text('${d.date} · ${d.kind}'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Preferences
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Authorized Patient Preferences',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (prefs.isEmpty)
                const Text(
                  'None recorded.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: prefs
                      .map((pr) => Chip(label: Text('${pr.key}: ${pr.value}')))
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Tab 4: Settings & Security Access Audit Section
// ---------------------------------------------------------------------------

class _SettingsAuditSection extends StatefulWidget {
  const _SettingsAuditSection({
    required this.auditLogs,
    required this.onRefreshLogs,
  });

  final List<Map<String, dynamic>> auditLogs;
  final VoidCallback onRefreshLogs;

  @override
  State<_SettingsAuditSection> createState() => _SettingsAuditSectionState();
}

class _SettingsAuditSectionState extends State<_SettingsAuditSection> {
  bool _notifyReminders = true;
  bool _notifyMissedDose = true;
  bool _notifySecurity = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Notification Preferences
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Caregiver Alert Preferences',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminder Notifications'),
                subtitle: const Text(
                  'Receive alerts when scheduled care tasks are due',
                ),
                value: _notifyReminders,
                onChanged: (val) => setState(() => _notifyReminders = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Missed Medication Alerts'),
                subtitle: const Text(
                  'Immediate alert when patient misses a medication time',
                ),
                value: _notifyMissedDose,
                onChanged: (val) => setState(() => _notifyMissedDose = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Security & Access Alerts'),
                subtitle: const Text('Alert when patient records are accessed'),
                value: _notifySecurity,
                onChanged: (val) => setState(() => _notifySecurity = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Security Access Audit Log
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.security, color: AppColors.teal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Access Audit History',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: widget.onRefreshLogs,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.auditLogs.isEmpty)
                const Text(
                  'No audit events logged yet.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...widget.auditLogs.take(8).map((log) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.teal,
                      size: 20,
                    ),
                    title: Text('${log["action"]} · Target: ${log["target"]}'),
                    subtitle: Text(
                      '${log["timestamp"]} · ${log["details"] ?? ""}',
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Caregiver Popup Menu
// ---------------------------------------------------------------------------

class _CaregiverPopupMenu extends StatelessWidget {
  const _CaregiverPopupMenu({required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (val) async {
        if (val == 'profile') onNavigate(4);
        if (val == 'settings') onNavigate(6);
        if (val == 'logout') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign Out'),
              content: const Text(
                'Are you sure you want to sign out from Caregiver session?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
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
          child: Row(
            children: [
              Icon(Icons.person_outline),
              SizedBox(width: 8),
              Text('Caregiver Profile'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 8),
              Text('Settings'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Sign Out', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    );
  }
}
