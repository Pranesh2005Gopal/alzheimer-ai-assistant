/// Auth, Profile, and Private Information models for the Flutter frontend.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// User / Auth
// ---------------------------------------------------------------------------

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.profile,
    required this.hasPin,
    this.caregiverPermissions = const {},
  });

  final String id;
  final String email;
  final String role;
  final UserProfile profile;
  final bool hasPin;
  final Map<String, List<String>> caregiverPermissions;

  bool get isPatient => role == 'patient' || role == 'admin';
  bool get isCaregiver => role == 'caregiver' || role == 'admin';

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final perms = json['caregiver_permissions'] as Map<String, dynamic>? ?? {};
    return AuthUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'patient',
      profile: UserProfile.fromJson(json['profile'] as Map<String, dynamic>? ?? {}),
      hasPin: json['has_pin'] as bool? ?? false,
      caregiverPermissions: perms.map(
        (k, v) => MapEntry(k, (v as List).cast<String>()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User Profile
// ---------------------------------------------------------------------------

class UserProfile {
  const UserProfile({
    this.fullName = '',
    this.preferredName = '',
    this.avatarUrl = '',
    this.dateOfBirth = '',
    this.language = 'en',
    this.voicePreference = 'female',
    this.hobbies = const [],
    this.dailyRoutine = const [],
    this.importantDates = const [],
    this.personalMemories = const [],
  });

  final String fullName;
  final String preferredName;
  final String avatarUrl;
  final String dateOfBirth;
  final String language;
  final String voicePreference;
  final List<String> hobbies;
  final List<String> dailyRoutine;
  final List<Map<String, dynamic>> importantDates;
  final List<String> personalMemories;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String> asList(dynamic v) {
      if (v is List) return v.whereType<String>().toList();
      return [];
    }

    List<Map<String, dynamic>> asMaps(dynamic v) {
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    }

    return UserProfile(
      fullName: json['full_name'] as String? ?? '',
      preferredName: json['preferred_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      dateOfBirth: json['date_of_birth'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      voicePreference: json['voice_preference'] as String? ?? 'female',
      hobbies: asList(json['hobbies']),
      dailyRoutine: asList(json['daily_routine']),
      importantDates: asMaps(json['important_dates']),
      personalMemories: asList(json['personal_memories']),
    );
  }

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'preferred_name': preferredName,
        'avatar_url': avatarUrl,
        'date_of_birth': dateOfBirth,
        'language': language,
        'voice_preference': voicePreference,
        'hobbies': hobbies,
        'daily_routine': dailyRoutine,
        'important_dates': importantDates,
        'personal_memories': personalMemories,
      };

  UserProfile copyWith({
    String? fullName,
    String? preferredName,
    String? avatarUrl,
    String? dateOfBirth,
    String? language,
    String? voicePreference,
    List<String>? hobbies,
    List<String>? dailyRoutine,
    List<Map<String, dynamic>>? importantDates,
    List<String>? personalMemories,
  }) =>
      UserProfile(
        fullName: fullName ?? this.fullName,
        preferredName: preferredName ?? this.preferredName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        language: language ?? this.language,
        voicePreference: voicePreference ?? this.voicePreference,
        hobbies: hobbies ?? this.hobbies,
        dailyRoutine: dailyRoutine ?? this.dailyRoutine,
        importantDates: importantDates ?? this.importantDates,
        personalMemories: personalMemories ?? this.personalMemories,
      );
}

// ---------------------------------------------------------------------------
// Private Information
// ---------------------------------------------------------------------------

class PrivateInfo {
  const PrivateInfo({
    this.medicalConditions = const [],
    this.allergies = const [],
    this.medications = const [],
    this.emergencyContacts = const [],
    this.doctorDetails = const {},
    this.address = '',
    this.caregiverInfo = const {},
  });

  final List<String> medicalConditions;
  final List<String> allergies;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> emergencyContacts;
  final Map<String, dynamic> doctorDetails;
  final String address;
  final Map<String, dynamic> caregiverInfo;

  factory PrivateInfo.fromJson(Map<String, dynamic> json) {
    List<String> asList(dynamic v) {
      if (v is List) return v.whereType<String>().toList();
      return [];
    }

    List<Map<String, dynamic>> asMaps(dynamic v) {
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    }

    Map<String, dynamic> asMap(dynamic v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      return {};
    }

    return PrivateInfo(
      medicalConditions: asList(json['medical_conditions']),
      allergies: asList(json['allergies']),
      medications: asMaps(json['medications']),
      emergencyContacts: asMaps(json['emergency_contacts']),
      doctorDetails: asMap(json['doctor_details']),
      address: json['address'] as String? ?? '',
      caregiverInfo: asMap(json['caregiver_info']),
    );
  }

  Map<String, dynamic> toJson() => {
        'medical_conditions': medicalConditions,
        'allergies': allergies,
        'medications': medications,
        'emergency_contacts': emergencyContacts,
        'doctor_details': doctorDetails,
        'address': address,
        'caregiver_info': caregiverInfo,
      };
}
