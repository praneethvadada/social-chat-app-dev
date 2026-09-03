import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // AWS Deployment - Using deployed backend services on EC2
  // static const String baseUrl = 'http://98.90.116.96:8080/api';
  // WebSocket bypasses API Gateway and connects directly to social-service on port 8082
  // static const String wsUrl = 'http://98.90.116.96:8082/ws';

  // Base server URL for media/images (without /api suffix)
  // static const String serverUrl = 'http://98.90.116.96:8080';

  // Local dev: 10.0.2.2 is a special alias that ONLY resolves inside the
  // Android emulator (it maps to the host machine's localhost from within
  // the emulator's virtual network) — a real desktop browser or an iOS
  // simulator has no idea what that address is, so every request just
  // hangs with no response, not a clean connection-refused. kIsWeb picks
  // localhost automatically for `flutter run -d chrome`; the Android
  // emulator path (kIsWeb == false) keeps 10.0.2.2 as before. A PHYSICAL
  // device (real phone, not emulator/simulator) needs neither — it needs
  // your Mac's actual LAN IP (e.g. 192.168.x.x from `ipconfig getifaddr en0`),
  // since it's not on the same virtual/local loopback as either case below.
  //
  // NOTE: WebSocket connects directly to social-chats-service on 8083
  // (chat/calls/presence were split out of social-service). REST still goes
  // through the gateway on 8080 (api-gateway's own server.port default in
  // both application.properties and application-prod.properties — "8090"
  // was a stale value that never matched any real gateway config; it went
  // unnoticed because the 10.0.2.2 host issue above made every request
  // hang before a connection was ever actually attempted, masking it).
  static const String _host = kIsWeb ? 'localhost' : '10.0.2.2';
  static const String baseUrl = 'http://$_host:8080/api';
  static const String wsUrl = 'http://$_host:8083/ws';
  static const String serverUrl = 'http://$_host:8080';

  // Backend endpoints for call integration
  static const String agoraTokenEndpoint = '$baseUrl/calls/token';
  static const String callLogEndpoint = '$baseUrl/calls';

  // Public web domain used to build shareable profile links (/u/<username>).
  static const String webDomain = 'https://socialchat.app';
}
