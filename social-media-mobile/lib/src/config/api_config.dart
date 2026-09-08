import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class ApiConfig {
  // Production (Hostinger VPS) — picked up automatically whenever the app
  // is built in release mode (`flutter build web` defaults to --release,
  // so this needs no extra flags and no manual edit before shipping).
  // api-gateway (REST) and social-chats-service (WebSocket, proxied via
  // SockJS) both sit behind nginx on this same subdomain over HTTPS.
  static const String _prodApiHost = 'www.api.rchat.revolutionworldinc.com';
  static const String _prodBaseUrl = 'https://$_prodApiHost/api';
  // SockJS (see chat_websocket_service.dart's StompConfig.SockJS) takes an
  // http(s):// base URL, not ws(s):// — it negotiates the actual transport
  // itself, same convention the dev URL below already uses.
  static const String _prodWsUrl = 'https://$_prodApiHost/ws';
  static const String _prodServerUrl = 'https://$_prodApiHost';

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
  // NOTE: WebSocket connects directly to social-chats-service on 8083 in
  // dev (chat/calls/presence were split out of social-service), bypassing
  // the gateway. In production it goes through the gateway's own existing
  // "/ws/**" route (GatewayConfig.java — added precisely for this case,
  // "gateway-routed WS clients") on the same api subdomain as REST (see
  // _prodWsUrl above), since a raw host:8083 URL has no TLS/nginx in front
  // of it — nginx only needs ONE upstream (the gateway) for the whole api
  // subdomain. REST always goes through the gateway on 8080 locally
  // (api-gateway's own server.port default in both application.properties
  // and application-prod.properties — "8090" was a stale value that never
  // matched any real gateway config; it went unnoticed because the
  // 10.0.2.2 host issue above made every request hang before a connection
  // was ever actually attempted, masking it).
  static const String _devHost = kIsWeb ? 'localhost' : '10.0.2.2';
  static const String _devBaseUrl = 'http://$_devHost:8080/api';
  static const String _devWsUrl = 'http://$_devHost:8083/ws';
  static const String _devServerUrl = 'http://$_devHost:8080';

  static const String baseUrl = kReleaseMode ? _prodBaseUrl : _devBaseUrl;
  static const String wsUrl = kReleaseMode ? _prodWsUrl : _devWsUrl;
  static const String serverUrl = kReleaseMode ? _prodServerUrl : _devServerUrl;

  // Backend endpoints for call integration
  static const String agoraTokenEndpoint = '$baseUrl/calls/token';
  static const String callLogEndpoint = '$baseUrl/calls';

  // Public web domain used to build shareable profile links (/u/<username>).
  static const String webDomain = 'https://www.rchat.revolutionworldinc.com';
}
