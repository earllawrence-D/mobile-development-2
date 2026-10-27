import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// One user-defined location that does not exist on Google Maps
/// (a house, a hangout spot, a hidden viewpoint, ...), plus the radius of
/// the virtual fence drawn around it.
class CustomPlace {
  CustomPlace({
    required this.id,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 40,
    this.iconIndex = 0,
  });

  final String id;
  String name;
  String description;
  double latitude;
  double longitude;

  /// Geofence radius in meters.
  double radiusMeters;

  /// Index into placeIcons in the map screen (an int so it can be JSON-saved).
  int iconIndex;

  LatLng get point => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'lat': latitude,
        'lng': longitude,
        'radius': radiusMeters,
        'icon': iconIndex,
      };

  factory CustomPlace.fromJson(Map<String, dynamic> json) => CustomPlace(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        radiusMeters: (json['radius'] as num?)?.toDouble() ?? 40,
        iconIndex: (json['icon'] as int?) ?? 0,
      );
}

enum GeofenceEventType { enter, exit }

/// One entry in the geofence event log.
class GeofenceEvent {
  GeofenceEvent({
    required this.type,
    required this.placeName,
    required this.time,
    required this.distanceMeters,
  });

  final GeofenceEventType type;
  final String placeName;
  final DateTime time;
  final double distanceMeters;

  bool get isEnter => type == GeofenceEventType.enter;

  String get message => isEnter ? 'Entered $placeName' : 'Left $placeName';
}

/// Where the "you are here" position is coming from / why it is missing.
enum TrackingStatus {
  starting,
  tracking,
  simulated,
  serviceOff,
  denied,
  deniedForever,
  error,
}

const double _earthRadiusMeters = 6371000;

/// Great-circle (haversine) distance between two coordinates, in meters.
/// This is the core of the geofence test: `distance <= radius` means inside.
double haversineMeters(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

/// Pure geofence state machine, kept free of Flutter/plugins so it can be
/// unit-tested. Feed it positions; it reports enter/exit transitions.
///
/// A small [exitBuffer] (hysteresis) stops GPS jitter on the fence edge from
/// producing a flood of enter/exit events.
class GeofenceEngine {
  GeofenceEngine({this.exitBuffer = 5});

  final double exitBuffer;
  final Set<String> _inside = {};

  Set<String> get insideIds => Set.unmodifiable(_inside);
  bool isInside(String id) => _inside.contains(id);

  void reset() => _inside.clear();

  /// Forget a place (e.g. it was deleted) without emitting an exit event.
  void forget(String id) => _inside.remove(id);

  /// Evaluates [places] against the position and returns the transitions.
  List<GeofenceEvent> update(
    double lat,
    double lng,
    Iterable<CustomPlace> places, {
    DateTime? now,
  }) {
    final events = <GeofenceEvent>[];
    final time = now ?? DateTime.now();
    for (final place in places) {
      final d = haversineMeters(lat, lng, place.latitude, place.longitude);
      final wasInside = _inside.contains(place.id);
      if (!wasInside && d <= place.radiusMeters) {
        _inside.add(place.id);
        events.add(GeofenceEvent(
          type: GeofenceEventType.enter,
          placeName: place.name,
          time: time,
          distanceMeters: d,
        ));
      } else if (wasInside && d > place.radiusMeters + exitBuffer) {
        _inside.remove(place.id);
        events.add(GeofenceEvent(
          type: GeofenceEventType.exit,
          placeName: place.name,
          time: time,
          distanceMeters: d,
        ));
      }
    }
    return events;
  }
}