import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'screens/app_shell.dart';
import 'screens/landing_page.dart';
import 'screens/login_screen.dart';
import 'settings/app_settings.dart';
import 'state/assistant_controller.dart';
import 'state/auth_controller.dart';
import 'theme/app_theme.dart';
import 'web/url_strategy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
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
                  title: 'AI Memory Care — Personalized Voice Assistant',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: widget.controller.themeMode,
                  home: _RootNavigator(
                    authController: widget.authController,
                    initialRoute: _AppRoute.fromPath(Uri.base.path),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Routes to the public landing page, existing login/register screens,
/// or the authenticated app shell based on auth state.
class _RootNavigator extends StatefulWidget {
  const _RootNavigator({
    required this.authController,
    required this.initialRoute,
  });

  final AuthController authController;
  final _AppRoute initialRoute;

  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

enum _UnauthView { landing, login, register }

/// The public web paths supported by Firebase Hosting's SPA rewrite.
///
/// These paths deliberately map only to screens and AppShell destinations
/// that already exist in this application. Unknown paths continue to show the
/// landing page instead of exposing a new route surface.
class _AppRoute {
  const _AppRoute._(this.unauthView, this.navIndex);

  const _AppRoute.landing() : this._(_UnauthView.landing, null);
  const _AppRoute.login() : this._(_UnauthView.login, null);
  const _AppRoute.register() : this._(_UnauthView.register, null);
  const _AppRoute.dashboard() : this._(_UnauthView.landing, 0);
  const _AppRoute.voice() : this._(_UnauthView.landing, 1);
  const _AppRoute.face() : this._(_UnauthView.landing, 4);

  final _UnauthView unauthView;
  final int? navIndex;

  static _AppRoute fromPath(String path) {
    switch (path) {
      case '/login':
        return const _AppRoute.login();
      case '/register':
        return const _AppRoute.register();
      case '/dashboard':
        return const _AppRoute.dashboard();
      case '/voice':
        return const _AppRoute.voice();
      case '/face':
        return const _AppRoute.face();
      case '/':
      default:
        return const _AppRoute.landing();
    }
  }
}

class _RootNavigatorState extends State<_RootNavigator> {
  late _UnauthView _unauthView;
  AuthState? _lastAuthState;

  @override
  void initState() {
    super.initState();
    _unauthView = widget.initialRoute.unauthView;
    widget.authController.addListener(_onAuthChanged);
    final initialNavIndex = widget.initialRoute.navIndex;
    if (initialNavIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AssistantScope.of(context).selectNav(initialNavIndex);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RootNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authController != widget.authController) {
      oldWidget.authController.removeListener(_onAuthChanged);
      widget.authController.addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final next = widget.authController.state;
    if (_lastAuthState == AuthState.authenticated && next == AuthState.unauthenticated) {
      _unauthView = _UnauthView.landing;
    }
    _lastAuthState = next;
    if (mounted) {
      setState(() {});
    }
  }

  void _show(_UnauthView view) {
    setState(() => _unauthView = view);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.authController.state) {
      case AuthState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthState.unauthenticated:
        switch (_unauthView) {
          case _UnauthView.landing:
            return LandingPage(
              onLogin: () => _show(_UnauthView.login),
              onRegister: () => _show(_UnauthView.register),
              onGetStarted: () => _show(_UnauthView.register),
            );
          case _UnauthView.login:
            return LoginScreen(onBack: () => _show(_UnauthView.landing));
          case _UnauthView.register:
            return LoginScreen(
              startInRegister: true,
              onBack: () => _show(_UnauthView.landing),
            );
        }
      case AuthState.authenticated:
        return const AppShell();
    }
  }
}
