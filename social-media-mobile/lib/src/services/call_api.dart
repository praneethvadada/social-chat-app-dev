
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';
import '../models/call_history.dart';
import '../database/call_local_repository.dart';


class CallApi {
  // Requests an Agora token from backend for a given channel and uid.
  // Backend should implement `ApiConfig.agoraTokenEndpoint` to return JSON: {"token": "...", "appId": "..."}
  static Future<Map<String, dynamic>?> fetchAgoraToken(String channel, int uid) async {
    final uri = Uri.parse('${ApiConfig.agoraTokenEndpoint}?channel=$channel&uid=$uid');
    try {
      final token = await ApiService.getToken();
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
      print('[CallApi] fetchAgoraToken failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[CallApi] fetchAgoraToken exception: $e');
    }
    return null;
  }

  // Log a call (initiated, rejected, ended, etc). Returns the created
  // CallLog's id so callers can thread it through the rest of the call's
  // lifecycle instead of re-scanning history later.
  static Future<int?> logCall(Map<String, dynamic> payload) async {
    final uri = Uri.parse(ApiConfig.callLogEndpoint);
    try {
      final token = await ApiService.getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(uri, body: json.encode(payload), headers: headers);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final id = body['id'];
        return id is int ? id : int.tryParse(id.toString());
      }
      print('[CallApi] logCall failed: ${res.statusCode} ${res.body}');
      return null;
    } catch (e) {
      print('[CallApi] logCall exception: $e');
      return null;
    }
  }

  // "Join later" — is there an in-progress call for this group right now?
  static Future<Map<String, dynamic>?> fetchActiveGroupCall(int groupId) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/group/$groupId/active');
    try {
      final token = await ApiService.getToken();
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
      print('[CallApi] fetchActiveGroupCall failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[CallApi] fetchActiveGroupCall exception: $e');
    }
    return null;
  }

  // Server-authoritative join — enforces the max-participant cap. Returns
  // null on success, or 'call_full'/'error' describing why it failed.
  static Future<String?> joinCallParticipant(int callId, int agoraUid) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/$callId/participants/join');
    try {
      final token = await ApiService.getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(uri, body: json.encode({'agoraUid': agoraUid}), headers: headers);
      if (res.statusCode == 200) return null;
      if (res.statusCode == 409) return 'call_full';
      print('[CallApi] joinCallParticipant failed: ${res.statusCode} ${res.body}');
      return 'error';
    } catch (e) {
      print('[CallApi] joinCallParticipant exception: $e');
      return 'error';
    }
  }

  static Future<void> leaveCallParticipant(int callId) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/$callId/participants/leave');
    try {
      final token = await ApiService.getToken();
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      await http.post(uri, headers: headers);
    } catch (e) {
      print('[CallApi] leaveCallParticipant exception: $e');
    }
  }

  // Fetch call history for the authenticated user
  static final CallLocalRepository _localRepo = CallLocalRepository();

  // Fetch local call history (SQLite)
  static Future<List<CallHistory>> getLocalCallHistory() async {
    return _localRepo.getAllCalls();
  }

  // Fetch call history from backend AND update local DB
  static Future<List<CallHistory>> fetchCallHistory() async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/history');
    try {
      final token = await ApiService.getToken();
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      print('[CallApi] fetchCallHistory: token=${token?.substring(0, 20)}..., headers=$headers, url=$uri');

      final res = await http.get(uri, headers: headers);
      print('[CallApi] fetchCallHistory: response status=${res.statusCode}, body=${res.body}');
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        final calls = data.map((e) => CallHistory.fromJson(e as Map<String, dynamic>)).toList();
        
        // Save to local DB (Write-behind)
        await _localRepo.saveCalls(calls);
        
        return calls;
      }
      print('[CallApi] fetchCallHistory failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('[CallApi] fetchCallHistory exception: $e');
    }
    return getLocalCallHistory();
  }

  // Update call status (rejected, ended, etc)
  static Future<bool> updateCallStatus(int callId, String status, {int duration = 0}) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/$callId/status');
    try {
      final token = await ApiService.getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final payload = {
        'status': status,
        'duration': duration,
      };

      final res = await http.put(uri, body: json.encode(payload), headers: headers);
      if (res.statusCode == 200) return true;
      print('[CallApi] updateCallStatus failed: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      print('[CallApi] updateCallStatus exception: $e');
      return false;
    }  }

  // Send reject signal via REST (fallback for when WebSocket is disconnected)
  static Future<bool> rejectCallSignal(int callerId, String channelName) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/reject');
    try {
      final token = await ApiService.getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final payload = {
        'callerId': callerId,
        'channelName': channelName,
      };

      final res = await http.post(uri, body: json.encode(payload), headers: headers);
      if (res.statusCode == 200) {
        print('[CallApi] rejectCallSignal succeeded');
        return true;
      }
      print('[CallApi] rejectCallSignal failed: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      print('[CallApi] rejectCallSignal exception: $e');
      return false;
    }
  }

  // Send accept signal via REST (fallback)
  static Future<bool> acceptCallSignal(int callerId, String channelName, bool isVideo) async {
    final uri = Uri.parse('${ApiConfig.callLogEndpoint}/accept');
    try {
      final token = await ApiService.getToken();
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final payload = {
        'callerId': callerId,
        'channelName': channelName,
        'isVideo': isVideo,
      };

      final res = await http.post(uri, body: json.encode(payload), headers: headers);
      if (res.statusCode == 200) {
        print('[CallApi] acceptCallSignal succeeded');
        return true;
      }
      print('[CallApi] acceptCallSignal failed: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      print('[CallApi] acceptCallSignal exception: $e');
      return false;
    }
  }
}