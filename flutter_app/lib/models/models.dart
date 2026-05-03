class User {
  final int id;
  final String username;
  final String role;
  final String status;

  const User({
    required this.id,
    required this.username,
    required this.role,
    this.status = 'active',
  });

  bool get isAdmin => role == 'admin';

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        username: j['username'],
        role: j['role'] ?? 'user',
        status: j['status'] ?? 'active',
      );
}

class ChatMessage {
  final int id;
  final int userId;
  final String username;
  final String type; // 'text' | 'file'
  final String content;
  final String? fileName;
  final int? fileSize;
  final bool fileExpired;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.type,
    required this.content,
    this.fileName,
    this.fileSize,
    this.fileExpired = false,
    required this.createdAt,
  });

  bool get isFile => type == 'file';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'],
        userId: j['user_id'],
        username: j['username'],
        type: j['type'] ?? 'text',
        content: j['content'] ?? '',
        fileName: j['file_name'],
        fileSize: j['file_size'],
        fileExpired: j['file_expired'] == true,
        createdAt: DateTime.parse(j['created_at']).toLocal(),
      );
}

class InviteCode {
  final int id;
  final String code;
  final bool used;
  final String? usedBy;
  final DateTime createdAt;

  const InviteCode({
    required this.id,
    required this.code,
    required this.used,
    this.usedBy,
    required this.createdAt,
  });

  factory InviteCode.fromJson(Map<String, dynamic> j) => InviteCode(
        id: j['id'],
        code: j['code'],
        used: j['used'] ?? false,
        usedBy: j['used_by'],
        createdAt: DateTime.parse(j['created_at']).toLocal(),
      );
}

class AdminUser {
  final int id;
  final String username;
  final String role;
  final String status;
  final bool online;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    required this.online,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'],
        username: j['username'],
        role: j['role'] ?? 'user',
        status: j['status'] ?? 'active',
        online: j['online'] ?? false,
        createdAt: DateTime.parse(j['created_at']).toLocal(),
      );
}
