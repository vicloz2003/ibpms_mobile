import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks whether the device currently has a usable network interface (RNF-6).
///
/// `connectivity_plus` reports interface state (wifi/mobile/none), which is a good
/// proxy for "can we reach the backend". Real reachability is confirmed lazily by
/// the actual HTTP call failing — on a network error we fall back to cache and/or
/// enqueue, so a false "online" never loses data.
class ConnectivityService {
  ConnectivityService._() {
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
    _init();
  }
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _online = true;

  /// Current best-effort online state.
  bool get isOnline => _online;

  /// Emits whenever the online state flips. Useful to trigger a sync flush.
  Stream<bool> get onStatusChange => _controller.stream;

  Future<void> _init() async {
    try {
      _onChanged(await _connectivity.checkConnectivity());
    } catch (_) {
      _setOnline(true); // assume online if the platform query fails
    }
  }

  void _onChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    _setOnline(online);
  }

  void _setOnline(bool value) {
    if (value == _online) return;
    _online = value;
    _controller.add(value);
  }

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }
}
