import 'package:flutter_test/flutter_test.dart';

import 'package:patient_assistant/main.dart';

void main() {
  testWidgets('Patient home shows TALK control', (WidgetTester tester) async {
    await tester.pumpWidget(const PatientAssistantApp());
    await tester.pump();
    expect(find.text('TALK'), findsOneWidget);
  });
}
