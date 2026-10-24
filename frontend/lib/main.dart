import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'settings/app_settings.dart';
import 'state/assistant_controller.dart';
import 'state/auth_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final authApi = AuthApi(baseUrl: settings.apiBase);
  final controller = AssistantController(
    settings: settings,
    tokenProvider: () => authApi.token,
  );
  final authController = AuthController(api: authApi);
  runApp(
    PatientAssistantApp(
      controller: controller,
      authController: authController,
      authApi: authApi,
    ),
  );
}

class PatientAssistantApp extends StatefulWidget {
  const PatientAssistantApp({
    super.key,
    required this.controller,
    required this.authController,
    required this.authApi,
  });

  final AssistantController controller;
  final AuthController authController;
  final AuthApi authApi;

  @override
  State<PatientAssistantApp> createState() => _PatientAssistantAppState();
}

class _PatientAssistantAppState extends State<PatientAssistantApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
    widget.authController.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    widget.authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.authController,
      builder: (context, _) {
        return AuthScope(
          controller: widget.authController,
          child: ListenableBuilder(
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
                  home: _RootNavigator(authController: widget.authController),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Routes to login screen or app shell based on auth state.
class _RootNavigator extends StatelessWidget {
  const _RootNavigator({required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    switch (authController.state) {
      case AuthState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthState.unauthenticated:
        return const LoginScreen();
      case AuthState.authenticated:
        return const AppShell();
    }
  }
}
