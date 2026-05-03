import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/models.dart';
import 'auth_service.dart';

enum WsState { disconnected, connecting, connected }

class WsService {
  static WsService? _instance;
  static WsService get instance => _instance ??= WsService._();
  WsService._();

  WebSocketChannel? _channel;
  WsState _state = WsState.disconnected;
  Timer? _reconnectTimer;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _eventController   = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController   = StreamController<WsState>.broadcast();

  Stream<ChatMessage>           get messages => _messageController.stream;
  Stream<Map<String, dynamic>>  get events   => _eventController.stream;
  Stream<WsState>               get stateStream => _stateController.stream;
  WsState                       get state    => _state;

  void connect() {
    if (_state == WsState.connected || _state == WsState.connecting) return;
    _setState(WsState.connecting);

    final uri = Uri.parse('${ServerConfig.wsUrl}?token=${AuthService.token}');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    _setState(WsState.connected);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _setState(WsState.disconnected);
  }

  void sendText(String content) {
    _send({'type': 'send_message', 'content': content});
  }

  void sendFile(String fileId, String fileName, int fileSize) {
    _send({
      'type': 'send_file',
      'content': fileId,
      'file_name': fileName,
      'file_size': fileSize,
    });
  }

  void loadHistory(int beforeId) {
    _send({'type': 'load_history', 'before_id': beforeId});
  }

  void _send(Map<String, dynamic> data) {
    if (_state == WsState.connected) {
      _channel?.sink.add(jsonEncode(data));
    }
  }

  void _onData(dynamic raw) {
    final Map<String, dynamic> data = jsonDecode(raw as String);
    final type = data['type'] as String?;

    switch (type) {
      case 'message':
        if (data['message'] != null) {
          _messageController.add(ChatMessage.fromJson(data['message']));
        }
        break;
      case 'history':
        final msgs = (data['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(m))
            .toList();
        _eventController.add({'type': 'history', 'messages': msgs, 'has_more': data['has_more'] ?? false});
        break;
      case 'history_page':
        final msgs = (data['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(m))
            .toList();
        _eventController.add({'type': 'history_page', 'messages': msgs, 'has_more': data['has_more'] ?? false});
        break;
      default:
        _eventController.add(data);
    }
  }

  void _onError(dynamic error) {
    _setState(WsState.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    _setState(WsState.disconnected);
    if (AuthService.isLoggedIn) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void _setState(WsState s) {
    _state = s;
    _stateController.add(s);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _eventController.close();
    _stateController.close();
  }
}
