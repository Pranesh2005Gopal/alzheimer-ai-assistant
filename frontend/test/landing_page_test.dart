import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_assistant/api/auth_api.dart';
import 'package:patient_assistant/screens/landing_page.dart';
import 'package:patient_assistant/screens/login_screen.dart';
import 'package:patient_assistant/state/auth_controller.dart';

void main() {
  testWidgets('landing page shows branding, features, and auth actions', (
    tester,
  ) async {
    var loginTaps = 0;
    var registerTaps = 0;
    var startedTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LandingPage(
          onLogin: () => loginTaps++,
          onRegister: () => registerTaps++,
          onGetStarted: () => startedTaps++,
        ),
      ),
    );

    expect(find.text('AI Memory Care'), findsWidgets);
    expect(find.text('A Smarter, More Caring Voice Assistant'), findsOneWidget);
    expect(find.text('Voice-based interaction'), findsOneWidget);
    expect(find.text('Personalized information'), findsOneWidget);
    expect(find.text('Smart reminders and appointments'), findsOneWidget);
    expect(find.text('Memory assistance'), findsOneWidget);
    expect(find.text('Face recognition'), findsOneWidget);
    expect(find.text('Caregiver support'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
    expect(loginTaps, 1);
    expect(registerTaps, 1);
    expect(startedTaps, 1);
  });

  testWidgets('login and register open the existing auth screens', (tester) async {
    await tester.pumpWidget(
      AuthScope(
        controller: AuthController(api: AuthApi(baseUrl: 'http://127.0.0.1:19999')),
        child: const MaterialApp(home: _LandingAuthHarness()),
      ),
    );

    expect(find.byType(LandingPage), findsOneWidget);
    expect(find.text('Sign in to continue'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Login').first);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LandingPage), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Register').first);
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
  });
}

class _LandingAuthHarness extends StatefulWidget {
  const _LandingAuthHarness();

  @override
  State<_LandingAuthHarness> createState() => _LandingAuthHarnessState();
}

class _LandingAuthHarnessState extends State<_LandingAuthHarness> {
  String? _view;

  @override
  Widget build(BuildContext context) {
    if (_view == 'login') {
      return LoginScreen(onBack: () => setState(() => _view = null));
    }
    if (_view == 'register') {
      return LoginScreen(
        startInRegister: true,
        onBack: () => setState(() => _view = null),
      );
    }
    return LandingPage(
      onLogin: () => setState(() => _view = 'login'),
      onRegister: () => setState(() => _view = 'register'),
      onGetStarted: () => setState(() => _view = 'register'),
    );
  }
}
