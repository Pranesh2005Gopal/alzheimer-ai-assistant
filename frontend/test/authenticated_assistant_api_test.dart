import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_assistant/api/assistant_api.dart';
import 'package:patient_assistant/api/auth_api.dart';

void main() {
  test(
    'login token is used for text turns and the protected overview',
    () async {
      final protectedPaths = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'patient-test',
                'email': 'patient@example.test',
                'role': 'patient',
                'profile': {},
                'has_pin': false,
                'caregiver_permissions': {},
              },
              'token': 'test-session-token',
            }),
            200,
          );
        }

        expect(request.headers['authorization'], 'Bearer test-session-token');
        protectedPaths.add(request.url.path);
        if (request.url.path == '/v1/text/turn') {
          expect(jsonDecode(request.body), {'text': 'How am I doing?'});
          return http.Response(
            jsonEncode({
              'transcript': 'How am I doing?',
              'intent': 'GENERAL_CONVERSATION',
              'reply_text': 'You are doing well.',
              'status': 'ok',
              'audio_wav_base64': '',
            }),
            200,
          );
        }
        if (request.url.path == '/v1/voice/turn') {
          return http.Response(
            jsonEncode({
              'transcript': 'Hello',
              'intent': 'GENERAL_CONVERSATION',
              'reply_text': 'Hello back.',
              'status': 'ok',
              'audio_wav_base64': '',
            }),
            200,
          );
        }
        if (request.url.path == '/v1/patient/overview') {
          return http.Response(
            jsonEncode({
              'greeting': 'Hello',
              'patient_name': 'Patient',
              'caregiver_name': '',
              'date_label': '',
              'time_label': '',
              'memory': {},
              'reminders': [],
              'appointments': [],
              'family': [],
              'recent_activity': [],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      final auth = AuthApi(baseUrl: 'http://test.invalid', client: client);
      final assistant = AssistantApi(
        baseUrl: 'http://test.invalid',
        client: client,
        tokenProvider: () => auth.token,
      );

      await auth.login(
        email: 'patient@example.test',
        password: 'not-a-real-password',
      );
      await assistant.sendText('How am I doing?');
      await assistant.sendAudioBytes([0, 1, 2]);
      await assistant.overview();

      expect(protectedPaths, [
        '/v1/text/turn',
        '/v1/voice/turn',
        '/v1/patient/overview',
      ]);
    },
  );

  test(
    'a missing token blocks protected requests before they are sent',
    () async {
      var wasCalled = false;
      final assistant = AssistantApi(
        baseUrl: 'http://test.invalid',
        tokenProvider: () => null,
        client: MockClient((_) async {
          wasCalled = true;
          return http.Response('', 500);
        }),
      );

      await expectLater(
        assistant.sendText('Hello'),
        throwsA(isA<HttpException>()),
      );
      expect(wasCalled, isFalse);
    },
  );
}
