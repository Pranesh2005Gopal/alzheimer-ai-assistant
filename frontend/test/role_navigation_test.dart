import 'package:flutter_test/flutter_test.dart';
import 'package:patient_assistant/screens/app_shell.dart';

void main() {
  test('Vision is patient-only navigation', () {
    expect(
      navigationLabelsForRole(isCaregiver: true),
      isNot(contains('Vision')),
    );
    expect(navigationLabelsForRole(isCaregiver: false), contains('Faces'));
  });
}
