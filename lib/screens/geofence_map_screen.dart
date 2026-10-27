import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/geofence_controller.dart';
import '../models/geofence_models.dart';

/// Icons a custom place can use (stored by index in [CustomPlace.iconIndex]).
const List<IconData> placeIcons = [
  Icons.home,
  Icons.groups,
  Icons.landscape,
  Icons.menu_book,
  Icons.storefront,
  Icons.park,
  Icons.restaurant,
  Icons.star,
];

/// Activity 5: custom map + geofencing tracker.
///
/// The controller is created here (not in main.dart) so GPS tracking only
/// runs while this screen is open, and it is wired to [AppState] so each
/// geofence enter/exit also shows up under "Recent Activity" on the Home
/// Dashboard.
class GeofenceMapScreen extends StatelessWidget {
  const GeofenceMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return ChangeNotifierProvider(
      create: (_) => GeofenceController(onLog: appState.logActivity)..start(),
      child: const _GeofenceMapView(),
    );
  }
}

class _GeofenceMapView extends StatefulWidget {
  const _GeofenceMapView();

  @override
  State<_GeofenceMapView> createState() => _GeofenceMapViewState();
}

class _GeofenceMapViewState extends State<_GeofenceMapView> {
  final MapController _mapController = MapController();
  ValueNotifier<GeofenceEvent?>? _eventNotifier;
  int _tab = 0; // 0 = locations, 1 = events
  bool _followed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eventNotifier == null) {
      _eventNotifier = context.read<GeofenceController>().lastEvent;
      _eventNotifier!.addListener(_onEvent);
    }
  }

  @override
  void dispose() {
    _eventNotifier?.removeListener(_onEvent);
    _mapController.dispose();
    super.dispose();
  }

  void _onEvent() {
    final e = _eventNotifier?.value;
    if (e == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      backgroundColor:
          e.isEnter ? Colors.green.shade700 : Colors.orange.shade800,
      content: Row(
        children: [
          Icon(e.isEnter ? Icons.login : Icons.logout, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(e.message)),
        ],
      ),
    ));
  }

  void _moveTo(LatLng point, {double zoom = 18}) {
    _mapController.move(point, zoom);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GeofenceController>();

    // Center the camera on the user the first time a real fix arrives.
    if (!_followed && c.position != null && !c.simulate) {
      _followed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveTo(c.position!, zoom: 17);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Map'),
        actions: [
          Row(
            children: [
              const Text('Simulate', style: TextStyle(fontSize: 12)),
              Switch(
                value: c.simulate,
                onChanged: (v) {
                  c.setSimulate(v);
                  if (v) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Simulation on: tap anywhere on the map to move.'),
                    ));
                  }
                },
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _confirmReset(c);
              if (v == 'clear') c.clearEvents();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear event log')),
              PopupMenuItem(
                  value: 'reset', child: Text('Reset places to defaults')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusBanner(controller: c),
            Expanded(flex: 5, child: _buildMap(c)),
            _buildTabs(),
            Expanded(
              flex: 4,
              child: _tab == 0 ? _buildPlaceList(c) : _buildEventLog(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(GeofenceController c) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: kMapCenter,
            initialZoom: 16.5,
            minZoom: 3,
            maxZoom: 19,
            onTap: (_, point) {
              if (c.simulate) c.simulateAt(point);
            },
            onLongPress: (_, point) => _addPlaceAt(c, point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.lab_compiler_app',
            ),
            // Geofence circles, sized in real meters so they scale with zoom.
            CircleLayer(
              circles: [
                for (final p in c.places)
                  CircleMarker(
                    point: p.point,
                    radius: p.radiusMeters,
                    useRadiusInMeter: true,
                    color: (c.isInside(p.id) ? Colors.green : Colors.indigo)
                        .withValues(alpha: 0.18),
                    borderColor:
                        c.isInside(p.id) ? Colors.green : Colors.indigo,
                    borderStrokeWidth: 2,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final p in c.places)
                  Marker(
                    point: p.point,
                    width: 110,
                    height: 70,
                    child: GestureDetector(
                      onTap: () => _showPlaceSheet(c, p),
                      child: _PlaceMarker(
                        place: p,
                        inside: c.isInside(p.id),
                      ),
                    ),
                  ),
                if (c.position != null)
                  Marker(
                    point: c.position!,
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'geo_locate',
                tooltip: 'Go to my location',
                onPressed:
                    c.position == null ? null : () => _moveTo(c.position!),
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'geo_fit',
                tooltip: 'Show all places',
                onPressed: c.places.isEmpty ? null : () => _fitAll(c),
                child: const Icon(Icons.zoom_out_map),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'geo_add',
                tooltip: 'Add place',
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                onPressed: () => _addPlaceAt(
                  c,
                  c.position ?? _mapController.camera.center,
                ),
                child: const Icon(Icons.add_location_alt),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Long-press the map to add a place',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  void _fitAll(GeofenceController c) {
    final points = [
      for (final p in c.places) p.point,
      if (c.position != null) c.position!,
    ];
    if (points.length < 2) {
      _moveTo(points.first);
      return;
    }
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(60),
      maxZoom: 18,
    ));
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
              value: 0,
              icon: Icon(Icons.place_outlined),
              label: Text('Places')),
          ButtonSegment(
              value: 1, icon: Icon(Icons.history), label: Text('Event log')),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
    );
  }

  Widget _buildPlaceList(GeofenceController c) {
    if (c.places.isEmpty) {
      return const Center(child: Text('No places yet. Long-press the map.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: c.places.length,
      itemBuilder: (context, i) {
        final p = c.places[i];
        final inside = c.isInside(p.id);
        final d = c.distanceTo(p);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: inside ? Colors.green : Colors.indigo,
            child: Icon(placeIcons[p.iconIndex % placeIcons.length],
                color: Colors.white, size: 20),
          ),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            d == null
                ? 'Radius ${p.radiusMeters.round()} m · waiting for location'
                : 'Radius ${p.radiusMeters.round()} m · ${_fmtDistance(d)} away',
          ),
          trailing: Chip(
            label: Text(inside ? 'INSIDE' : 'outside'),
            visualDensity: VisualDensity.compact,
            backgroundColor: inside ? Colors.green.shade100 : null,
          ),
          onTap: () {
            _moveTo(p.point);
            _showPlaceSheet(c, p);
          },
        );
      },
    );
  }

  Widget _buildEventLog(GeofenceController c) {
    if (c.events.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No geofence events yet. Walk into a circle (or use Simulate and '
            'tap inside one).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: c.events.length,
      itemBuilder: (context, i) {
        final e = c.events[i];
        final t = e.time;
        String two(int n) => n.toString().padLeft(2, '0');
        return ListTile(
          dense: true,
          leading: Icon(
            e.isEnter ? Icons.login : Icons.logout,
            color: e.isEnter ? Colors.green : Colors.orange,
          ),
          title: Text(e.message),
          subtitle: Text(
              '${two(t.hour)}:${two(t.minute)}:${two(t.second)} · ${_fmtDistance(e.distanceMeters)} from center'),
        );
      },
    );
  }

  // ---------------------------------------------------------- place actions

  Future<void> _addPlaceAt(GeofenceController c, LatLng point) async {
    final result = await showDialog<_PlaceFormResult>(
      context: context,
      builder: (_) => const _PlaceFormDialog(title: 'New place'),
    );
    if (result == null) return;
    final place = c.addPlace(
      name: result.name,
      description: result.description,
      point: point,
      radius: result.radius,
      iconIndex: result.iconIndex,
    );
    _moveTo(place.point);
  }

  Future<void> _editPlace(GeofenceController c, CustomPlace p) async {
    final result = await showDialog<_PlaceFormResult>(
      context: context,
      builder: (_) => _PlaceFormDialog(title: 'Edit place', initial: p),
    );
    if (result == null) return;
    c.updatePlace(
      p,
      name: result.name,
      description: result.description,
      radius: result.radius,
      iconIndex: result.iconIndex,
    );
  }

  void _showPlaceSheet(GeofenceController c, CustomPlace p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              if (p.description.isNotEmpty) Text(p.description),
              const SizedBox(height: 8),
              Text(
                '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'
                ' · radius ${p.radiusMeters.round()} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _editPlace(c, p);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.my_location, size: 18),
                    label: const Text('Move to my location'),
                    onPressed: c.position == null
                        ? null
                        : () {
                            c.updatePlace(p, point: c.position!);
                            Navigator.pop(sheetContext);
                          },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      c.deletePlace(p);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(GeofenceController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset places?'),
        content: const Text(
            'This replaces all your places with the 5 starter locations.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) c.resetToDefaults();
  }
}

String _fmtDistance(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(2)} km'
    : '${meters.round()} m';

// ---------------------------------------------------------------- widgets

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({required this.place, required this.inside});

  final CustomPlace place;
  final bool inside;

  @override
  Widget build(BuildContext context) {
    final color = inside ? Colors.green : Colors.indigo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
          child: Icon(placeIcons[place.iconIndex % placeIcons.length],
              color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            place.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black87,
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final GeofenceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    late final String text;
    late final Color color;
    IconData icon = Icons.gps_fixed;
    Widget? action;

    switch (c.status) {
      case TrackingStatus.starting:
        text = 'Getting your location…';
        color = Colors.blueGrey;
        icon = Icons.gps_not_fixed;
      case TrackingStatus.tracking:
        final acc = c.accuracy;
        text = c.position == null
            ? 'Waiting for GPS fix…'
            : 'Live tracking${acc != null ? ' (±${acc.round()} m)' : ''}'
                ' · inside ${c.insideCount} of ${c.places.length} zones';
        color = Colors.green.shade700;
      case TrackingStatus.simulated:
        text = 'Simulation mode · tap the map to move · '
            'inside ${c.insideCount} of ${c.places.length} zones';
        color = Colors.deepPurple;
        icon = Icons.touch_app;
      case TrackingStatus.serviceOff:
        text = 'Location services are turned off.';
        color = Colors.orange.shade800;
        icon = Icons.location_off;
        action = TextButton(
            onPressed: c.openLocationSettings, child: const Text('Settings'));
      case TrackingStatus.denied:
        text = 'Location permission denied.';
        color = Colors.red.shade700;
        icon = Icons.location_disabled;
        action =
            TextButton(onPressed: c.retryTracking, child: const Text('Allow'));
      case TrackingStatus.deniedForever:
        text = 'Permission permanently denied. Enable it in app settings.';
        color = Colors.red.shade700;
        icon = Icons.location_disabled;
        action = TextButton(
            onPressed: c.openAppSettings, child: const Text('Settings'));
      case TrackingStatus.error:
        text = 'Could not read your location.';
        color = Colors.red.shade700;
        icon = Icons.error_outline;
        action =
            TextButton(onPressed: c.retryTracking, child: const Text('Retry'));
    }

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            if (action != null)
              DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceFormResult {
  _PlaceFormResult(this.name, this.description, this.radius, this.iconIndex);
  final String name;
  final String description;
  final double radius;
  final int iconIndex;
}

class _PlaceFormDialog extends StatefulWidget {
  const _PlaceFormDialog({required this.title, this.initial});

  final String title;
  final CustomPlace? initial;

  @override
  State<_PlaceFormDialog> createState() => _PlaceFormDialogState();
}

class _PlaceFormDialogState extends State<_PlaceFormDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _desc =
      TextEditingController(text: widget.initial?.description ?? '');
  late double _radius = widget.initial?.radiusMeters ?? 40;
  late int _icon = widget.initial?.iconIndex ?? 0;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            Text('Geofence radius: ${_radius.round()} m'),
            Slider(
              value: _radius,
              min: 10,
              max: 200,
              divisions: 19,
              label: '${_radius.round()} m',
              onChanged: (v) => setState(() => _radius = v),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < placeIcons.length; i++)
                  ChoiceChip(
                    label: Icon(placeIcons[i], size: 18),
                    selected: _icon == i,
                    onSelected: (_) => setState(() => _icon = i),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _PlaceFormResult(name, _desc.text.trim(), _radius, _icon),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}