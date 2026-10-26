/// Private Information screen – PIN-protected medical records.
/// Shows a PIN entry gate before revealing sensitive data.
library;

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../models/auth_models.dart';
import '../state/auth_controller.dart';
import '../state/assistant_controller.dart';
import '../theme/app_colors.dart';

class PrivateInfoScreen extends StatefulWidget {
  const PrivateInfoScreen({super.key});

  @override
  State<PrivateInfoScreen> createState() => _PrivateInfoScreenState();
}

class _PrivateInfoScreenState extends State<PrivateInfoScreen> {
  bool get _isCaregiver => AuthScope.of(context).user?.isCaregiver == true;
  // PIN gate
  bool _unlocked = false;
  bool _verifying = false;
  String? _pinError;
  final _pinCtrl = TextEditingController();
  String? _grant;

  // Data
  PrivateInfo? _privateInfo;
  bool _loadingData = false;
  bool _editing = false;
  bool _saving = false;

  // Edit controllers
  List<String> _conditions = [];
  List<String> _allergies = [];
  List<Map<String, dynamic>> _medications = [];
  List<Map<String, dynamic>> _emergencyContacts = [];
  final _addressCtrl = TextEditingController();
  final _doctorNameCtrl = TextEditingController();
  final _doctorPhoneCtrl = TextEditingController();

  @override
  void dispose() {
    _pinCtrl.dispose();
    _addressCtrl.dispose();
    _doctorNameCtrl.dispose();
    _doctorPhoneCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // PIN verification
  // ---------------------------------------------------------------------------

  Future<void> _verifyPin() async {
    final auth = AuthScope.of(context);
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() => _pinError = 'Enter a valid 4–6 digit PIN');
      return;
    }
    setState(() {
      _verifying = true;
      _pinError = null;
    });
    final grant = await auth.verifyPin(pin);
    if (!mounted) return;
    if (grant != null) {
      _grant = grant;
      setState(() {
        _unlocked = true;
        _verifying = false;
      });
      await _loadPrivateData();
    } else {
      setState(() {
        _pinError = auth.error ?? 'Incorrect PIN';
        _verifying = false;
      });
    }
  }

  Future<void> _loadPrivateData() async {
    if (_grant == null) return;
    setState(() => _loadingData = true);
    try {
      final auth = AuthScope.of(context);
      final selectedPatientId = AssistantScope.of(context).selectedPatientId;
      final info = auth.user?.isCaregiver == true && selectedPatientId != null
          ? await auth.api.getCaregiverPatientPrivate(
              selectedPatientId,
              grant: _grant!,
            )
          : await auth.api.getPrivateInfo(grant: _grant!);
      if (mounted) {
        setState(() {
          _privateInfo = info;
          _conditions = List<String>.from(info.medicalConditions);
          _allergies = List<String>.from(info.allergies);
          _medications = List<Map<String, dynamic>>.from(info.medications);
          _emergencyContacts = List<Map<String, dynamic>>.from(
            info.emergencyContacts,
          );
          _addressCtrl.text = info.address;
          _doctorNameCtrl.text = (info.doctorDetails['name'] ?? '') as String;
          _doctorPhoneCtrl.text = (info.doctorDetails['phone'] ?? '') as String;
          _loadingData = false;
        });
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() => _loadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _savePrivate() async {
    if (_grant == null) return;
    setState(() => _saving = true);
    try {
      final auth = AuthScope.of(context);
      await auth.api.updatePrivateInfo(
        changes: {
          'medical_conditions': _conditions,
          'allergies': _allergies,
          'medications': _medications,
          'emergency_contacts': _emergencyContacts,
          'address': _addressCtrl.text.trim(),
          'doctor_details': {
            'name': _doctorNameCtrl.text.trim(),
            'phone': _doctorPhoneCtrl.text.trim(),
          },
        },
        grant: _grant!,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Private information saved.')),
        );
        await _loadPrivateData();
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final user = auth.user;

    if (user == null) return const SizedBox();

    if (!user.hasPin) {
      return _NoPinPlaceholder();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Information'),
        leading: _unlocked
            ? IconButton(
                icon: const Icon(Icons.lock),
                tooltip: 'Lock',
                onPressed: () => setState(() {
                  _unlocked = false;
                  _grant = null;
                  _privateInfo = null;
                  _pinCtrl.clear();
                }),
              )
            : null,
        actions: [
          if (_unlocked && !user.isCaregiver && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
          if (_unlocked && !user.isCaregiver && _editing) ...[
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _savePrivate,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ],
      ),
      body: _unlocked ? _unlockedBody() : _pinGate(),
    );
  }

  // ---------------------------------------------------------------------------
  // PIN gate widget
  // ---------------------------------------------------------------------------

  Widget _pinGate() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.health_and_safety,
                    size: 56,
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isCaregiver
                        ? 'Authorized Patient Medical Information'
                        : 'Private Medical Information',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isCaregiver
                        ? 'Enter your PIN to access the selected patient’s authorized records.'
                        : 'Enter your PIN to access protected information.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '● ● ● ●',
                      border: const OutlineInputBorder(),
                      errorText: _pinError,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verifyPin(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _verifying
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(_verifying ? 'Verifying…' : 'Unlock'),
                      onPressed: _verifying ? null : _verifyPin,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Locked after 5 failed attempts for 5 minutes.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Unlocked content
  // ---------------------------------------------------------------------------

  Widget _unlockedBody() {
    if (_loadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    final info = _privateInfo;
    if (info == null) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Load data'),
          onPressed: _loadPrivateData,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionCard(
            icon: Icons.medical_services_outlined,
            title: 'Medical Conditions',
            child: _editableChips(_conditions, 'condition'),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.warning_amber_outlined,
            title: 'Allergies',
            child: _editableChips(_allergies, 'allergy'),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.medication_outlined,
            title: 'Medications',
            child: _medicationsList(),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.local_hospital_outlined,
            title: 'Doctor Details',
            child: Column(
              children: [
                TextFormField(
                  controller: _doctorNameCtrl,
                  enabled: _editing,
                  decoration: const InputDecoration(
                    labelText: "Doctor's Name",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _doctorPhoneCtrl,
                  enabled: _editing,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Doctor's Phone",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.phone_in_talk_outlined,
            title: 'Emergency Contacts',
            child: _emergencyContactsList(),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            icon: Icons.home_outlined,
            title: 'Address',
            child: TextFormField(
              controller: _addressCtrl,
              enabled: _editing,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Home address',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _editableChips(List<String> items, String singular) {
    if (!_editing && items.isEmpty) {
      return Text(
        'None recorded',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...items.map(
          (item) => Chip(
            label: Text(item),
            deleteIcon: _editing ? const Icon(Icons.close, size: 16) : null,
            onDeleted: _editing
                ? () => setState(() => items.remove(item))
                : null,
          ),
        ),
        if (_editing)
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text('Add $singular'),
            onPressed: () async {
              final ctrl = TextEditingController();
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Add $singular'),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: InputDecoration(hintText: singular),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                setState(() => items.add(result));
              }
            },
          ),
      ],
    );
  }

  Widget _medicationsList() {
    if (!_editing && _medications.isEmpty) {
      return Text(
        'None recorded',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        ..._medications.asMap().entries.map((entry) {
          final med = entry.value;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.medication),
            title: Text(med['name'] as String? ?? ''),
            subtitle: Text(med['dosage'] as String? ?? ''),
            trailing: _editing
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _medications.removeAt(entry.key)),
                  )
                : null,
          );
        }),
        if (_editing)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Medication'),
            onPressed: () async {
              final nameCtrl = TextEditingController();
              final doseCtrl = TextEditingController();
              await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Add Medication'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Medication name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: doseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Dosage / instructions',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (nameCtrl.text.trim().isNotEmpty) {
                          setState(
                            () => _medications.add({
                              'name': nameCtrl.text.trim(),
                              'dosage': doseCtrl.text.trim(),
                            }),
                          );
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _emergencyContactsList() {
    if (!_editing && _emergencyContacts.isEmpty) {
      return Text(
        'No emergency contacts',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        ..._emergencyContacts.asMap().entries.map((entry) {
          final c = entry.value;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.contact_phone),
            title: Text(c['name'] as String? ?? ''),
            subtitle: Text('${c["relationship"] ?? ""} · ${c["phone"] ?? ""}'),
            trailing: _editing
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _emergencyContacts.removeAt(entry.key)),
                  )
                : null,
          );
        }),
        if (_editing)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Contact'),
            onPressed: () async {
              final nameCtrl = TextEditingController();
              final relCtrl = TextEditingController();
              final phoneCtrl = TextEditingController();
              await showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Emergency Contact'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: relCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Relationship',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (nameCtrl.text.trim().isNotEmpty) {
                          setState(
                            () => _emergencyContacts.add({
                              'name': nameCtrl.text.trim(),
                              'relationship': relCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                            }),
                          );
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder when no PIN set
// ---------------------------------------------------------------------------

class _NoPinPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private Information')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Set a PIN First',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'You need to set a PIN in your Profile before accessing private medical information.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.person_outline),
                label: const Text('Go to Profile'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
