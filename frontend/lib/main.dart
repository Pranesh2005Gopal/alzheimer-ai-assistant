import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'settings/app_settings.dart';
import 'state/assistant_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final controller = AssistantController(settings: settings);
  runApp(PatientAssistantApp(controller: controller));
}

class PatientAssistantApp extends StatefulWidget {
  const PatientAssistantApp({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<PatientAssistantApp> createState() => _PatientAssistantAppState();
}

class _PatientAssistantAppState extends State<PatientAssistantApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return AssistantScope(
          controller: widget.controller,
          child: MaterialApp(
            title: 'AI Memory Care',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: widget.controller.themeMode,
            home: const AppShell(),
          ),
        );
      },
    );
  }
}
