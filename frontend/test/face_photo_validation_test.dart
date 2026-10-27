import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_assistant/api/assistant_api.dart';

void main() {
  test('gallery photo validation preserves the server feedback', () async {
    final api = AssistantApi(
      baseUrl: 'http://test.invalid',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/vision/validate');
        return http.Response(jsonEncode({
          'usable': false,
          'quality_feedback': 'Keep both eyes visible and look at the camera.',
          'landmarks': {},
          'image_width': 640,
          'image_height': 480,
        }), 200);
      }),
    );

    final result = await api.validateFacePhoto(List<int>.filled(128, 7));
    expect(result.hasUsableFace, isFalse);
    expect(result.qualityFeedback, contains('eyes visible'));
    expect(result.imageWidth, 640);
  });
}
