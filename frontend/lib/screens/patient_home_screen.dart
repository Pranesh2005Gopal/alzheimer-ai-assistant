// This file is kept for reference only. The app now uses AppShell (app_shell.dart).
// PatientHomeScreen is no longer used; navigation is handled by AssistantController.navIndex.

import 'package:flutter/material.dart';

/// Legacy screen — superseded by [AppShell] + [DashboardScreen].
/// Kept here so it can be restored if needed; not referenced by main.dart.
class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Use AppShell instead.')),
    );
  }
}
