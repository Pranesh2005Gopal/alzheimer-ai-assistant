import 'package:flutter/material.dart';

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiController;
  late TextEditingController _nameController;
  bool _saving = false;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _apiController = TextEditingController();
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AssistantScope.of(context);
    if (_apiController.text.isEmpty) {
      _apiController.text = controller.apiBase;
    }
  }

  @override
  void dispose() {
    _apiController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveApi() async {
    final controller = AssistantScope.of(context);
    setState(() => _saving = true);
    try {
      await controller.saveApiBase(_apiController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server address saved. Reconnecting…')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final controller = AssistantScope.of(context);
    setState(() => _savingName = true);
    try {
      await controller.savePreferredName(name);
      _nameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Name set to "$name".')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save name: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final online = controller.link == AssistantLink.ready;
        final degraded = controller.link == AssistantLink.degraded;

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
                        Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Configure the assistant connection and app preferences.', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Connection status
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Connection Status', icon: Icons.wifi_outlined),
                    const SizedBox(height: 10),
                    StatusBadge(
                      label: online ? 'Connected to assistant' : degraded ? 'Degraded — Ollama unavailable' : 'Disconnected',
                      tone: online ? StatusTone.ready : degraded ? StatusTone.warning : StatusTone.danger,
                    ),
                    if (controller.loadError != null) ...[
                      const SizedBox(height: 8),
                      Text(controller.loadError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: controller.refreshAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // API URL
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Assistant Server Address', icon: Icons.lan_outlined),
                    const SizedBox(height: 4),
                    Text(
                      'Use the computer\'s local network IP when connecting from a phone (e.g. http://192.168.1.x:8080).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _apiController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API base URL',
                        hintText: 'http://192.168.1.x:8080',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.http_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveApi,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save & Connect'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Preferred name
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Patient Name', icon: Icons.person_outline),
                    const SizedBox(height: 4),
                    Text('Current: ${controller.patientName.isEmpty ? "Not set" : controller.patientName}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Preferred name',
                        hintText: 'Enter patient\'s preferred name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _savingName ? null : _saveName,
                      icon: _savingName
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save Name'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Theme
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Appearance', icon: Icons.palette_outlined),
                    const SizedBox(height: 8),
                    _ThemeTile(
                      label: 'System default',
                      mode: ThemeMode.system,
                      current: controller.themeMode,
                      onTap: () => controller.saveTheme(ThemeMode.system),
                    ),
                    _ThemeTile(
                      label: 'Light mode',
                      mode: ThemeMode.light,
                      current: controller.themeMode,
                      onTap: () => controller.saveTheme(ThemeMode.light),
                    ),
                    _ThemeTile(
                      label: 'Dark mode',
                      mode: ThemeMode.dark,
                      current: controller.themeMode,
                      onTap: () => controller.saveTheme(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // About
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'About', icon: Icons.info_outline),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.local_hospital_rounded, color: Theme.of(context).colorScheme.primary),
                      title: const Text('AI Memory Care Assistant'),
                      subtitle: const Text('Version 1.0.0 · Flutter'),
                    ),
                    Text(
                      'An AI-driven voice assistant for Alzheimer\'s patient care. Helps with reminders, memory assistance, and face recognition.',
                      style: Theme.of(context).textTheme.bodySmall,
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

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.label, required this.mode, required this.current, required this.onTap});

  final String label;
  final ThemeMode mode;
  final ThemeMode current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = current == mode;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      leading: Icon(
        mode == ThemeMode.system ? Icons.brightness_auto_outlined : mode == ThemeMode.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      trailing: selected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
      onTap: onTap,
    );
  }
}
