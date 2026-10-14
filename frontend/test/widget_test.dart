import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patient_assistant/main.dart';
import 'package:patient_assistant/settings/app_settings.dart';
import 'package:patient_assistant/state/assistant_controller.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Use a non-existent server; controller.start() will fail gracefully.
    final settings = AppSettings(apiBase: 'http://127.0.0.1:19999');
    final controller = AssistantController(settings: settings);

    await tester.pumpWidget(PatientAssistantApp(controller: controller));

    // One pump — enough to verify the widget tree builds successfully.
    await tester.pump(Duration.zero);

    expect(find.byType(MaterialApp), findsOneWidget);

    // Do NOT call controller.dispose() here — the widget's State.dispose() handles it.
  });
}
