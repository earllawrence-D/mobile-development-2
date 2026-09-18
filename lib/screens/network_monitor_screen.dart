import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/network_monitor.dart';

class NetworkMonitorScreen extends StatelessWidget {
  const NetworkMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // context.watch subscribes this screen to NetworkMonitor, so the status
    // banner and request list rebuild the instant a handover is detected.
    final monitor = context.watch<NetworkMonitor>();

    return Scaffold(
      appBar: AppBar(title: const Text('Network Monitor')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusBanner(status: monitor.status),
                  const SizedBox(height: 16),
                  isWide
                      ? Row(
                          children: [
                            Expanded(child: _startFetchButton(context)),
                            const SizedBox(width: 12),
                            Expanded(child: _clearButton(context, monitor)),
                          ],
                        )
                      : Column(
                          children: [
                            _startFetchButton(context),
                            const SizedBox(height: 8),
                            _clearButton(context, monitor),
                          ],
                        ),
                  const SizedBox(height: 20),
                  Text('Simulated Requests',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Turn off Wi-Fi (or enable airplane mode) while a request '
                    'is running to simulate a handover. It will queue '
                    'automatically and resume the moment a connection comes '
                    'back.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: monitor.requests.isEmpty
                        ? const Center(
                            child: Text(
                              'No requests yet. Tap "Start Large Dataset '
                              'Fetch" above to simulate one.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: monitor.requests.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _RequestTile(request: monitor.requests[index]),
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

  Widget _startFetchButton(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.cloud_download_outlined),
      label: const Text('Start Large Dataset Fetch'),
      onPressed: () {
        final request = context.read<NetworkMonitor>().startFetch();
        context
            .read<AppState>()
            .logActivity('Started network fetch (${request.id})');
      },
    );
  }

  Widget _clearButton(BuildContext context, NetworkMonitor monitor) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.clear_all),
      label: const Text('Clear Completed'),
      onPressed: monitor.requests.any((r) => r.state == RequestState.completed)
          ? () => context.read<NetworkMonitor>().clearCompleted()
          : null,
    );
  }
}

/// Shows the current active interface — Wi-Fi, Cellular, or Offline — driven
/// entirely by the connectivity stream in [NetworkMonitor].
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final NetworkStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      NetworkStatus.wifi => (Icons.wifi, 'Wi-Fi', Colors.green),
      NetworkStatus.cellular => (Icons.signal_cellular_alt, 'Cellular', Colors.blue),
      NetworkStatus.offline => (Icons.wifi_off, 'Offline', Colors.red),
    };

    return Card(
      color: color.withValues(alpha: 0.12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            // Expanded keeps this readable on narrow phone widths without
            // overflowing the row.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active Interface',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the request list, showing progress and current queue state.
class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final SimulatedRequest request;

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = switch (request.state) {
      RequestState.running => ('Running', Colors.blue),
      RequestState.queued => ('Queued — waiting for connection', Colors.orange),
      RequestState.completed => ('Completed', Colors.green),
    };

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.label,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(chipLabel, style: const TextStyle(fontSize: 12)),
                  backgroundColor: chipColor.withValues(alpha: 0.15),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: request.progress,
                minHeight: 8,
                color: chipColor,
                backgroundColor: chipColor.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(request.progress * 100).round()}%'),
                if (request.retryCount > 0)
                  Text(
                    'Resumed ${request.retryCount}x after handover',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
