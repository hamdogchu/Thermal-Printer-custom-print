import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);
  static const String _prefsKey = 'app_logs';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLogs = prefs.getStringList(_prefsKey) ?? [];
    logsNotifier.value = savedLogs;
  }

  Future<void> _saveLogs(List<String> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, logs);
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.split('.').first;
    final logMessage = '[$timestamp] $message';
    debugPrint(logMessage);
    
    final currentLogs = List<String>.from(logsNotifier.value);
    currentLogs.add(logMessage);
    logsNotifier.value = currentLogs;
    _saveLogs(currentLogs);
  }

  void logError(String message, [dynamic error, StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.split('.').first;
    String logMessage = '[$timestamp] ERROR: $message';
    if (error != null) {
      logMessage += '\nException: $error';
    }
    if (stackTrace != null) {
      logMessage += '\nStackTrace: $stackTrace';
    }
    debugPrint(logMessage);
    
    final currentLogs = List<String>.from(logsNotifier.value);
    currentLogs.add(logMessage);
    logsNotifier.value = currentLogs;
    _saveLogs(currentLogs);
  }
  
  void clear() {
    logsNotifier.value = [];
    _saveLogs([]);
  }
}
