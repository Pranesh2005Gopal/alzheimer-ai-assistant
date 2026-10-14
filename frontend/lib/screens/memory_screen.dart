import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../widgets/app_widgets.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool _loading = false;
  Map<String, dynamic>? _memory;
  String? _error;
  final _noteController = TextEditingController();
  bool _addingNote = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = AssistantScope.of(context);
      final data = await controller.loadMemory();
      if (!mounted) return;
      setState(() {
        _memory = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load memory: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    setState(() => _addingNote = true);
    try {
      final controller = AssistantScope.of(context);
      await controller.addMemoryNote(text);
      _noteController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add note: $e')));
      }
    } finally {
      if (mounted) setState(() => _addingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final overview = controller.overview;
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
                        Icon(Icons.auto_stories_outlined, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Memory Assistance', style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Important people, dates, and preferences stored by the assistant.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Family & People (from overview for quick load)
              if (overview != null && overview.family.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Familiar People', icon: Icons.people_outlined),
                      const SizedBox(height: 8),
                      ...overview.family.map((p) => _PersonTile(person: p)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Important Dates
              if (overview != null && overview.importantDates.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Important Dates', icon: Icons.calendar_today_outlined),
                      const SizedBox(height: 8),
                      ...overview.importantDates.map((d) => _DateTile(date: d)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Preferences
              if (overview != null && overview.preferences.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Preferences', icon: Icons.favorite_border),
                      const SizedBox(height: 8),
                      ...overview.preferences.map((p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.star_outline, color: Theme.of(context).colorScheme.primary),
                            title: Text(p.key, style: Theme.of(context).textTheme.titleMedium),
                            subtitle: Text(p.value),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Raw memory details from API
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (_error != null)
                AppCard(child: ErrorState(message: _error!, onRetry: _load))
              else if (_memory != null) ...[
                _MemoryRawCard(data: _memory!),
                const SizedBox(height: 16),
              ],

              // No data state
              if (!_loading && _error == null && (overview == null || (overview.family.isEmpty && overview.importantDates.isEmpty && overview.preferences.isEmpty)))
                AppCard(
                  child: const EmptyState(
                    title: 'No memories stored yet',
                    message: 'Talk to the assistant and it will remember important information for you.',
                    icon: Icons.auto_stories_outlined,
                  ),
                ),

              const SizedBox(height: 16),

              // Add memory note
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Add a Memory Note', icon: Icons.edit_note_outlined),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Patient loves morning tea, sister\'s name is Priya…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _addingNote ? null : _addNote,
                      icon: _addingNote ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                      label: const Text('Save Note'),
                    ),
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

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final PersonItem person;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Text(
          person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
        ),
      ),
      title: Text(person.name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(person.relationship),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});

  final MemoryDate date;

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
        child: Icon(Icons.event_outlined, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(date.title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(date.date),
    );
  }
}

class _MemoryRawCard extends StatelessWidget {
  const _MemoryRawCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final notes = data['notes'];
    if (notes == null || (notes is List && notes.isEmpty)) {
      return const SizedBox.shrink();
    }
    final noteList = notes is List ? notes.map((e) => '$e').toList() : <String>['$notes'];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Memory Notes', icon: Icons.note_outlined),
          const SizedBox(height: 8),
          ...noteList.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(note, style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
