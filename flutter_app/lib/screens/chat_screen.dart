import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'admin_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _onlineUsers = <String>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WsService.instance.connect();
    _listenWs();
  }

  void _listenWs() {
    WsService.instance.messages.listen((msg) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });

    WsService.instance.events.listen((event) {
      final type = event['type'] as String?;
      switch (type) {
        case 'history':
          final msgs = (event['messages'] as List).cast<ChatMessage>();
          setState(() { _messages.clear(); _messages.addAll(msgs); });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
          break;
        case 'online_users':
          final users = (event['users'] as List?)?.map((u) => u['username'] as String).toList() ?? [];
          setState(() { _onlineUsers..clear()..addAll(users); });
          break;
        case 'user_joined':
          final u = event['username'] as String? ?? '';
          if (!_onlineUsers.contains(u)) setState(() => _onlineUsers.add(u));
          break;
        case 'user_left':
        case 'user_banned':
          final u = event['username'] as String? ?? '';
          setState(() => _onlineUsers.remove(u));
          break;
        case 'kicked':
          _forceLogout('You were removed by admin.');
          break;
        case 'banned':
          _forceLogout('Your account has been banned.');
          break;
      }
    });
  }

  void _forceLogout(String reason) {
    WsService.instance.disconnect();
    AuthService.logout();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Account Action'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (animate) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    WsService.instance.sendText(text);
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;

    final file = File(picked.path!);
    final size = await file.length();
    if (size > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large (max 10MB)'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final data = await ApiService.uploadFile(file);
      WsService.instance.sendFile(data['file_id'], data['original_name'], data['size']);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadFile(ChatMessage msg) async {
    try {
      final path = await ApiService.downloadFile(msg.content, msg.fileName!);
      await OpenFilex.open(path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    WsService.instance.disconnect();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Group Chat'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${_onlineUsers.length} online',
                  style: const TextStyle(fontSize: 12, color: Colors.green)),
            ),
          ],
        ),
        actions: [
          if (me.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              tooltip: 'Admin Panel',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                WsService.instance.disconnect();
                await AuthService.logout();
                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              } else if (value == 'switch_server') {
                WsService.instance.disconnect();
                await AuthService.logout();
                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'switch_server',
                child: Row(children: [
                  Icon(Icons.dns_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Switch Server'),
                ]),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 10),
                  Text('Logout'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Online users bar
          if (_onlineUsers.isNotEmpty)
            Container(
              height: 36,
              color: const Color(0xFF1A1A1A),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _onlineUsers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Center(
                  child: Chip(
                    avatar: const CircleAvatar(backgroundColor: Colors.green, radius: 4),
                    label: Text(_onlineUsers[i], style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF2A2A2A),
                  ),
                ),
              ),
            ),
          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageTile(
                msg: _messages[i],
                isMe: _messages[i].userId == me.id,
                onDownload: _downloadFile,
              ),
            ),
          ),
          // Input bar
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    icon: _uploading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file),
                    onPressed: _uploading ? null : _pickAndSendFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF1A73E8)),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final Future<void> Function(ChatMessage) onDownload;

  const _MessageTile({required this.msg, required this.isMe, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(msg.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2, bottom: 2,
          left: isMe ? 60 : 12,
          right: isMe ? 12 : 60,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(msg.username, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            GestureDetector(
              onLongPress: msg.isFile ? null : () {
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF1A73E8) : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: msg.isFile ? _fileContent() : _textContent(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textContent() => Text(msg.content, style: const TextStyle(color: Colors.white));

  Widget _fileContent() {
    final sizeKb = ((msg.fileSize ?? 0) / 1024).toStringAsFixed(1);
    return InkWell(
      onTap: () => onDownload(msg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg.fileName ?? 'file',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                Text('$sizeKb KB · tap to open',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
