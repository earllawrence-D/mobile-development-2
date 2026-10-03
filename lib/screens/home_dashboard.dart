import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../widgets/activity_menu_card.dart';
import '../widgets/health_status_pill.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // context.watch subscribes this widget to AppState so it rebuilds
    // instantly when the theme or profile name changes on Settings.
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Global connection-health badge. It watches NetworkDiagnostics
          // itself, so every new diagnostic cycle updates it app-wide,
          // and tapping it deep-links into the diagnostic dashboard.
          HealthStatusPill(
            onTap: () => Navigator.pushNamed(context, '/network-diagnostics'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          // LayoutBuilder + a width breakpoint lets the dashboard switch
          // between a stacked Column (phones) and a multi-column Wrap
          // (tablets/desktop) without ever overflowing.
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final cards = [
              _activityOneCard(context),
              _activityTwoCard(context),
              _networkMonitorCard(context),
              _diagnosticsCard(context),
              _meshChatCard(context),
            ];
            final columns = constraints.maxWidth > 900 ? 3 : 2;
            final cardWidth =
                (constraints.maxWidth - 40 - 16 * (columns - 1)) / columns;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${appState.profileName}!',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  Text('Activities', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  // Five cards no longer fit in one Row, so wide screens use
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

  Widget _activityOneCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 1: Titration Log',
      subtitle: 'Record trial counts and observations',
      icon: Icons.science_outlined,
      color: Colors.indigo,
      onTap: () => Navigator.pushNamed(context, '/activity-one'),
    );
  }

  Widget _activityTwoCard(BuildContext context) {
    return ActivityMenuCard(
      title: 'Activity 1.1: Data Notes',
      subtitle: 'Jot down quick lab notes',
      icon: Icons.edit_note_outlined,
      color: Colors.teal,
      onTap: () => Navigator.pushNamed(context, '/activity-two'),
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
}