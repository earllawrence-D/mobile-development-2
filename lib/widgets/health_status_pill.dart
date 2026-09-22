import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network_diagnostics.dart';
import 'health_tier_visuals.dart';

/// Compact, reusable badge showing the app-wide connection health tier.
///
/// It is its own `context.watch<NetworkDiagnostics>()` subscriber, so any
/// screen can drop it in (e.g. the Home app bar) and it will rebuild on
/// every new diagnostic cycle *without* rebuilding the whole screen —
/// that is the "broadcast across the application" part of the
/// global-state-injection requirement.
class HealthStatusPill extends StatelessWidget {
  const HealthStatusPill({super.key, this.onTap});

  /// Typically deep-links into the diagnostic dashboard.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final diagnostics = context.watch<NetworkDiagnostics>();
    final tier = diagnostics.tier;
    final idlePing = diagnostics.lastReport?.idlePingMs;

    final color = tier == null ? Colors.blueGrey : tierColor(tier);
    final label = tier == null
        ? 'Measuring…'
        : idlePing == null
            ? tierLabel(tier)
            : '${tierLabel(tier)} · $idlePing ms';

    return ActionChip(
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      onPressed: onTap,
    );
  }
}