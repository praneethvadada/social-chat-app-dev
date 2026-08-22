import 'package:sqflite/sqflite.dart';
import '../models/call_history.dart';
import 'database_helper.dart';

class CallLocalRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Save a single call (insert or update)
  Future<void> saveCall(CallHistory call) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        'call_history',
        {
          'id': call.id,
          'initiator_id': call.initiatorId,
          'receiver_id': call.receiverId,
          'type': call.type == CallType.video ? 'VIDEO' : 'AUDIO',
          'status': call.status.toString().split('.').last.toUpperCase(),
          'duration': call.duration,
          'created_at': call.createdAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('[CallLocalRepository] ✅ Call saved: id=${call.id}');
    } catch (e) {
      print('[CallLocalRepository] ❌ Error saving call: $e');
    }
  }

  // Save multiple calls (bulk)
  Future<void> saveCalls(List<CallHistory> calls) async {
    try {
      final db = await _dbHelper.database;
      final batch = db.batch();
      for (final call in calls) {
        batch.insert(
          'call_history',
          {
            'id': call.id,
            'initiator_id': call.initiatorId,
            'receiver_id': call.receiverId,
            'type': call.type == CallType.video ? 'VIDEO' : 'AUDIO',
            'status': call.status.toString().split('.').last.toUpperCase(),
            'duration': call.duration,
            'created_at': call.createdAt.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      print('[CallLocalRepository] ✅ Saved ${calls.length} calls to SQLite');
    } catch (e) {
      print('[CallLocalRepository] ❌ Error saving calls batch: $e');
    }
  }

  // Get all calls (sorted by date desc)
  Future<List<CallHistory>> getAllCalls() async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('call_history', orderBy: 'created_at DESC');

      return maps.map((map) {
         return CallHistory(
           id: map['id'] as int,
           initiatorId: map['initiator_id'] as int,
           receiverId: map['receiver_id'] as int,
           type: (map['type'] as String) == 'VIDEO' ? CallType.video : CallType.audio,
           status: _parseStatus(map['status'] as String),
           duration: map['duration'] as int,
           createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
         );
      }).toList();
    } catch (e) {
      print('[CallLocalRepository] ❌ Error fetching calls: $e');
      return [];
    }
  }

  CallStatus _parseStatus(String status) {
     switch (status) {
       case 'ACCEPTED': return CallStatus.accepted;
       case 'DECLINED': 
       case 'REJECTED': return CallStatus.declined;
       case 'ENDED': return CallStatus.ended;
       default: return CallStatus.initiated;
     }
  }
}
