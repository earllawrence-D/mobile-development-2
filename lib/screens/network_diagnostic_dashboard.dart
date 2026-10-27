import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/diagnostic_report.dart';
import '../models/network_diagnostics.dart';
import '../widgets/adaptive_media_panel.dart';
import '../widgets/health_tier_visuals.dart';

/// Live view over the global [NetworkDiagnostics] tool.
///
/// Shows the classified health tier, the raw measurements of the last
/// cycle (idle ping / download + load ping / upload + upload ping /
/// packet loss), a step-by-step progress checklist while a cycle runs,
/// the download-speed history sparkline, the threshold legend, and the
/// adaptive media panel that demonstrates the connection-driven UI
/// switching objective.
class NetworkDiagnosticDashboard extends StatelessWidget {
  const NetworkDiagnosticDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Watching the global provider here is what keeps this screen live:
    // every phase change and every finished cycle rebuilds it.
    final diagnostics = context.watch<NetworkDiagnostics>();
    final report = diagnostics.lastReport;
    final tier = diagnostics.tier;

    return Scaffold(
      appBar: AppBar(title: const Text('Network Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _TierBanner(tier: tier, report: report),
            if (diagnostics.isRunning) ...[
              const SizedBox(height: 16),
              _PhaseChecklist(current: diagnostics.phase),
            ],
            if (diagnostics.lastError != null) ...[
              const SizedBox(height: 12),
              _ErrorNote(message: diagnostics.lastError!),
            ],
            const SizedBox(height: 20),
            Text('Live Metrics', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _MetricsGrid(report: report),
            const SizedBox(height: 20),
            _ControlsRow(diagnostics: diagnostics),
            const SizedBox(height: 24),
            Text(
              'Download History (last cycles)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _HistorySparkline(history: diagnostics.history),
            const SizedBox(height: 24),
            AdaptiveMediaPanel(tier: tier),
            const SizedBox(height: 24),
            const _ThresholdLegend(),
          ],
        ),
      ),
    );
  }
}

/// Color-coded hero card summarizing the current global tier.
class _TierBanner extends StatelessWidget {
  const _TierBanner({required this.tier, required this.report});

  final HealthTier? tier;
  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    final current = tier;
    final color = current == null ? Colors.blueGrey : tierColor(current);
    final icon = current == null ? Icons.hourglass_empty : tierIcon(current);
    final label = current == null ? 'Measuring…' : tierLabel(current);
    final advice = current == null
        ? 'Running the first diagnostic cycle.'
        : tierAdvice(current);

    final stats = <String>[];
    final r = report;
    if (r != null) {
      final download = r.downloadMbps;
      final upload = r.uploadMbps;
      final ping = r.idlePingMs;
      if (download != null) stats.add('↓ ${download.toStringAsFixed(1)} Mbps');
      if (upload != null) stats.add('↑ ${upload.toStringAsFixed(1)} Mbps');
      if (ping != null) stats.add('ping $ping ms');
      stats.add('loss ${(r.packetLossRatio * 100).round()}%');
    }

    return Card(
      color: color.withValues(alpha: 0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection Health',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(advice, style: Theme.of(context).textTheme.bodySmall),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      stats.join('   ·   '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step-by-step progress shown while the background cycle is running.
class _PhaseChecklist extends StatelessWidget {
  const _PhaseChecklist({required this.current});

  final DiagnosticPhase current;

  static const _steps = [
    (DiagnosticPhase.idlePing, 'Step 1 — Baseline idle ping'),
    (DiagnosticPhase.download, 'Step 2 — Download bandwidth + concurrent pings'),
    (DiagnosticPhase.upload, 'Step 3 — Upload bandwidth + concurrent upload pings'),
    (DiagnosticPhase.analyzing, 'Analyzing & classifying'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _steps
        .indexWhere((step) => step.$1 == current)
        .clamp(0, _steps.length - 1);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (i < currentIndex)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 20)
                    else if (i == currentIndex)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.radio_button_unchecked,
                          color: Theme.of(context).disabledColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _steps[i].$2,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: i == currentIndex
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                      ),
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

/// The four headline measurements of the last completed cycle.
class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.report});

  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final lossColor =
        (r?.packetLossRatio ?? 0) >= NetworkThresholds.heavyLossRatio
            ? Colors.red
            : Colors.green;

    final cards = [
      _MetricCard(
        label: 'Idle Ping',
        icon: Icons.wifi_tethering,
        color: Colors.blue,
        value: r?.idlePingMs == null ? '—' : '${r!.idlePingMs} ms',
        sub: 'baseline median of ${NetworkDiagnostics.pingProbeCount} probes',
      ),
      _MetricCard(
        label: 'Download',
        icon: Icons.file_download,
        color: Colors.indigo,
        value: r?.downloadMbps == null
            ? '—'
            : '${r!.downloadMbps!.toStringAsFixed(1)} Mbps',
        sub: r?.downloadPingMs == null
            ? 'concurrent pings during transfer'
            : 'load ping: ${r!.downloadPingMs} ms',
      ),
      _MetricCard(
        label: 'Upload',
        icon: Icons.file_upload,
        color: Colors.teal,
        value: r?.uploadMbps == null
            ? '—'
            : '${r!.uploadMbps!.toStringAsFixed(1)} Mbps',
        sub: r?.uploadPingMs == null
            ? 'concurrent pings during upload'
            : 'upload ping: ${r!.uploadPingMs} ms',
      ),
      // The noticeable "lag" of a connection: how much the latency inflates
      // while a transfer is saturating the link (bufferbloat).
      _MetricCard(
        label: 'Lag Under Load',
        icon: Icons.timeline,
        color: Colors.deepPurple,
        value: _lagValue(r),
        sub: 'download / upload ping while loading',
      ),
      _MetricCard(
        label: 'Packet Loss',
        icon: Icons.report_problem,
        color: lossColor,
        value: r == null ? '—' : '${(r.packetLossRatio * 100).round()}%',
        sub: r == null
            ? null
            : '${r.pingProbesFailed} / ${r.pingProbesTotal} probes lost',
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.maxWidth / 240).clamp(2, 4).floor();
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.0,
        children: cards,
      );
    });
  }

  /// Idle-vs-load comparison: the ping taken *while* a transfer was
  /// saturating the link is the "lag" (bufferbloat) figure — it shows how
  /// far latency inflates under load. `download / upload` when both were
  /// measured, `—` while the probes are still failing.
  static String _lagValue(DiagnosticReport? r) {
    final download = r?.downloadPingMs;
    final upload = r?.uploadPingMs;
    if (download == null && upload == null) return '—';
    if (download != null && upload != null) return '$download / $upload ms';
    return '${download ?? upload} ms';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null)
            Text(
              sub!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// Manual re-test trigger plus the auto re-test interval selector.
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.diagnostics});

  final NetworkDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: diagnostics.isRunning
                ? null
                : () => context.read<NetworkDiagnostics>().runNow(),
            icon: const Icon(Icons.speed),
            label: Text(
              diagnostics.isRunning ? 'Testing…' : 'Run Diagnostic Now',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Auto re-test',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: DropdownButton<Duration>(
              value: diagnostics.interval,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: Duration(seconds: 30), child: Text('Every 30 s')),
                DropdownMenuItem(
                    value: Duration(seconds: 60), child: Text('Every 1 min')),
                DropdownMenuItem(
                    value: Duration(seconds: 120), child: Text('Every 2 min')),
                DropdownMenuItem(value: Duration.zero, child: Text('Paused')),
              ],
              onChanged: (value) => context
                  .read<NetworkDiagnostics>()
                  .setInterval(value == Duration.zero ? null : value),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny bar chart: one bar per completed cycle, colored by its tier.
class _HistorySparkline extends StatelessWidget {
  const _HistorySparkline({required this.history});

  final List<DiagnosticReport> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Text(
        'No completed diagnostic cycles yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final series = history.reversed.take(24).toList();
    var maxMbps = NetworkThresholds.excellentMinMbps;
    for (final r in series) {
      final v = r.downloadMbps;
      if (v != null && v > maxMbps) maxMbps = v;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final r in series)
                    Expanded(
                      child: Tooltip(
                        message: r.downloadMbps == null
                            ? '${tierLabel(NetworkThresholds.classify(r))} — no download data'
                            : '${r.downloadMbps!.toStringAsFixed(1)} Mbps — ${tierLabel(NetworkThresholds.classify(r))}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 6 + ((r.downloadMbps ?? 0) / maxMbps) * 88,
                          decoration: BoxDecoration(
                            color: tierColor(NetworkThresholds.classify(r)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'One bar per cycle · color = tier · '
              'scale capped at ${maxMbps.toStringAsFixed(0)} Mbps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Documents the exact classification rules so the grading criteria are
/// visible inside the app itself.
class _ThresholdLegend extends StatelessWidget {
  const _ThresholdLegend();

  @override
  Widget build(BuildContext context) {
    final rows = <(Color, String, String)>[
      (tierColor(HealthTier.excellent), 'Excellent', 'download > 10 Mbps'),
      (tierColor(HealthTier.fair), 'Fair', 'download 2 – 10 Mbps'),
      (tierColor(HealthTier.poor), 'Poor', 'download < 2 Mbps'),
      (
        tierColor(HealthTier.degraded),
        'Degraded',
        'packet loss ≥ 25% or idle ping ≥ 400 ms (overrides speed)'
      ),
      (tierColor(HealthTier.offline), 'Offline', 'all probes failed'),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Health Tier Thresholds',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final (color, name, description) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$name — $description',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}