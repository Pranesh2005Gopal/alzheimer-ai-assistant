import 'dart:convert';
import 'dart:typed_data';

enum AssistantLink { initializing, ready, degraded, offline, error }

enum VoicePhase { idle, listening, processing, speaking, error }

class HealthStatus {
  HealthStatus({
    required this.reachable,
    required this.status,
    required this.patient,
    required this.services,
    this.message = '',
  });

  final bool reachable;
  final String status;
  final String patient;
  final Map<String, String> services;
  final String message;

  AssistantLink get link {
    if (!reachable) {
      return AssistantLink.offline;
    }
    if (status == 'ready' && (services['api'] == 'online')) {
      if (services['llm'] == 'unavailable') {
        return AssistantLink.degraded;
      }
      return AssistantLink.ready;
    }
    if (status == 'degraded') {
      return AssistantLink.degraded;
    }
    return AssistantLink.error;
  }

  factory HealthStatus.offline(String message) {
    return HealthStatus(
      reachable: false,
      status: 'offline',
      patient: '',
      services: const {},
      message: message,
    );
  }

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['services'];
    final services = <String, String>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        services['$key'] = '$value';
      });
    }
    return HealthStatus(
      reachable: json['ok'] == true,
      status: json['status'] as String? ?? (json['ok'] == true ? 'ready' : 'error'),
      patient: json['patient'] as String? ?? '',
      services: services,
    );
  }
}

class ChatLine {
  ChatLine({required this.fromYou, required this.text, this.audioBytes, DateTime? at})
      : at = at ?? DateTime.now();

  final bool fromYou;
  final String text;
  final List<int>? audioBytes;
  final DateTime at;
}

class ReminderItem {
  ReminderItem({
    required this.id,
    required this.title,
    required this.time,
    required this.kind,
    required this.status,
    this.frequency = '',
    this.medicationName,
    this.notes = '',
    this.message,
    this.needsSpeech = false,
    this.audioBytes,
  });

  final String id;
  final String title;
  final String time;
  final String kind;
  final String status;
  final String frequency;
  final String? medicationName;
  final String notes;
  final String? message;
  final bool needsSpeech;
  final Uint8List? audioBytes;

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      time: json['time'] as String? ?? '',
      kind: json['kind'] as String? ?? 'general',
      status: json['status'] as String? ?? 'pending',
      frequency: json['frequency'] as String? ?? '',
      medicationName: json['medication_name'] as String?,
      notes: json['notes'] as String? ?? '',
      message: json['message'] as String?,
      needsSpeech: json['needs_speech'] as bool? ?? false,
      audioBytes: _decodeAudio(json['audio_wav_base64'] as String?),
    );
  }

  String get kindLabel {
    switch (kind) {
      case 'medication':
        return 'Medicine';
      case 'appointment':
        return 'Appointment';
      case 'daily_routine':
        return 'Daily routine';
      default:
        return 'Reminder';
    }
  }
}

Uint8List? _decodeAudio(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return null;
  }
  return base64Decode(encoded);
}

class AppointmentItem {
  AppointmentItem({
    required this.id,
    required this.doctor,
    required this.date,
    required this.time,
    this.location = '',
    this.purpose = '',
  });

  final String id;
  final String doctor;
  final String date;
  final String time;
  final String location;
  final String purpose;

  factory AppointmentItem.fromJson(Map<String, dynamic> json) {
    return AppointmentItem(
      id: json['id'] as String? ?? '',
      doctor: json['doctor'] as String? ?? '',
      date: json['date'] as String? ?? '',
      time: json['time'] as String? ?? '',
      location: json['location'] as String? ?? '',
      purpose: json['purpose'] as String? ?? '',
    );
  }
}

class PersonItem {
  PersonItem({
    required this.id,
    required this.name,
    required this.relationship,
    this.notes = '',
    this.hasFaceProfile = false,
  });

  final String id;
  final String name;
  final String relationship;
  final String notes;
  final bool hasFaceProfile;

  factory PersonItem.fromJson(Map<String, dynamic> json) {
    return PersonItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      hasFaceProfile: json['has_face_profile'] as bool? ?? false,
    );
  }
}

class MemoryDate {
  MemoryDate({required this.title, required this.date, required this.kind, this.notes = ''});

  final String title;
  final String date;
  final String kind;
  final String notes;

  factory MemoryDate.fromJson(Map<String, dynamic> json) {
    return MemoryDate(
      title: json['title'] as String? ?? '',
      date: json['date'] as String? ?? json['date_iso'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

class PreferenceItem {
  PreferenceItem({required this.subject, required this.key, required this.value});

  final String subject;
  final String key;
  final String value;

  factory PreferenceItem.fromJson(Map<String, dynamic> json) {
    return PreferenceItem(
      subject: json['subject'] as String? ?? '',
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
    );
  }
}

class ActivityItem {
  ActivityItem({required this.kind, required this.summary, required this.time});

  final String kind;
  final String summary;
  final String time;

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      kind: json['kind'] as String? ?? 'event',
      summary: json['summary'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }
}

class ConversationTurnItem {
  ConversationTurnItem({required this.role, required this.text, required this.time, this.intent});

  final String role;
  final String text;
  final String time;
  final String? intent;

  factory ConversationTurnItem.fromJson(Map<String, dynamic> json) {
    return ConversationTurnItem(
      role: json['role'] as String? ?? '',
      text: json['text'] as String? ?? '',
      time: json['time'] as String? ?? '',
      intent: json['intent'] as String?,
    );
  }
}

class FaceEvent {
  FaceEvent({
    required this.recognized,
    required this.message,
    required this.personName,
    required this.at,
  });

  final bool recognized;
  final String message;
  final String personName;
  final DateTime at;
}

class OverviewData {
  OverviewData({
    required this.greeting,
    required this.patientName,
    required this.caregiverName,
    required this.dateLabel,
    required this.timeLabel,
    required this.reminders,
    required this.appointments,
    required this.family,
    required this.importantDates,
    required this.preferences,
    required this.activity,
    this.nextReminder,
    this.activeReminder,
    this.nextAppointment,
  });

  final String greeting;
  final String patientName;
  final String caregiverName;
  final String dateLabel;
  final String timeLabel;
  final ReminderItem? nextReminder;
  final ReminderItem? activeReminder;
  final AppointmentItem? nextAppointment;
  final List<ReminderItem> reminders;
  final List<AppointmentItem> appointments;
  final List<PersonItem> family;
  final List<MemoryDate> importantDates;
  final List<PreferenceItem> preferences;
  final List<ActivityItem> activity;

  factory OverviewData.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return null;
    }

    List<Map<String, dynamic>> asMaps(dynamic value) {
      if (value is! List) {
        return const [];
      }
      return value.map((row) => asMap(row)).whereType<Map<String, dynamic>>().toList();
    }

    final memory = asMap(json['memory']) ?? {};
    final nextReminder = asMap(json['next_reminder']);
    final active = asMap(json['active_reminder']);
    final nextAppointment = asMap(json['next_appointment']);
    return OverviewData(
      greeting: json['greeting'] as String? ?? 'Hello',
      patientName: json['patient_name'] as String? ?? '',
      caregiverName: json['caregiver_name'] as String? ?? '',
      dateLabel: json['date_label'] as String? ?? '',
      timeLabel: json['time_label'] as String? ?? '',
      nextReminder: nextReminder == null ? null : ReminderItem.fromJson(nextReminder),
      activeReminder: active == null ? null : ReminderItem.fromJson(active),
      nextAppointment: nextAppointment == null ? null : AppointmentItem.fromJson(nextAppointment),
      reminders: asMaps(json['reminders']).map(ReminderItem.fromJson).toList(),
      appointments: asMaps(json['appointments']).map(AppointmentItem.fromJson).toList(),
      family: asMaps(json['family']).map(PersonItem.fromJson).toList(),
      importantDates: asMaps(memory['important_dates']).map(MemoryDate.fromJson).toList(),
      preferences: asMaps(memory['preferences']).map(PreferenceItem.fromJson).toList(),
      activity: asMaps(json['recent_activity']).map(ActivityItem.fromJson).toList(),
    );
  }
}
