import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Watches network connectivity and exposes it reactively.
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _online = true;
  bool get online => _online;

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _online = _hasNetwork(results);
      notifyListeners();
    } catch (_) {
      _online = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final now = _hasNetwork(results);
      if (now != _online) {
        _online = now;
        notifyListeners();
      }
    });
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any(
      (r) =>
          r != ConnectivityResult.none &&
          r != ConnectivityResult.bluetooth &&
          r != ConnectivityResult.other,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}