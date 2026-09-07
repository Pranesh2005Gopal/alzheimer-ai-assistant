import 'package:flutter/material.dart';

import 'screens/patient_home_screen.dart';
import 'theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PatientAssistantApp());
}

class PatientAssistantApp extends StatelessWidget {
  const PatientAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.talk,
          surface: AppColors.card,
        ),
      ),
      home: const PatientHomeScreen(),
    );
  }
}
