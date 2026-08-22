import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsHandler = void Function(Map<String, dynamic> payload);

class WebSocketService {
  final String url;
  WebSocketChannel? _channel;
  final Map<String, List<WsHandler>> _listeners = {};

  WebSocketService(this.url);

  void connect() {
    if (_channel != null) return;
    print('[WebSocketService] connecting to $url');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
    } catch (e) {
      print('[WebSocketService] connect error: $e');
      return;
    }
    _channel!.stream.listen((message) {
      print('[WebSocketService] received: $message');
      try {
        final Map<String, dynamic> m = json.decode(message as String) as Map<String, dynamic>;
        final type = m['type'] as String?;
        if (type != null && _listeners.containsKey(type)) {
          for (final h in List<WsHandler>.from(_listeners[type]!)) {
            try {
              h(m['payload'] as Map<String, dynamic>);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }, onDone: () {
      print('[WebSocketService] connection closed');
      _channel = null;
      // reconnect strategy could be added here
    }, onError: (_) {
      print('[WebSocketService] stream error: $_');
      _channel = null;
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void send(String type, Map<String, dynamic> payload) {
    final msg = json.encode({'type': type, 'payload': payload});
    try {
      print('[WebSocketService] send: $msg');
      _channel?.sink.add(msg);
    } catch (e) {
      print('[WebSocketService] send error: $e');
    }
  }

  void on(String type, WsHandler handler) {
    _listeners.putIfAbsent(type, () => []).add(handler);
  }

  void off(String type, WsHandler handler) {
    _listeners[type]?.remove(handler);
  }
}
