class ApiConfig {
  // AWS Deployment - Using deployed backend services on EC2
  // static const String baseUrl = 'http://98.90.116.96:8080/api';
  // WebSocket bypasses API Gateway and connects directly to social-service on port 8082
  // static const String wsUrl = 'http://98.90.116.96:8082/ws';

  // Base server URL for media/images (without /api suffix)
  // static const String serverUrl = 'http://98.90.116.96:8080';

  // Local Chrome Run
  // static const String baseUrl = 'http://localhost:8080/api';
  // static const String wsUrl = 'http://localhost:8082/ws';
  // static const String serverUrl = 'http://localhost:8080';

  // Local Emulator Run
  // NOTE: WebSocket now connects directly to social-chats-service on 8083
  // (chat/calls/presence were split out of social-service). REST still goes
  // through the gateway on 8080 (which routes /messages + /calls to 8083).
  static const String baseUrl = 'http://10.0.2.2:8090/api';
  static const String wsUrl = 'http://10.0.2.2:8083/ws';
  static const String serverUrl = 'http://10.0.2.2:8090';

  // Backend endpoints for call integration
  static const String agoraTokenEndpoint = '$baseUrl/calls/token';
  static const String callLogEndpoint = '$baseUrl/calls';

  // Public web domain used to build shareable profile links (/u/<username>).
  static const String webDomain = 'https://socialchat.app';
}
