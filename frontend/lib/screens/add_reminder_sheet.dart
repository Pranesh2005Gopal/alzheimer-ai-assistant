import 'package:flutter/material.dart';

import '../state/assistant_controller.dart';

Future<void> showAddReminderSheet(BuildContext context, AssistantController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _AddReminderForm(controller: controller),
    ),
  );
}

class _AddReminderForm extends StatefulWidget {
  const _AddReminderForm({required this.controller});

  final AssistantController controller;

  @override
  State<_AddReminderForm> createState() => _AddReminderFormState();
}

class _AddReminderFormState extends State<_AddReminderForm> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  String _kind = 'general';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter what to remind.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.createReminder(
        title: _title.text.trim(),
        time: _time,
        kind: _kind,
        notes: _notes.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the reminder. $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add reminder', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'What should I remind you about?'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            items: const [
              DropdownMenuItem(value: 'medication', child: Text('Medicine')),
              DropdownMenuItem(value: 'daily_routine', child: Text('Meal / daily routine')),
              DropdownMenuItem(value: 'appointment', child: Text('Appointment')),
              DropdownMenuItem(value: 'general', child: Text('General')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'general'),
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Time'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _time);
              if (picked != null) {
                setState(() => _time = picked);
              }
            },
          ),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save reminder'),
          ),
        ],
      ),
    );
  }
}
