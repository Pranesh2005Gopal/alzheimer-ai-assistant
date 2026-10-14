/// AuthController – manages authentication state and exposes auth methods
/// to the widget tree via an InheritedWidget.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../models/auth_models.dart';

enum AuthState { loading, unauthenticated, authenticated }

class AuthController extends ChangeNotifier {
  AuthController({required AuthApi api}) : _api = api;

  final AuthApi _api;

  AuthState _state = AuthState.loading;
  AuthUser? _user;
  String? _error;
  bool _busy = false;

  AuthState get state => _state;
  AuthUser? get user => _user;
  String? get error => _error;
  bool get busy => _busy;
  bool get isAuthenticated => _state == AuthState.authenticated && _user != null;
  AuthApi get api => _api;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    _busy = true;
    notifyListeners();
    final hadToken = await _api.loadSavedToken();
    if (hadToken) {
      try {
        final me = await _api.getMe();
        _user = me;
        _state = AuthState.authenticated;
      } catch (_) {
        await _api.clearToken();
        _state = AuthState.unauthenticated;
      }
    } else {
      _state = AuthState.unauthenticated;
    }
    _busy = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auth actions
  // ---------------------------------------------------------------------------

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String role = 'patient',
  }) async {
    return _run(() async {
      final result = await _api.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
      );
      _user = result.user;
      _state = AuthState.authenticated;
    });
  }

  Future<bool> login({required String email, required String password}) async {
    return _run(() async {
      final result = await _api.login(email: email, password: password);
      _user = result.user;
      _state = AuthState.authenticated;
    });
  }

  Future<void> logout() async {
    _busy = true;
    notifyListeners();
    await _api.logout();
    _user = null;
    _state = AuthState.unauthenticated;
    _busy = false;
    notifyListeners();
  }

  Future<bool> setPin(String pin) async {
    return _run(() async {
      await _api.setPin(pin);
      if (_user != null) {
        // Refresh user to reflect has_pin = true
        final me = await _api.getMe();
        _user = me;
      }
    });
  }

  Future<String?> verifyPin(String pin) async {
    _error = null;
    _busy = true;
    notifyListeners();
    try {
      final grant = await _api.verifyPin(pin);
      _busy = false;
      notifyListeners();
      return grant;
    } on AuthApiException catch (e) {
      _error = e.message;
      _busy = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = e.toString();
      _busy = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> changes) async {
    return _run(() async {
      final profile = await _api.updateProfile(changes);
      if (_user != null) {
        _user = AuthUser(
          id: _user!.id,
          email: _user!.email,
          role: _user!.role,
          profile: profile,
          hasPin: _user!.hasPin,
          caregiverPermissions: _user!.caregiverPermissions,
        );
      }
    });
  }

  Future<bool> changePassword(String oldPwd, String newPwd) async {
    return _run(() => _api.changePassword(oldPwd, newPwd));
  }

  // ---------------------------------------------------------------------------
  // Internal helper
  // ---------------------------------------------------------------------------

  Future<bool> _run(Future<void> Function() action) async {
    _error = null;
    _busy = true;
    notifyListeners();
    try {
      await action();
      _busy = false;
      notifyListeners();
      return true;
    } on AuthApiException catch (e) {
      _error = e.message;
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _busy = false;
      notifyListeners();
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// InheritedWidget wrapper
// ---------------------------------------------------------------------------

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({super.key, required AuthController controller, required super.child})
      : super(notifier: controller);

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in widget tree');
    return scope!.notifier!;
  }
}
