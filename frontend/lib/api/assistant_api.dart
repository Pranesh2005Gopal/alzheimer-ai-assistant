import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/care_models.dart';

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
  AssistantApi({String? baseUrl}) : baseUrl = _normalize(baseUrl ?? defaultBase());

  String baseUrl;

  static String defaultBase() {
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }

  static String _normalize(String value) {
    return value.trim().replaceFirst(RegExp(r'/$'), '');
  }

  void updateBaseUrl(String value) {
    baseUrl = _normalize(value);
  }

  Future<HealthStatus> health() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return HealthStatus.offline('Health check failed (${response.statusCode})');
      }
      return HealthStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (error) {
      return HealthStatus.offline('Cannot reach assistant at $baseUrl');
    }
  }

  Future<OverviewData> overview() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/patient/overview')).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('Overview failed (${response.statusCode})');
    }
    return OverviewData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<VoiceTurn> sendAudio(File wavFile) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/voice/turn'));
    request.files.add(
      await http.MultipartFile.fromPath('audio', wavFile.path, filename: 'speech.wav'),
    );
    return _sendMultipart(request, 'Voice turn', VoiceTurn.fromJson);
  }

  Future<VoiceTurn> sendText(String text) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/v1/text/turn'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(minutes: 10));
    if (response.statusCode != 200) {
      throw HttpException('Text turn failed (${response.statusCode}): ${response.body}');
    }
    return VoiceTurn.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<FaceRecognitionResult> recognizeFace(List<int> imageBytes) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/vision/recognize'));
    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: 'face.jpg'),
    );
    return _sendMultipart(request, 'Face recognition', FaceRecognitionResult.fromJson);
  }

  Future<FaceRecognitionResult> recognizeFromCamera() async {
    final response = await http
        .post(Uri.parse('$baseUrl/v1/vision/recognize-camera'))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw HttpException('Face recognition failed (${response.statusCode}): ${response.body}');
    }
    return FaceRecognitionResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<KnownPerson>> listPeople() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/vision/people'));
    if (response.statusCode != 200) {
      throw HttpException('People list failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((row) => KnownPerson.fromJson(row as Map<String, dynamic>)).toList();
  }

  Future<FaceRecognitionResult> registerFace({
    required List<int> imageBytes,
    required String name,
    String personId = '',
    String relationship = '',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/vision/register'));
    request.fields['name'] = name;
    request.fields['relationship'] = relationship;
    request.fields['person_id'] = personId;
    request.files.add(
      http.MultipartFile.fromBytes('image', imageBytes, filename: 'face.jpg'),
    );
    return _sendMultipart(request, 'Face registration', FaceRecognitionResult.fromJson);
  }

  Future<List<ReminderItem>> listReminders() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/reminders'));
    return _mapList(response, 'Reminders', 'reminders', ReminderItem.fromJson);
  }

  Future<ReminderItem> createReminder({
    required String title,
    required String timeIso,
    required String kind,
    String frequency = 'once',
    String? medicationName,
    String notes = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/reminders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'time_iso': timeIso,
        'kind': kind,
        'frequency': frequency,
        'medication_name': medicationName,
        'notes': notes,
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Could not create reminder (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ReminderItem.fromJson(data['reminder'] as Map<String, dynamic>);
  }

  Future<ReminderItem> completeReminder(String id) async {
    final response = await http.post(Uri.parse('$baseUrl/v1/reminders/$id/complete'));
    if (response.statusCode != 200) {
      throw HttpException('Could not complete reminder (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ReminderItem.fromJson(data['reminder'] as Map<String, dynamic>);
  }

  Future<bool> deleteReminder(String id) async {
    final response = await http.delete(Uri.parse('$baseUrl/v1/reminders/$id'));
    return response.statusCode == 200;
  }

  Future<List<AppointmentItem>> listAppointments() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/appointments'));
    return _mapList(response, 'Appointments', 'appointments', AppointmentItem.fromJson);
  }

  Future<AppointmentItem> createAppointment({
    required String doctor,
    required String dateIso,
    required String timeIso,
    String location = '',
    String purpose = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/appointments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctor': doctor,
        'date_iso': dateIso,
        'time_iso': timeIso,
        'location': location,
        'purpose': purpose,
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Could not schedule appointment (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AppointmentItem.fromJson(data['appointment'] as Map<String, dynamic>);
  }

  Future<bool> addCareNote({required String note, String category = 'observation'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/care/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'note': note, 'category': category}),
    );
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> memory() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/memory'));
    if (response.statusCode != 200) {
      throw HttpException('Memory failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> addMemoryNote(String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/memory/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode != 200) {
      throw HttpException('Could not store memory note (${response.statusCode})');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['message'] as String? ?? 'Stored.';
  }

  Future<List<ActivityItem>> activity({int limit = 50}) async {
    final response = await http.get(Uri.parse('$baseUrl/v1/activity?limit=$limit'));
    return _mapList(response, 'Activity', 'events', ActivityItem.fromJson);
  }

  Future<List<ConversationTurnItem>> conversation() async {
    final response = await http.get(Uri.parse('$baseUrl/v1/conversation'));
    return _mapList(response, 'Conversation', 'turns', ConversationTurnItem.fromJson);
  }

  Future<String> setPreferredName(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/profile/name'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'preferred_name': name}),
    );
    if (response.statusCode != 200) {
      throw HttpException('Could not update name (${response.statusCode})');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['preferred_name'] as String? ?? name;
  }

  Future<List<T>> _mapList<T>(
    http.Response response,
    String label,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    if (response.statusCode != 200) {
      throw HttpException('$label failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data[key] as List<dynamic>? ?? const [];
    return rows.map((row) => parse(row as Map<String, dynamic>)).toList();
  }

  Future<T> _sendMultipart<T>(
    http.MultipartRequest request,
    String label,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 10));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw HttpException('$label failed (${streamed.statusCode}): $body');
      }
      return parse(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }
}

class KnownPerson {
  KnownPerson({
    required this.id,
    required this.name,
    required this.relationship,
    required this.hasFaceProfile,
  });

  final String id;
  final String name;
  final String relationship;
  final bool hasFaceProfile;

  factory KnownPerson.fromJson(Map<String, dynamic> json) {
    return KnownPerson(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      hasFaceProfile: json['has_face_profile'] as bool? ?? false,
    );
  }
}

class FaceRecognitionResult {
  FaceRecognitionResult({
    required this.recognized,
    required this.personName,
    required this.relationship,
    required this.notes,
    required this.score,
    required this.message,
    required this.audioBytes,
  });

  final bool recognized;
  final String personName;
  final String relationship;
  final String notes;
  final double score;
  final String message;
  final Uint8List audioBytes;

  factory FaceRecognitionResult.fromJson(Map<String, dynamic> json) {
    final encoded = json['audio_wav_base64'] as String? ?? '';
    final person = json['person'] as Map<String, dynamic>?;
    return FaceRecognitionResult(
      recognized: json['recognized'] as bool? ?? json['status'] == 'registered',
      personName: person?['name'] as String? ?? 'Unknown',
      relationship: person?['relationship'] as String? ?? '',
      notes: person?['notes'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] as String? ?? '',
      audioBytes: encoded.isEmpty ? Uint8List(0) : base64Decode(encoded),
    );
  }
}
