import 'package:flutter/material.dart';

import '../models/diagnostic_report.dart';

/// Single source of truth for how each [HealthTier] is *presented* in the
/// UI (color, icon, wording). Every screen that visualizes the global
/// diagnostic state imports these helpers, so the tiers stay perfectly
/// consistent across the whole application.
Color tierColor(HealthTier tier) => switch (tier) {
      HealthTier.excellent => Colors.green,
      HealthTier.fair => Colors.amber,
      HealthTier.poor => Colors.red,
      HealthTier.degraded => Colors.deepPurple,
      HealthTier.offline => Colors.blueGrey,
    };

IconData tierIcon(HealthTier tier) => switch (tier) {
      HealthTier.excellent => Icons.check_circle,
      HealthTier.fair => Icons.info,
      HealthTier.poor => Icons.priority_high,
      HealthTier.degraded => Icons.warning,
      HealthTier.offline => Icons.wifi_off,
    };

String tierLabel(HealthTier tier) => switch (tier) {
      HealthTier.excellent => 'Excellent',
      HealthTier.fair => 'Fair',
      HealthTier.poor => 'Poor',
      HealthTier.degraded => 'Degraded',
      HealthTier.offline => 'Offline',
    };

/// One-line guidance shown under the tier label, describing exactly how
/// the app is adapting its content to this connection health.
String tierAdvice(HealthTier tier) => switch (tier) {
      HealthTier.excellent => 'Full high-resolution multimedia enabled.',
      HealthTier.fair => 'Reduced-resolution media to stay smooth.',
      HealthTier.poor => 'Lightweight placeholders only — bandwidth too low.',
      HealthTier.degraded =>
        'Unstable connection — media suppressed for stability.',
      HealthTier.offline =>
        'No route to the test servers — local placeholders only.',
    };