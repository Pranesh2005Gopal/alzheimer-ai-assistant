/// User Profile screen – name, avatar, DOB, language, voice preference,
/// hobbies, familiar people, daily routine, important dates, personal memories.
library;

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../models/auth_models.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameCtrl;
  late TextEditingController _preferredNameCtrl;
  late TextEditingController _dobCtrl;
  String _language = 'en';
  String _voice = 'female';
  List<String> _hobbies = [];
  List<String> _routine = [];
  List<String> _memories = [];

  bool _editing = false;
  bool _saving = false;
  String? _error;

  static const _languages = [
    ('en', 'English'), ('es', 'Spanish'), ('fr', 'French'),
    ('de', 'German'), ('hi', 'Hindi'), ('ta', 'Tamil'), ('te', 'Telugu'),
  ];

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController();
    _preferredNameCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = AuthScope.of(context).user;
    if (user != null && _fullNameCtrl.text.isEmpty) {
      final p = user.profile;
      _fullNameCtrl.text = p.fullName;
      _preferredNameCtrl.text = p.preferredName;
      _dobCtrl.text = p.dateOfBirth;
      _language = p.language.isNotEmpty ? p.language : 'en';
      _voice = p.voicePreference.isNotEmpty ? p.voicePreference : 'female';
      _hobbies = List<String>.from(p.hobbies);
      _routine = List<String>.from(p.dailyRoutine);
      _memories = List<String>.from(p.personalMemories);
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _preferredNameCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    final auth = AuthScope.of(context);
    final ok = await auth.updateProfile({
      'full_name': _fullNameCtrl.text.trim(),
      'preferred_name': _preferredNameCtrl.text.trim(),
      'date_of_birth': _dobCtrl.text.trim(),
      'language': _language,
      'voice_preference': _voice,
      'hobbies': _hobbies,
      'daily_routine': _routine,
      'personal_memories': _memories,
    });
    if (mounted) {
      setState(() { _saving = false; _editing = !ok; _error = ok ? null : auth.error; });
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // List item editors (hobbies, routine, memories)
  // ---------------------------------------------------------------------------

  Future<void> _addItem(List<String> list, String label) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => list.add(result));
    }
  }

  Widget _listChips(List<String> items, String label, VoidCallback onAdd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...items.map(
              (h) => Chip(
                label: Text(h),
                deleteIcon: _editing ? const Icon(Icons.close, size: 16) : null,
                onDeleted: _editing ? () => setState(() => items.remove(h)) : null,
              ),
            ),
            if (_editing)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text('Add'),
                onPressed: () => _addItem(items, label),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final user = auth.user;
    if (user == null) return const SizedBox();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing) ...[
            TextButton(
              onPressed: _saving ? null : () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ),

              // Avatar row
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        (user.profile.preferredName.isNotEmpty
                                ? user.profile.preferredName
                                : user.profile.fullName)
                            .characters
                            .take(2)
                            .string
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.profile.fullName.isNotEmpty ? user.profile.fullName : 'Your Name',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      user.email,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Chip(
                      label: Text(user.role.toUpperCase()),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Basic info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Basic Information'),
                      TextFormField(
                        controller: _fullNameCtrl,
                        enabled: _editing,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Name required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _preferredNameCtrl,
                        enabled: _editing,
                        decoration: const InputDecoration(
                          labelText: 'Preferred Name (call me…)',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dobCtrl,
                        enabled: _editing,
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth (optional)',
                          prefixIcon: Icon(Icons.cake_outlined),
                          hintText: 'YYYY-MM-DD',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Preferences card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Preferences'),
                      DropdownButtonFormField<String>(
                        value: _language,
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          prefixIcon: Icon(Icons.language),
                          border: OutlineInputBorder(),
                        ),
                        items: _languages
                            .map((l) => DropdownMenuItem(value: l.$1, child: Text(l.$2)))
                            .toList(),
                        onChanged: _editing ? (v) => setState(() => _language = v ?? 'en') : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _voice,
                        decoration: const InputDecoration(
                          labelText: 'Voice Preference',
                          prefixIcon: Icon(Icons.record_voice_over_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                        ],
                        onChanged: _editing ? (v) => setState(() => _voice = v ?? 'female') : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Hobbies, routine, memories
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _listChips(_hobbies, 'Hobbies & Interests', () {}),
                      _listChips(_routine, 'Daily Routine', () {}),
                      _listChips(_memories, 'Personal Memories', () {}),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Security settings
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('Security'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.pin_outlined),
                        title: Text(user.hasPin ? 'Change PIN' : 'Set Private PIN'),
                        subtitle: Text(
                          user.hasPin
                              ? 'A PIN protects your medical & private info'
                              : 'Set a PIN to protect private information',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showPinSetupDialog(),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Change Password'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showChangePasswordDialog(),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout),
                        title: const Text('Sign Out'),
                        textColor: AppColors.danger,
                        iconColor: AppColors.danger,
                        onTap: () => _confirmLogout(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<void> _showPinSetupDialog() async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Private PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This PIN protects your medical and private information.'),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              decoration: const InputDecoration(labelText: 'PIN (4–6 digits)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(labelText: 'Confirm PIN', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (pinCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('PINs do not match')),
                );
                return;
              }
              final auth = AuthScope.of(context);
              final ok = await auth.setPin(pinCtrl.text);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'PIN set successfully.' : auth.error ?? 'Error')),
                );
              }
            },
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              decoration: const InputDecoration(labelText: 'New Password (min 8 chars)', border: OutlineInputBorder()),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final auth = AuthScope.of(context);
              final ok = await auth.changePassword(oldCtrl.text, newCtrl.text);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Password changed.' : auth.error ?? 'Error')),
                );
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
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
    if (confirm == true && mounted) {
      await AuthScope.of(context).logout();
    }
  }
}
