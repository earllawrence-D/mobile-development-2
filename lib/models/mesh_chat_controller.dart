import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'mesh_models.dart';

/// Owns everything about the serverless chat session and exposes it as plain
/// state. The screen only reads [peers] / [messages] / [phase] and calls the
/// intent methods below (UI = f(state)).
///
/// Flow:
///   1. [start]        permissions -> startAdvertising + startDiscovery
///   2. [connect]      requestConnection to a discovered peer
///   3. handshake      both sides get the same auth token -> [acceptPeer]
///   4. [sendMessage]  bytes payload to every connected peer, which relay it
///                     onward (flood routing with TTL + de-duplication)
class MeshChatController extends ChangeNotifier {
  MeshChatController({required this.userName});

  /// Both devices must use the same service id to see each other.
  static const String serviceId = 'com.example.lab_compiler_app.meshchat';

  /// P2P_CLUSTER = many-to-many, which makes the chat a mesh.
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  static const int maxHops = 4;
  static const int maxTextLength = 1000;
  static const int _maxSeen = 500;

  final String userName;

  /// Random id that identifies this install as a message author.
  final String deviceId = _randomId();

  final Nearby _nearby = Nearby();

  MeshPhase _phase = MeshPhase.idle;
  bool _permanentlyDenied = false;
  bool _locationServiceOn = true;
  String? _error;
  bool _disposed = false;
  int _counter = 0;

  final Map<String, MeshPeer> _peers = {};
  final List<MeshMessage> _messages = [];
  final Set<String> _seen = <String>{};

  // ---- Read-only state for the UI -------------------------------------

  MeshPhase get phase => _phase;
  bool get permanentlyDenied => _permanentlyDenied;
  bool get locationServiceOn => _locationServiceOn;
  String? get error => _error;
  List<MeshMessage> get messages => List.unmodifiable(_messages);

  /// Connected peers first, then handshake in progress, then merely nearby.
  List<MeshPeer> get peers {
    final list = _peers.values.toList();
    list.sort((a, b) {
      final byStatus = b.status.index.compareTo(a.status.index);
      return byStatus != 0 ? byStatus : a.name.compareTo(b.name);
    });
    return list;
  }

  int get connectedCount =>
      _peers.values.where((p) => p.status == PeerStatus.connected).length;

  bool get canSend => _phase == MeshPhase.running && connectedCount > 0;

  // ---- Session lifecycle ----------------------------------------------

  Future<void> start() async {
    if (_phase == MeshPhase.starting || _phase == MeshPhase.running) return;
    _error = null;
    _setPhase(MeshPhase.starting);

    if (!await _ensurePermissions()) {
      _setPhase(MeshPhase.permissionDenied);
      return;
    }

    try {
      await _nearby.startAdvertising(
        userName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );
      await _nearby.startDiscovery(
        userName,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: serviceId,
      );
      if (_disposed) return;
      _addSystem('Broadcasting as "$userName" and scanning for neighbours.');
      _setPhase(MeshPhase.running);
    } catch (e) {
      await _shutdown();
      if (_disposed) return;
      _error = 'Could not start nearby networking: $e';
      _setPhase(MeshPhase.error);
    }
  }

  Future<void> stop() async {
    await _shutdown();
    if (_disposed) return;
    _peers.clear();
    _setPhase(MeshPhase.idle);
  }

  Future<void> _shutdown() async {
    // Each call is guarded separately: stopping something that never
    // started throws on some devices and must not skip the rest.
    for (final action in <Future<void> Function()>[
      _nearby.stopAdvertising,
      _nearby.stopDiscovery,
      _nearby.stopAllEndpoints,
    ]) {
      try {
        await action();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---- Permissions ----------------------------------------------------

  Future<bool> _ensurePermissions() async {
    final results = await <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    // Permissions that don't exist on the running Android version report as
    // granted, so "all granted" is the right test on every API level.
    final granted = results.values.every((s) => s.isGranted || s.isLimited);
    _permanentlyDenied = results.values.any((s) => s.isPermanentlyDenied);

    try {
      _locationServiceOn =
          await Permission.locationWhenInUse.serviceStatus.isEnabled;
    } catch (_) {
      _locationServiceOn = true;
    }
    return granted;
  }

  Future<void> openSettings() => openAppSettings();

  // ---- Discovery callbacks --------------------------------------------

  void _onEndpointFound(String id, String name, String foundServiceId) {
    final existing = _peers[id];
    if (existing != null) return;
    _peers[id] = MeshPeer(endpointId: id, name: name);
    notifyListeners();
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    // Keep peers that are mid-handshake or connected: losing the *advert*
    // does not mean the connection itself dropped.
    if (_peers[id]?.status == PeerStatus.discovered) {
      _peers.remove(id);
      notifyListeners();
    }
  }

  // ---- Pairing / handshake --------------------------------------------

  /// Step 1 (initiator): ask a discovered peer to connect.
  Future<void> connect(String endpointId) async {
    final peer = _peers[endpointId];
    if (peer == null || peer.status != PeerStatus.discovered) return;
    _peers[endpointId] = peer.copyWith(status: PeerStatus.connecting);
    notifyListeners();

    try {
      await _nearby.requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      // Typical cause: both phones tapped "Connect" at the same moment, or
      // the peer is already connected to us.
      _revertToDiscovered(endpointId);
      _error = 'Could not connect to ${peer.name}: $e';
      notifyListeners();
    }
  }

  /// Step 2 (both sides): the secure channel exists and each device now has
  /// the same short authentication token to show its user.
  void _onConnectionInitiated(String id, ConnectionInfo info) {
    final existing =
        _peers[id] ?? MeshPeer(endpointId: id, name: info.endpointName);
    _peers[id] = existing.copyWith(
      name: info.endpointName,
      status: PeerStatus.verifying,
      authToken: info.authenticationToken,
      incoming: info.isIncomingConnection,
      localAccepted: false,
    );
    notifyListeners();
  }

  /// Step 3: the user confirmed the codes match. The connection only opens
  /// once *both* devices have accepted.
  Future<void> acceptPeer(String endpointId) async {
    final peer = _peers[endpointId];
    if (peer == null || peer.status != PeerStatus.verifying) return;
    _peers[endpointId] = peer.copyWith(localAccepted: true);
    notifyListeners();
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: (String id, PayloadTransferUpdate update) {},
      );
    } catch (e) {
      _revertToDiscovered(endpointId);
      _error = 'Could not accept ${peer.name}: $e';
      notifyListeners();
    }
  }

  Future<void> rejectPeer(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
    } catch (_) {}
    _revertToDiscovered(endpointId);
    notifyListeners();
  }

  void _onConnectionResult(String id, Status status) {
    final peer = _peers[id];
    if (peer == null) return;
    switch (status) {
      case Status.CONNECTED:
        _peers[id] = peer.copyWith(
          status: PeerStatus.connected,
          clearAuth: true,
          localAccepted: true,
        );
        _addSystem('Connected to ${peer.name}.');
      case Status.REJECTED:
        _revertToDiscovered(id);
        _addSystem('${peer.name} declined the connection.');
      case Status.ERROR:
        _revertToDiscovered(id);
        _addSystem('Connection with ${peer.name} failed.');
    }
    notifyListeners();
  }

  Future<void> disconnect(String endpointId) async {
    final peer = _peers[endpointId];
    try {
      await _nearby.disconnectFromEndpoint(endpointId);
    } catch (_) {}
    if (peer != null) {
      _revertToDiscovered(endpointId);
      _addSystem('Disconnected from ${peer.name}.');
    }
    notifyListeners();
  }

  void _onDisconnected(String id) {
    final peer = _peers[id];
    if (peer == null) return;
    if (peer.status == PeerStatus.connected) {
      _addSystem('${peer.name} went out of range.');
    }
    // The endpoint may still be advertising, so it goes back to "nearby";
    // onEndpointLost will remove it if it has actually vanished.
    _revertToDiscovered(id);
    notifyListeners();
  }

  void _revertToDiscovered(String id) {
    final peer = _peers[id];
    if (peer == null) return;
    _peers[id] = peer.copyWith(
      status: PeerStatus.discovered,
      clearAuth: true,
      localAccepted: false,
    );
  }

  // ---- Payload routing --------------------------------------------------

  /// Sends a new message to every connected neighbour.
  void sendMessage(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty || !canSend) return;

    final message = MeshMessage(
      id: '$deviceId-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
      originId: deviceId,
      senderName: userName,
      text: text.length > maxTextLength ? text.substring(0, maxTextLength) : text,
      sentAt: DateTime.now(),
      ttl: maxHops,
    );
    _remember(message.id);
    _messages.add(message);
    _forward(message, exceptEndpoint: null);
    notifyListeners();
  }

  void _onPayloadReceived(String fromEndpoint, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null) return;

    final message = MeshMessage.tryDecode(bytes);
    if (message == null || message.originId == deviceId) return;
    if (_seen.contains(message.id)) return; // already arrived via another path

    _remember(message.id);
    _messages.add(message);

    // Relay to everyone except the neighbour it came from. This is what
    // makes A <-> B <-> C work even though A and C never connected.
    if (message.ttl > 1) {
      _forward(message.relayed(), exceptEndpoint: fromEndpoint);
    }
    notifyListeners();
  }

  void _forward(MeshMessage message, {required String? exceptEndpoint}) {
    final Uint8List bytes = message.encode();
    for (final peer in _peers.values) {
      if (peer.status != PeerStatus.connected) continue;
      if (peer.endpointId == exceptEndpoint) continue;
      unawaited(
        _nearby.sendBytesPayload(peer.endpointId, bytes).catchError((_) {}),
      );
    }
  }

  void _remember(String id) {
    _seen.add(id);
    if (_seen.length > _maxSeen) {
      _seen.remove(_seen.first); // Set preserves insertion order
    }
  }

  // ---- Helpers ----------------------------------------------------------

  void _addSystem(String text) => _messages.add(MeshMessage.system(text));

  void _setPhase(MeshPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  static String _randomId() {
    final rng = Random.secure();
    return List<String>.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}