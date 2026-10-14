import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../api/assistant_api.dart';

class AppSettings {
  AppSettings({
    required this.apiBase,
    this.themeMode = ThemeMode.system,
  });

  String apiBase;
  ThemeMode themeMode;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/assistant_settings.json');
  }

  static Future<AppSettings> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) {
        return AppSettings(apiBase: AssistantApi.defaultBase());
      }
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSettings(
        apiBase: data['api_base'] as String? ?? AssistantApi.defaultBase(),
        themeMode: _themeFrom(data['theme_mode'] as String?),
      );
    } catch (_) {
      return AppSettings(apiBase: AssistantApi.defaultBase());
    }
  }

  Future<void> save() async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode({
        'api_base': apiBase,
        'theme_mode': themeMode.name,
      }),
    );
  }

  static ThemeMode _themeFrom(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
