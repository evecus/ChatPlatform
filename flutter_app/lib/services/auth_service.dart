import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/models.dart';

class AuthService {
  static Dio _dio = Dio();
  static User? currentUser;

  static Future<void> init() async {
    // Load server address first
    await ServerConfig.load();

    if (!ServerConfig.isConfigured) return;

    _rebuildDio();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
      try {
        final res = await _dio.get('/api/auth/me');
        currentUser = User.fromJson(res.data);
      } catch (_) {
        await logout();
      }
    }
  }

  /// Call this after ServerConfig.save() to point Dio at the new server
  static void _rebuildDio() {
    final savedToken = _dio.options.headers['Authorization'];
    _dio = Dio(BaseOptions(baseUrl: ServerConfig.baseUrl));
    if (savedToken != null) {
      _dio.options.headers['Authorization'] = savedToken;
    }
  }

  static String? get token => _dio.options.headers['Authorization']
      ?.toString()
      .replaceFirst('Bearer ', '');

  static Dio get dio => _dio;

  static Future<User> login(String username, String password) async {
    _rebuildDio();
    final res = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    final t = res.data['token'] as String;
    await _saveToken(t);
    currentUser = User.fromJson(res.data['user']);
    return currentUser!;
  }

  static Future<User> register(String username, String password, String code) async {
    _rebuildDio();
    final res = await _dio.post('/api/auth/register', data: {
      'username': username,
      'password': password,
      'invite_code': code,
    });
    final t = res.data['token'] as String;
    await _saveToken(t);
    currentUser = User.fromJson(res.data['user']);
    return currentUser!;
  }

  static Future<void> _saveToken(String t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', t);
    _dio.options.headers['Authorization'] = 'Bearer $t';
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _dio.options.headers.remove('Authorization');
    currentUser = null;
  }

  static bool get isLoggedIn => currentUser != null && token != null;

  /// 修改用户名/密码成功后，用服务器返回的新 token 和用户信息更新本地状态
  static Future<void> applyUpdatedProfile(String newToken, Map<String, dynamic> userJson) async {
    await _saveToken(newToken);
    currentUser = User.fromJson(userJson);
  }
}
