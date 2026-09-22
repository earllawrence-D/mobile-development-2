import 'package:flutter/material.dart';

import '../models/diagnostic_report.dart';
import 'health_tier_visuals.dart';

/// Demonstrates the core objective of the diagnostic tool: the *same*
/// content area renders rich, high-resolution multimedia when the
/// connection is healthy, one reduced-resolution image when it is merely
/// fair, and collapses to lightweight local placeholders (with zero
/// network requests) when it is poor, degraded, or offline.
class AdaptiveMediaPanel extends StatelessWidget {
  const AdaptiveMediaPanel({super.key, required this.tier});

  /// Current global health tier (`null` while the first cycle is running).
  final HealthTier? tier;

  @override
  Widget build(BuildContext context) {
    final current = tier;
    final showHighRes = current == HealthTier.excellent;
    final showReduced = current == HealthTier.fair;

    final modeLabel = showHighRes
        ? 'High-res multimedia'
        : showReduced
            ? 'Reduced resolution'
            : 'Lightweight placeholders';
    final modeColor = current == null ? Colors.blueGrey : tierColor(current);

    final caption = switch (current) {
      null => 'Measuring — lightweight placeholders until real data arrives.',
      HealthTier.excellent =>
        'Connection is excellent: streaming full-quality media over the network.',
      HealthTier.fair =>
        'Connection is fair: one reduced-resolution image keeps the UI smooth.',
      HealthTier.poor =>
        'Connection is poor: network media suppressed, placeholders only.',
      HealthTier.degraded =>
        'Connection is unstable: network media suppressed for stability.',
      HealthTier.offline =>
        'Offline: rendering local placeholders, zero network requests.',
    };

    final boxes = <Widget>[];
    if (showHighRes) {
      boxes
        ..add(const _MediaBox.network(
            'https://picsum.photos/seed/labmedia-a/640/420'))
        ..add(const _MediaBox.network(
            'https://picsum.photos/seed/labmedia-b/640/420'));
    } else if (showReduced) {
      boxes.add(const _MediaBox.network(
          'https://picsum.photos/seed/labmedia-a/480/320'));
    } else {
      // Poor / degraded / offline / measuring: no network at all.
      final icon = _placeholderIcon(current);
      final label = _placeholderLabel(current);
      boxes
        ..add(_MediaBox.placeholder(icon, label))
        ..add(_MediaBox.placeholder(icon, label));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Adaptive Content Delivery',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(modeLabel, style: const TextStyle(fontSize: 12)),
                  backgroundColor: modeColor.withValues(alpha: 0.15),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(caption, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return isWide
                  ? Row(
                      children: [
                        for (var i = 0; i < boxes.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: boxes[i]),
                        ],
                      ],
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < boxes.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          boxes[i],
                        ],
                      ],
                    );
            }),
          ],
        ),
      ),
    );
  }

  IconData _placeholderIcon(HealthTier? tier) => switch (tier) {
        HealthTier.degraded => Icons.warning,
        HealthTier.offline => Icons.wifi_off,
        HealthTier.poor => Icons.image_not_supported,
        _ => Icons.hourglass_empty, // measuring
      };

  String _placeholderLabel(HealthTier? tier) => switch (tier) {
        HealthTier.degraded => 'Placeholder — unstable link',
        HealthTier.offline => 'Placeholder — offline',
        HealthTier.poor => 'Placeholder — low bandwidth',
        _ => 'Placeholder — measuring',
      };
}

/// One content slot: either a network image (healthy tiers) or a
/// lightweight local placeholder tile (degraded tiers).
class _MediaBox extends StatelessWidget {
  const _MediaBox.network(this.url)
      : icon = null,
        label = null;

  const _MediaBox.placeholder(this.icon, this.label) : url = null;

  final String? url;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final image = url;
    if (image != null) {
      child = Image.network(
        image,
        fit: BoxFit.cover,
        loadingBuilder: (context, image, progress) => progress == null
            ? image
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
        errorBuilder: (_, __, ___) => const _PlaceholderBody(
          icon: Icons.broken_image,
          label: 'Media unavailable — check connectivity',
        ),
      );
    } else {
      child = _PlaceholderBody(icon: icon!, label: label!);
    }

    return AspectRatio(
      aspectRatio: 3 / 2,
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }
}

class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blueGrey.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.blueGrey),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}