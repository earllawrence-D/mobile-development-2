import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// The three states the dashboard cares about. `connectivity_plus` reports
/// finer-grained interfaces (bluetooth, vpn, ethernet, etc.) but the lab
/// activity only asks us to distinguish Wi-Fi, Cellular, and Offline.
enum NetworkStatus { wifi, cellular, offline }

/// Lifecycle of one simulated "large dataset" request.
enum RequestState { running, queued, completed }

/// A single simulated long-running network request. Progress advances while
/// [state] is [RequestState.running]; a dropped connection freezes it at
/// [RequestState.queued] instead of losing the work.
class SimulatedRequest {
  SimulatedRequest({required this.id, required this.label});

  final String id;
  final String label;
  double progress = 0;
  RequestState state = RequestState.running;
  int retryCount = 0;
}

/// Global, app-wide connectivity monitor and request-queue manager.
///
/// - Subscribes to [Connectivity.onConnectivityChanged] so every screen that
///   watches this provider gets real-time Wi-Fi / Cellular / Offline updates
///   (the "Network Stream Listener" + "Real-time UI" requirements).
/// - Simulates a long-running request with a periodic progress tick (the
///   "continuous or long-running network request" requirement).
/// - If connectivity drops mid-request (a handover / IP migration), the
///   ticker is stopped and the request is moved to [RequestState.queued]
///   instead of throwing/crashing (the "Request Queuing System"
///   requirement).
/// - As soon as [Connectivity.onConnectivityChanged] reports a stable
///   Wi-Fi or Cellular connection again, queued requests automatically
///   resume ticking from where they left off (the "Graceful Recovery"
///   requirement) — no user action required.
class NetworkMonitor extends ChangeNotifier {
  NetworkMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _ticker;
  int _idCounter = 0;

  NetworkStatus _status = NetworkStatus.offline;
  final List<SimulatedRequest> _requests = [];

  NetworkStatus get status => _status;
  List<SimulatedRequest> get requests => List.unmodifiable(_requests);
  bool get hasQueuedRequests =>
      _requests.any((r) => r.state == RequestState.queued);

  Future<void> _init() async {
    // Read the current state once on startup, then subscribe for changes.
    final initial = await _connectivity.checkConnectivity();
    _applyConnectivity(initial);
    _subscription =
        _connectivity.onConnectivityChanged.listen(_applyConnectivity);
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final previousStatus = _status;

    if (results.contains(ConnectivityResult.wifi)) {
      _status = NetworkStatus.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      _status = NetworkStatus.cellular;
    } else {
      _status = NetworkStatus.offline;
    }

    final droppedJustNow =
        previousStatus != NetworkStatus.offline && _status == NetworkStatus.offline;
    final reconnectedJustNow =
        previousStatus == NetworkStatus.offline && _status != NetworkStatus.offline;

    if (droppedJustNow) {
      _queuePendingRequests();
    } else if (reconnectedJustNow) {
      _resumeQueuedRequests();
    }

    notifyListeners();
  }

  /// Kicks off a new simulated "large dataset" fetch.
  SimulatedRequest startFetch({String label = 'Large dataset fetch'}) {
    final request = SimulatedRequest(id: 'req-${++_idCounter}', label: label);
    _requests.insert(0, request);
    _startTickerIfNeeded();
    notifyListeners();
    return request;
  }

  /// Called when a handover/IP migration knocks the connection offline
  /// mid-request. This is the "catch the error and queue instead of
  /// crashing" step: we stop the ticker and flip any in-flight request to
  /// [RequestState.queued] rather than letting it fail outright.
  void _queuePendingRequests() {
    _ticker?.cancel();
    _ticker = null;
    for (final request in _requests) {
      if (request.state == RequestState.running) {
        request.state = RequestState.queued;
      }
    }
  }

  /// Called automatically from the connectivity callback stream once a
  /// stable Wi-Fi or Cellular connection is detected again. Queued requests
  /// resume from their saved progress — no data is lost and no user
  /// interaction is required.
  void _resumeQueuedRequests() {
    for (final request in _requests) {
      if (request.state == RequestState.queued) {
        request.state = RequestState.running;
        request.retryCount++;
      }
    }
    _startTickerIfNeeded();
  }

  void _startTickerIfNeeded() {
    if (_ticker != null) return;
    if (!_requests.any((r) => r.state == RequestState.running)) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());
  }

  void _tick() {
    var anyRunning = false;
    for (final request in _requests) {
      if (request.state != RequestState.running) continue;
      anyRunning = true;
      request.progress = (request.progress + 0.05).clamp(0.0, 1.0);
      if (request.progress >= 1.0) {
        request.state = RequestState.completed;
      }
    }
    if (!anyRunning || !_requests.any((r) => r.state == RequestState.running)) {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  void clearCompleted() {
    _requests.removeWhere((r) => r.state == RequestState.completed);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
