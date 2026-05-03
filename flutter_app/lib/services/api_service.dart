import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import '../models/models.dart';
import 'auth_service.dart';

class ApiService {
  static Options get _auth => Options(
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );

  static Dio get _dio => AuthService.dio;

  // ── Files ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadFile(File file) async {
    final name = p.basename(file.path);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });
    final res = await _dio.post('/api/files/upload', data: form, options: _auth);
    return res.data;
  }

  static Future<String> downloadFile(String fileId, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = p.join(dir.path, fileName);
    await _dio.download(
      '/api/files/$fileId',
      savePath,
      options: _auth,
    );
    return savePath;
  }

  static String fileUrl(String fileId) => '${ServerConfig.baseUrl}/api/files/$fileId';

  // ── Profile ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> updateProfile({
    String? newUsername,
    String? newPassword,
    required String oldPassword,
  }) async {
    final res = await _dio.put('/api/auth/profile',
      data: {
        if (newUsername != null && newUsername.isNotEmpty) 'new_username': newUsername,
        if (newPassword != null && newPassword.isNotEmpty) 'new_password': newPassword,
        'old_password': oldPassword,
      },
      options: _auth,
    );
    return res.data;
  }

  // ── Admin ──────────────────────────────────────────────────────────────

  static Future<List<AdminUser>> adminGetUsers() async {
    final res = await _dio.get('/api/admin/users', options: _auth);
    return (res.data as List).map((u) => AdminUser.fromJson(u)).toList();
  }

  static Future<void> adminBanUser(int id) async {
    await _dio.post('/api/admin/users/$id/ban', options: _auth);
  }

  static Future<void> adminUnbanUser(int id) async {
    await _dio.post('/api/admin/users/$id/unban', options: _auth);
  }

  static Future<void> adminKickUser(int id) async {
    await _dio.post('/api/admin/users/$id/kick', options: _auth);
  }

  static Future<void> adminDeleteUser(int id) async {
    await _dio.delete('/api/admin/users/$id', options: _auth);
  }

  static Future<List<InviteCode>> adminGetCodes() async {
    final res = await _dio.get('/api/admin/invite-codes', options: _auth);
    return (res.data as List).map((c) => InviteCode.fromJson(c)).toList();
  }

  static Future<String> adminCreateCode() async {
    final res = await _dio.post('/api/admin/invite-codes', options: _auth);
    return res.data['code'] as String;
  }

  static Future<void> adminDeleteCode(int id) async {
    await _dio.delete('/api/admin/invite-codes/$id', options: _auth);
  }
}
