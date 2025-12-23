import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../sync/sync_engine.dart';

/// Monitors network connectivity and triggers sync when coming back online
class ConnectivityService {
  final Connectivity _connectivity;
  final SyncEngine _syncEngine;
  
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;
  bool _isInitialized = false;

  ConnectivityService(this._connectivity, this._syncEngine);

  /// Start monitoring connectivity changes
  void start() {
    if (_isInitialized) return;
    _isInitialized = true;

    _subscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    
    // Check initial connectivity
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _wasOffline = !_hasConnection(results);
      AppLogger.info('Initial connectivity check', data: {
        'hasConnection': !_wasOffline,
        'results': results.map((r) => r.name).toList(),
      });
    } catch (e) {
      AppLogger.error('Failed to check initial connectivity', error: e);
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasConnection = _hasConnection(results);
    
    AppLogger.info('Connectivity changed', data: {
      'hasConnection': hasConnection,
      'wasOffline': _wasOffline,
      'results': results.map((r) => r.name).toList(),
    });

    if (hasConnection && _wasOffline) {
      // Just came back online - trigger sync
      AppLogger.info('Back online, triggering sync');
      _triggerSync();
    }

    _wasOffline = !hasConnection;
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);
  }

  void _triggerSync() {
    // Restart the sync engine to process pending jobs
    _syncEngine.stop();
    _syncEngine.start();
  }

  /// Check if currently connected to the internet
  Future<bool> isConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasConnection(results);
    } catch (e) {
      AppLogger.error('Failed to check connectivity', error: e);
      return false;
    }
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}

/// Provider for connectivity service
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final syncEngine = ref.watch(syncEngineProvider);
  final service = ConnectivityService(Connectivity(), syncEngine);
  
  ref.onDispose(() {
    service.stop();
  });
  
  return service;
});

/// Provider for current connectivity status
final isConnectedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(connectivityServiceProvider);
  return service.isConnected();
});

/// Stream provider for connectivity changes
final connectivityStreamProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  
  return connectivity.onConnectivityChanged.map((results) {
    return results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);
  });
});
