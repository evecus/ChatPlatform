// lib/config.dart
// Server address is configured at runtime by the user — no hardcoded URLs.

import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  static const _keyServer = 'server_address';

  /// Raw address as entered by the user, e.g. "192.168.1.10:8080" or "chat.example.com"
  static String _address = '';

  static String get address => _address;

  /// Whether a server address has been saved
  static bool get isConfigured => _address.isNotEmpty;

  /// HTTP(S) base URL, e.g. "http://192.168.1.10:8080"
  static String get baseUrl {
    final addr = _address.trim();
    if (addr.startsWith('http://') || addr.startsWith('https://')) {
      return addr.replaceAll(RegExp(r'/$'), '');
    }
    return 'http://$addr';
  }

  /// WebSocket URL derived from baseUrl
  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https://')) {
      return base.replaceFirst('https://', 'wss://') + '/ws';
    }
    return base.replaceFirst('http://', 'ws://') + '/ws';
  }

  /// Load saved address from SharedPreferences
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _address = prefs.getString(_keyServer) ?? '';
  }

  /// Save address and update in-memory value
  static Future<void> save(String addr) async {
    _address = addr.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServer, _address);
  }

  /// Clear saved address (e.g. when switching servers)
  static Future<void> clear() async {
    _address = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyServer);
  }
}
