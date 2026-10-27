import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geofence_models.dart';

/// Center of the map: Lianga, Surigao del Sur. Change this (and the sample
/// places below) to your own barangay if you prefer.
const LatLng kMapCenter = LatLng(8.6330, 126.0960);

const String _prefsKey = 'geofence_places_v1';

/// Five starter places inside one area. The coordinates are PLACEHOLDERS
/// spaced a few hundred meters apart: use "Move to my location" (or long-press
/// the map) to relocate each one onto your real house / secret spot.
List<CustomPlace> defaultPlaces() => [
      CustomPlace(
        id: 'p1',
        name: 'My House',
        description: 'Home sweet home (not on Google Maps).',
        latitude: 8.6330,
        longitude: 126.0960,
        radiusMeters: 40,
        iconIndex: 0,
      ),
      CustomPlace(
        id: 'p2',
        name: "Friend's House",
        description: 'Barkada hangout spot.',
        latitude: 8.6345,
        longitude: 126.0985,
        radiusMeters: 40,
        iconIndex: 1,
      ),
      CustomPlace(
        id: 'p3',
        name: 'Hidden Viewpoint',
        description: 'Undiscovered spot with a view of the bay.',
        latitude: 8.6310,
        longitude: 126.0990,
        radiusMeters: 50,
        iconIndex: 2,
      ),
      CustomPlace(
        id: 'p4',
        name: 'Secret Study Corner',
        description: 'Quiet place where I code.',
        latitude: 8.6315,
        longitude: 126.0935,
        radiusMeters: 35,
        iconIndex: 3,
      ),
      CustomPlace(
        id: 'p5',
        name: 'Sari-Sari Store',
        description: 'Neighborhood store, the best snacks.',
        latitude: 8.6350,
        longitude: 126.0940,
        radiusMeters: 30,
        iconIndex: 4,
      ),
    ];

/// Controller for the geofencing activity: owns the custom places, the live
/// (or simulated) position, and the enter/exit event log.
class GeofenceController extends ChangeNotifier {
  GeofenceController({this.onLog});

  /// Called for every enter/exit so it can be mirrored on the Home
  /// Dashboard's "Recent Activity" list (via AppState.logActivity).
  final void Function(String message)? onLog;

  final GeofenceEngine _engine = GeofenceEngine();
  final List<CustomPlace> _places = [];
  final List<GeofenceEvent> _events = [];
  StreamSubscription<Position>? _sub;

  TrackingStatus _status = TrackingStatus.starting;
  LatLng? _position;
  double? _accuracy;
  bool _simulate = false;
  bool _disposed = false;

  /// Fires after each enter/exit so the screen can show a SnackBar.
  final ValueNotifier<GeofenceEvent?> lastEvent = ValueNotifier(null);

  List<CustomPlace> get places => List.unmodifiable(_places);
  List<GeofenceEvent> get events => List.unmodifiable(_events);
  TrackingStatus get status => _status;
  LatLng? get position => _position;
  double? get accuracy => _accuracy;
  bool get simulate => _simulate;
  bool isInside(String id) => _engine.isInside(id);
  int get insideCount => _engine.insideIds.length;

  double? distanceTo(CustomPlace p) {
    final pos = _position;
    if (pos == null) return null;
    return haversineMeters(
        pos.latitude, pos.longitude, p.latitude, p.longitude);
  }

  // ---------------------------------------------------------------- startup

  Future<void> start() async {
    await _loadPlaces();
    await _startLocation();
  }

  Future<void> _loadPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => CustomPlace.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _places
            ..clear()
            ..addAll(list);
          _notify();
          return;
        }
      }
    } catch (_) {
      // Corrupt/unavailable storage: fall back to the defaults.
    }
    _places
      ..clear()
      ..addAll(defaultPlaces());
    _notify();
  }

  Future<void> _savePlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_places.map((p) => p.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _startLocation() async {
    if (_simulate) return;
    _setStatus(TrackingStatus.starting);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setStatus(TrackingStatus.serviceOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        _setStatus(TrackingStatus.denied);
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        _setStatus(TrackingStatus.deniedForever);
        return;
      }

      await _sub?.cancel();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // meters moved before a new fix is delivered
        ),
      ).listen(
        (pos) {
          if (_simulate) return;
          _accuracy = pos.accuracy;
          _handlePosition(LatLng(pos.latitude, pos.longitude));
        },
        onError: (_) => _setStatus(TrackingStatus.error),
      );
      _setStatus(TrackingStatus.tracking);

      // Get a first fix quickly instead of waiting for the user to move.
      final first = await Geolocator.getCurrentPosition();
      if (!_simulate) {
        _accuracy = first.accuracy;
        _handlePosition(LatLng(first.latitude, first.longitude));
      }
    } catch (_) {
      if (_status == TrackingStatus.starting) _setStatus(TrackingStatus.error);
    }
  }

  Future<void> retryTracking() => _startLocation();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  // -------------------------------------------------------------- simulation

  /// Simulation mode lets you test geofences without walking around (and on
  /// emulators/desktop): tap the map to teleport your position.
  void setSimulate(bool value) {
    if (_simulate == value) return;
    _simulate = value;
    _engine.reset();
    if (value) {
      _sub?.cancel();
      _sub = null;
      _accuracy = null;
      _status = TrackingStatus.simulated;
      _position ??= kMapCenter;
      _handlePosition(_position!);
    } else {
      _position = null;
      _startLocation();
    }
    _notify();
  }

  void simulateAt(LatLng point) {
    if (!_simulate) return;
    _handlePosition(point);
  }

  // --------------------------------------------------------------- geofencing

  void _handlePosition(LatLng pos) {
    if (_disposed) return;
    _position = pos;
    final newEvents = _engine.update(pos.latitude, pos.longitude, _places);
    for (final e in newEvents) {
      _events.insert(0, e);
      onLog?.call('Geofence: ${e.message}');
      lastEvent.value = e;
    }
    if (_events.length > 60) _events.removeRange(60, _events.length);
    _notify();
  }

  // ------------------------------------------------------------ place editing

  /// Adds a place; returns it so the caller can move the camera.
  CustomPlace addPlace({
    required String name,
    required String description,
    required LatLng point,
    double radius = 40,
    int iconIndex = 0,
  }) {
    final place = CustomPlace(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      description: description,
      latitude: point.latitude,
      longitude: point.longitude,
      radiusMeters: radius,
      iconIndex: iconIndex,
    );
    _places.add(place);
    _afterEdit();
    return place;
  }

  void updatePlace(
    CustomPlace place, {
    String? name,
    String? description,
    LatLng? point,
    double? radius,
    int? iconIndex,
  }) {
    if (name != null) place.name = name;
    if (description != null) place.description = description;
    if (point != null) {
      place.latitude = point.latitude;
      place.longitude = point.longitude;
    }
    if (radius != null) place.radiusMeters = radius;
    if (iconIndex != null) place.iconIndex = iconIndex;
    _afterEdit();
  }

  void deletePlace(CustomPlace place) {
    _places.removeWhere((p) => p.id == place.id);
    _engine.forget(place.id);
    _afterEdit();
  }

  void resetToDefaults() {
    _places
      ..clear()
      ..addAll(defaultPlaces());
    _engine.reset();
    _afterEdit();
  }

  void clearEvents() {
    _events.clear();
    _notify();
  }

  void _afterEdit() {
    _savePlaces();
    // Re-evaluate so moving/resizing a fence updates inside/outside at once.
    if (_position != null) {
      _handlePosition(_position!);
    } else {
      _notify();
    }
  }

  void _setStatus(TrackingStatus s) {
    _status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    lastEvent.dispose();
    super.dispose();
  }
}