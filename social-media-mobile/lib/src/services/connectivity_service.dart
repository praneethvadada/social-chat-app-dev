import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// ConnectivityService - Monitors internet connectivity in real-time
/// 
/// Detects:
/// - WiFi connected/disconnected
/// - Mobile data connected/disconnected
/// - Complete internet loss
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  
  factory ConnectivityService() {
    return _instance;
  }
  
  ConnectivityService._internal();
  
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  
  bool _isOnline = true;
  bool get isOnline => _isOnline;
  
  // Stream controller for connectivity changes
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;
  
  // List of listeners
  final List<Function(bool)> _listeners = [];
  
  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      _isOnline = _isConnected(result);
      print('[ConnectivityService] Initial status: ${_isOnline ? "🟢 ONLINE" : "🔴 OFFLINE"}');
      
      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
        final wasOnline = _isOnline;
        _isOnline = _isConnected(result);
        
        print('[ConnectivityService] Status changed: ${_isOnline ? "🟢 ONLINE" : "🔴 OFFLINE"}');
        
        if (wasOnline != _isOnline) {
          print('[ConnectivityService] Notifying ${_listeners.length} listeners...');
          
          // Notify all listeners
          for (final listener in _listeners) {
            try {
              listener(_isOnline);
            } catch (e) {
              print('[ConnectivityService] Error calling listener: $e');
            }
          }
          
          // Broadcast to stream
          _connectivityController.add(_isOnline);
        }
      });
    } catch (e) {
      print('[ConnectivityService] Error initializing: $e');
      _isOnline = true; // Default to online if check fails
    }
  }
  
  /// Add a listener for connectivity changes
  void addListener(Function(bool isOnline) callback) {
    if (!_listeners.contains(callback)) {
      _listeners.add(callback);
      print('[ConnectivityService] Listener added. Total: ${_listeners.length}');
    }
  }
  
  /// Remove a listener
  void removeListener(Function(bool isOnline) callback) {
    _listeners.remove(callback);
    print('[ConnectivityService] Listener removed. Total: ${_listeners.length}');
  }
  
  /// Check if result indicates connection
  bool _isConnected(List<ConnectivityResult> result) {
    return result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.ethernet);
  }
  
  /// Cleanup resources
  void dispose() {
    _connectivitySubscription.cancel();
    _connectivityController.close();
    _listeners.clear();
    print('[ConnectivityService] Disposed');
  }
}
