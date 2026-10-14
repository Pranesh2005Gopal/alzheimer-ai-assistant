/// Auth API client – communicates with /v1/auth and /v1/profile endpoints.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/auth_models.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AuthApi {
  AuthApi({required this.baseUrl});

  final String baseUrl;
  String? _token;
  String? _privateGrant;
  DateTime? _grantExpiry;

  String? get token => _token;
  bool get isLoggedIn => _token != null;

  void setToken(String? token) {
    _token = token;
  }

  void setPrivateGrant(String grant) {
    _privateGrant = grant;
    _grantExpiry = DateTime.now().add(const Duration(minutes: 19));
  }

  String? get validPrivateGrant {
    if (_privateGrant == null) return null;
    if (_grantExpiry == null || DateTime.now().isAfter(_grantExpiry!)) {
      _privateGrant = null;
      return null;
    }
    return _privateGrant;
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  static Future<File> _tokenFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/auth_token.txt');
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      final f = await _tokenFile();
      await f.writeAsString(token);
    } catch (_) {}
  }

  Future<bool> loadSavedToken() async {
    try {
      final f = await _tokenFile();
      if (await f.exists()) {
        final t = (await f.readAsString()).trim();
        if (t.isNotEmpty) {
          _token = t;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> clearToken() async {
    _token = null;
    _privateGrant = null;
    try {
      final f = await _tokenFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handle(resp);
    } on SocketException {
      throw const AuthApiException('Cannot reach server. Check your connection.');
    }
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (query != null) uri = uri.replace(queryParameters: query);
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handle(resp);
    } on SocketException {
      throw const AuthApiException('Cannot reach server. Check your connection.');
    }
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body, {Map<String, String>? query}) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (query != null) uri = uri.replace(queryParameters: query);
      final resp = await http
          .patch(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handle(resp);
    } on SocketException {
      throw const AuthApiException('Cannot reach server. Check your connection.');
    }
  }

  Map<String, dynamic> _handle(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    String detail = resp.body;
    try {
      final parsed = jsonDecode(resp.body) as Map<String, dynamic>;
      detail = parsed['detail'] as String? ?? detail;
    } catch (_) {}
    throw AuthApiException(detail, statusCode: resp.statusCode);
  }

  // ---------------------------------------------------------------------------
  // Auth endpoints
  // ---------------------------------------------------------------------------

  Future<({AuthUser user, String token})> register({
    required String email,
    required String password,
    required String fullName,
    String role = 'patient',
  }) async {
    final data = await _post('/v1/auth/register', {
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
    });
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final tok = data['token'] as String;
    await saveToken(tok);
    return (user: user, token: tok);
  }

  Future<({AuthUser user, String token})> login({
    required String email,
    required String password,
  }) async {
    final data = await _post('/v1/auth/login', {
      'email': email,
      'password': password,
    });
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    final tok = data['token'] as String;
    await saveToken(tok);
    return (user: user, token: tok);
  }

  Future<void> logout() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/v1/auth/logout2'), headers: _headers)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    await clearToken();
  }

  Future<AuthUser> getMe() async {
    final data = await _get('/v1/auth/me');
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> setPin(String pin) async {
    await _post('/v1/auth/set-pin', {'pin': pin});
  }

  /// Returns a private_grant on success, throws on failure.
  Future<String> verifyPin(String pin) async {
    final data = await _post('/v1/auth/verify-pin', {'pin': pin});
    final grant = data['private_grant'] as String;
    setPrivateGrant(grant);
    return grant;
  }

  Future<void> changePassword(String oldPwd, String newPwd) async {
    await _post('/v1/auth/change-password', {
      'old_password': oldPwd,
      'new_password': newPwd,
    });
  }

  // ---------------------------------------------------------------------------
  // Profile endpoints
  // ---------------------------------------------------------------------------

  Future<UserProfile> getProfile() async {
    final data = await _get('/v1/profile');
    return UserProfile.fromJson(data['profile'] as Map<String, dynamic>? ?? {});
  }

  Future<UserProfile> updateProfile(Map<String, dynamic> changes) async {
    final data = await _patch('/v1/profile', changes);
    return UserProfile.fromJson(data['profile'] as Map<String, dynamic>? ?? {});
  }

  // ---------------------------------------------------------------------------
  // Private information endpoints
  // ---------------------------------------------------------------------------

  Future<PrivateInfo> getPrivateInfo({required String grant}) async {
    final data = await _get('/v1/private', query: {'private_grant': grant});
    return PrivateInfo.fromJson(data['private'] as Map<String, dynamic>? ?? {});
  }

  Future<void> updatePrivateInfo({
    required Map<String, dynamic> changes,
    required String grant,
  }) async {
    await _patch('/v1/private', changes, query: {'private_grant': grant});
  }

  // ---------------------------------------------------------------------------
  // Caregiver permissions
  // ---------------------------------------------------------------------------

  Future<void> setCaregiverPermissions(String caregiverId, List<String> permissions) async {
    await _post('/v1/profile/caregiver-permissions', {
      'caregiver_id': caregiverId,
      'permissions': permissions,
    });
  }

  Future<List<Map<String, dynamic>>> getAssignedPatients() async {
    final data = await _get('/v1/caregiver/assigned-patients');
    final list = data['patients'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<UserProfile> getCaregiverPatientProfile(String patientId) async {
    final data = await _get('/v1/caregiver/$patientId/profile');
    return UserProfile.fromJson(data['profile'] as Map<String, dynamic>? ?? {});
  }

  Future<PrivateInfo> getCaregiverPatientPrivate(String patientId, {required String grant}) async {
    final data = await _get('/v1/caregiver/$patientId/private', query: {'private_grant': grant});
    return PrivateInfo.fromJson(data['private'] as Map<String, dynamic>? ?? {});
  }

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final data = await _get('/v1/auth/audit');
    final list = data['audit_logs'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
