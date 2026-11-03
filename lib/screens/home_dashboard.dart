import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../widgets/activity_menu_card.dart';
import '../widgets/welcome_card.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // context.watch subscribes this widget to AppState so it rebuilds
    // instantly when the theme or profile name changes on Settings.
    final appState = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          // LayoutBuilder + a width breakpoint lets the dashboard switch
          // between a stacked Column (phones) and a multi-column Wrap
          // (tablets/desktop) without ever overflowing.
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final cards = [
              _networkMonitorCard(context),
              _diagnosticsCard(context),
              _meshChatCard(context),
              _geofenceCard(context),
            ];
            final columns = constraints.maxWidth > 900 ? 3 : 2;
            final cardWidth =
                (constraints.maxWidth - 40 - 16 * (columns - 1)) / columns;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting + connection pill + settings, grouped in one card.
                  WelcomeCard(
                    profileName: appState.profileName,
                    onPillTap: () =>
                        Navigator.pushNamed(context, '/network-diagnostics'),
                    onSettingsTap: () =>
                        Navigator.pushNamed(context, '/settings'),
                  ),
                  const SizedBox(height: 28),
                  Text('Activities', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 11),
                  // Cards no longer fit in one Row, so wide screens use
                  // a Wrap of fixed-width cards (2 or 3 columns) instead.
                  isWide
                      ? Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final card in cards)
                              SizedBox(width: cardWidth, child: card),
                          ],
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              cards[i],
                            ],
                          ],
                        ),
                  const SizedBox(height: 24),
                  Text('Recent Activity', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (appState.activityLog.isEmpty)
                    Text(
                      'No activity logged yet. Complete an activity to see it here.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ...appState.activityLog.take(5).map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(entry, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _networkMonitorCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 2: Network Monitor',
      subtitle: 'Live Wi-Fi/Cellular status & handover recovery',
      icon: Icons.network_check_outlined,
      color: Colors.deepOrange,
      onTap: () => Navigator.pushNamed(context, '/network-monitor'),
    );
  }

  Widget _diagnosticsCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 3: Network Diagnostics ',
      subtitle: 'Live speed/ping tiers & adaptive media demo',
      icon: Icons.speed,
      color: Colors.deepPurple,
      onTap: () => Navigator.pushNamed(context, '/network-diagnostics'),
    );
  }

  Widget _meshChatCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 4: Local Mesh Chat',
      subtitle: 'Serverless peer-to-peer messaging, no internet needed',
      icon: Icons.hub_outlined,
      color: Colors.green,
      onTap: () => Navigator.pushNamed(context, '/mesh-chat'),
    );
  }

  Widget _geofenceCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 5: Geofence Map',
      subtitle: 'Custom map markers with live enter/exit geofence tracking',
      icon: Icons.add_location_alt_outlined,
      color: Colors.redAccent,
      onTap: () => Navigator.pushNamed(context, '/geofence-map'),
    );
  }
}