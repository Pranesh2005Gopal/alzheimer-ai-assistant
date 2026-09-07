import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class VoiceTurn {
  VoiceTurn({
    required this.transcript,
    required this.intent,
    required this.replyText,
    required this.status,
    required this.audioBytes,
  });

  final String transcript;
  final String intent;
  final String replyText;
  final String status;
  final Uint8List audioBytes;

  factory VoiceTurn.fromJson(Map<String, dynamic> json) {
    final encoded = json['audio_wav_base64'] as String? ?? '';
    return VoiceTurn(
      transcript: json['transcript'] as String? ?? '',
      intent: json['intent'] as String? ?? 'UNKNOWN',
      replyText: json['reply_text'] as String? ?? '',
      status: json['status'] as String? ?? 'ok',
      audioBytes: encoded.isEmpty ? Uint8List(0) : base64Decode(encoded),
    );
  }
}

class AssistantApi {
  AssistantApi({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBase();

  final String baseUrl;

  static String _defaultBase() {
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }

  Future<Map<String, dynamic>> overview() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/patient/overview'));
    if (response.statusCode != 200) {
      throw HttpException('Overview failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<VoiceTurn> sendAudio(File wavFile) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/voice/turn'));
    request.files.add(await http.MultipartFile.fromPath('audio', wavFile.path));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw HttpException('Voice turn failed (${streamed.statusCode}): $body');
    }
    return VoiceTurn.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}
