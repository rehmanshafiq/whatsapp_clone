import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/network/api_exception.dart';

enum SocketConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebSocketService {
  static const String _socketBaseUrl =
      'wss://chatapp-backend-0kxr.onrender.com/ws?token=';
  static const Duration _heartbeatInterval = Duration(seconds: 45);
  static const Duration _reconnectDelay = Duration(seconds: 5);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  String? _token;
  bool _isManualDisconnect = false;

  final StreamController<dynamic> _messagesController =
      StreamController<dynamic>.broadcast();
  final StreamController<SocketConnectionStatus> _statusController =
      StreamController<SocketConnectionStatus>.broadcast();

  SocketConnectionStatus _status = SocketConnectionStatus.disconnected;

  Stream<dynamic> get messagesStream => _messagesController.stream;
  Stream<SocketConnectionStatus> get statusStream => _statusController.stream;
  SocketConnectionStatus get status => _status;
  bool get isConnected => _status == SocketConnectionStatus.connected;

  Future<void> connect({required String token}) async {
    _token = token;
    _isManualDisconnect = false;

    if (isConnected) return;

    _setStatus(
      _status == SocketConnectionStatus.disconnected
          ? SocketConnectionStatus.connecting
          : SocketConnectionStatus.reconnecting,
    );

    _cancelReconnectTimer();
    await _closeCurrentChannel();

    try {
      final uri = Uri.parse('$_socketBaseUrl$token');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onSocketMessage,
        onError: _onSocketError,
        onDone: _onSocketDone,
        cancelOnError: true,
      );

      await channel.ready.timeout(const Duration(seconds: 10));
      _setStatus(SocketConnectionStatus.connected);
      _startHeartbeat();
      _sendHeartbeat();
    } catch (e) {
      _cleanupConnection();
      _scheduleReconnect();
      throw ApiException(message: 'Failed to connect to realtime service.');
    }
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _cancelReconnectTimer();
    _cleanupConnection();
    await _closeCurrentChannel();
    _setStatus(SocketConnectionStatus.disconnected);
  }

  void send(dynamic payload) {
    if (!isConnected || _channel == null) return;

    try {
      if (payload is String) {
        _channel!.sink.add(payload);
      } else {
        _channel!.sink.add(jsonEncode(payload));
      }
    } catch (_) {}
  }

  void _onSocketMessage(dynamic message) {
    dynamic parsedMessage = message;
    if (message is String) {
      try {
        parsedMessage = jsonDecode(message);
      } catch (_) {
        parsedMessage = message;
      }
    }
    _messagesController.add(parsedMessage);
  }

  void _onSocketError(Object _) {
    _cleanupConnection();
    if (!_isManualDisconnect) {
      _setStatus(SocketConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _onSocketDone() {
    _cleanupConnection();
    if (!_isManualDisconnect) {
      _setStatus(SocketConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    final token = _token;
    if (!isConnected || token == null) return;
    send(<String, dynamic>{'token': token});
  }

  void _scheduleReconnect() {
    if (_isManualDisconnect || _token == null) return;
    if (_reconnectTimer?.isActive == true) return;

    _setStatus(SocketConnectionStatus.reconnecting);
    _reconnectTimer = Timer(_reconnectDelay, () async {
      final token = _token;
      if (token == null || _isManualDisconnect) return;
      try {
        await connect(token: token);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _cleanupConnection() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _closeCurrentChannel() async {
    if (_channel == null) return;
    try {
      await _channel!.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _setStatus(SocketConnectionStatus nextStatus) {
    _status = nextStatus;
    _statusController.add(nextStatus);
  }

  Future<void> dispose() async {
    await disconnect();
    await _messagesController.close();
    await _statusController.close();
  }
}
