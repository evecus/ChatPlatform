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
import 'settings_screen.dart';

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
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WsService.instance.connect();
    _listenWs();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    // 上拉到顶触发加载更多
    if (_scroll.position.pixels <= 0 && _hasMore && !_loadingMore) {
      _loadMoreHistory();
    }
  }

  void _loadMoreHistory() {
    if (_messages.isEmpty) return;
    setState(() => _loadingMore = true);
    WsService.instance.loadHistory(_messages.first.id);
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
          final hasMore = event['has_more'] as bool? ?? false;
          setState(() {
            _messages.clear();
            _messages.addAll(msgs);
            _hasMore = hasMore;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
          break;

        case 'history_page':
          final msgs = (event['messages'] as List).cast<ChatMessage>();
          final hasMore = event['has_more'] as bool? ?? false;
          // 记住当前滚动高度，插入后保持位置不跳动
          final oldExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
          setState(() {
            _messages.insertAll(0, msgs);
            _hasMore = hasMore;
            _loadingMore = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              final newExtent = _scroll.position.maxScrollExtent;
              _scroll.jumpTo(newExtent - oldExtent);
            }
          });
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
          _forceLogout('您已被管理员移出聊天室。');
          break;
        case 'banned':
          _forceLogout('您的账号已被封禁。');
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
        title: const Text('账号通知'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('确定'),
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
        const SnackBar(content: Text('文件过大（最大 10MB）'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final data = await ApiService.uploadFile(file);
      WsService.instance.sendFile(data['file_id'], data['original_name'], data['size']);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadFile(ChatMessage msg) async {
    if (msg.fileExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件已过期，无法下载'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      final path = await ApiService.downloadFile(msg.content, msg.fileName!);
      await OpenFilex.open(path);
    } catch (e) {
      final errStr = e.toString();
      final isExpired = errStr.contains('410') || errStr.contains('file_expired');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isExpired ? '文件已过期，无法下载' : '下载失败：$e'),
          backgroundColor: isExpired ? Colors.orange : Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    WsService.instance.disconnect();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.currentUser!;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('群聊', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF1A1A1A)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            tooltip: '设置',
          ),
          if (me.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Color(0xFF1A1A1A)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              tooltip: '管理面板',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF1A1A1A)),
            onSelected: (value) async {
              if (value == 'logout' || value == 'switch_server') {
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
                  Text('切换服务器'),
                ]),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 10),
                  Text('退出登录'),
                ]),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE0E0E0), height: 1),
        ),
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length + (_loadingMore || _hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                // 顶部加载指示器
                if (i == 0 && (_loadingMore || _hasMore)) {
                  return _LoadMoreIndicator(loading: _loadingMore);
                }
                final msgIndex = (_loadingMore || _hasMore) ? i - 1 : i;
                return _MessageTile(
                  msg: _messages[msgIndex],
                  isMe: _messages[msgIndex].userId == me.id,
                  onDownload: _downloadFile,
                );
              },
            ),
          ),
          // Input bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    icon: _uploading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.attach_file, color: Color(0xFF666666)),
                    onPressed: _uploading ? null : _pickAndSendFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      style: const TextStyle(color: Color(0xFF1A1A1A)),
                      decoration: InputDecoration(
                        hintText: '发送消息...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFFF0F0F0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF00B4A0)),
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

class _LoadMoreIndicator extends StatelessWidget {
  final bool loading;
  const _LoadMoreIndicator({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4A0)),
              )
            : const Text('上拉加载更多', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
            if (!isMe || msg.isFile)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: Text(
                  isMe ? '我' : msg.username,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            GestureDetector(
              onLongPress: msg.isFile ? null : () {
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF00B4A0) : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: msg.isFile ? _fileContent(isMe) : _textContent(isMe),
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

  Widget _textContent(bool isMe) => Text(
    msg.content,
    style: TextStyle(color: isMe ? Colors.white : const Color(0xFF1A1A1A)),
  );

  Widget _fileContent(bool isMe) {
    final sizeKb = ((msg.fileSize ?? 0) / 1024).toStringAsFixed(1);
    final expired = msg.fileExpired;
    final textColor = isMe ? Colors.white : const Color(0xFF1A1A1A);
    final subColor = isMe ? Colors.white70 : Colors.grey;
    final expiredColor = isMe ? Colors.white54 : Colors.grey.shade400;

    return InkWell(
      onTap: () => onDownload(msg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? Icons.insert_drive_file_outlined : Icons.insert_drive_file,
            color: expired ? expiredColor : subColor,
            size: 24,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.fileName ?? '文件',
                  style: TextStyle(
                    color: expired ? expiredColor : textColor,
                    fontWeight: FontWeight.w500,
                    decoration: expired ? TextDecoration.lineThrough : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  expired ? '文件已过期' : '$sizeKb KB',
                  style: TextStyle(color: expired ? expiredColor : subColor, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            expired ? Icons.block : Icons.download_rounded,
            color: expired ? expiredColor : subColor,
            size: 18,
          ),
        ],
      ),
    );
  }
}
