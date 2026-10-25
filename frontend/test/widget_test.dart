import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patient_assistant/api/auth_api.dart';
import 'package:patient_assistant/main.dart';
import 'package:patient_assistant/settings/app_settings.dart';
import 'package:patient_assistant/state/assistant_controller.dart';
import 'package:patient_assistant/state/auth_controller.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Use a non-existent server; controller.start() will fail gracefully.
    final settings = AppSettings(apiBase: 'http://127.0.0.1:19999');
    final controller = AssistantController(settings: settings);
    final authApi = AuthApi(baseUrl: settings.apiBase);
    final authController = AuthController(api: authApi);

    await tester.pumpWidget(PatientAssistantApp(
      controller: controller,
      authController: authController,
      authApi: authApi,
    ));

    // One pump — enough to verify the widget tree builds successfully.
    await tester.pump(Duration.zero);

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MaterialApp &&
            widget.title == 'AI Memory Care — Personalized Voice Assistant',
      ),
      findsOneWidget,
    );

    // Do NOT call controller.dispose() here — the widget's State.dispose() handles it.
  });
}
