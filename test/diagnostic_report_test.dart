// Unit tests for the pure classification logic that decides the health tier
// shown all over the app — including the "Offline" verdict (which is what you
// see when every probe fails, e.g. no internet or a release APK without
// `android.permission.INTERNET`). No network access is used here.
import 'package:flutter_test/flutter_test.dart';

import 'package:lab_compiler_app/models/diagnostic_report.dart';

/// Builds a report, defaulting to a healthy connection, so each test only
/// has to state the measurement it is actually exercising.
DiagnosticReport report({
  bool succeeded = true,
  int? idlePingMs,
  int? downloadPingMs,
  int? uploadPingMs,
  double? downloadMbps,
  double? uploadMbps,
  int pingProbesTotal = 0,
  int pingProbesFailed = 0,
}) =>
    DiagnosticReport(
      timestamp: DateTime(2024, 1, 1),
      succeeded: succeeded,
      idlePingMs: idlePingMs,
      downloadPingMs: downloadPingMs,
      uploadPingMs: uploadPingMs,
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      pingProbesTotal: pingProbesTotal,
      pingProbesFailed: pingProbesFailed,
    );

void main() {
  group('NetworkThresholds.classify', () {
    test('is offline only when every probe failed', () {
      // 5 idle + 4 download + 4 upload probes, all lost: no ping, no transfer.
      final result = report(
        succeeded: false,
        pingProbesTotal: 13,
        pingProbesFailed: 13,
      );

      expect(result.tier, HealthTier.offline);
      expect(result.packetLossRatio, 1.0);
      expect(result.idlePingMs, isNull);
    });

    test('is excellent above 10 Mbps', () {
      expect(report(downloadMbps: 42.5).tier, HealthTier.excellent);
    });

    test('exactly 10 Mbps is fair (the comparison is strict)', () {
      expect(report(downloadMbps: 10).tier, HealthTier.fair);
    });

    test('2 – 10 Mbps is fair and below 2 Mbps is poor', () {
      expect(report(downloadMbps: 2).tier, HealthTier.fair);
      expect(report(downloadMbps: 1.99).tier, HealthTier.poor);
    });

    test('successful pings with failed transfers are poor, not offline', () {
      final result = report(
        idlePingMs: 30,
        downloadMbps: null,
        pingProbesTotal: 13,
        pingProbesFailed: 0,
      );

      expect(result.tier, HealthTier.poor);
    });

    test('heavy packet loss degrades even a fast connection', () {
      final result = report(
        downloadMbps: 80,
        pingProbesTotal: 4,
        pingProbesFailed: 1, // 25 %
      );

      expect(result.packetLossRatio, NetworkThresholds.heavyLossRatio);
      expect(result.tier, HealthTier.degraded);
    });

    test('transfers that work while every ping is lost are degraded', () {
      // This is what a connection looks like when the host answers data but
      // the latency probes are blocked/dropped — degraded, never offline.
      final result = report(
        downloadMbps: 25,
        pingProbesTotal: 13,
        pingProbesFailed: 13,
      );

      expect(result.tier, HealthTier.degraded);
    });

    test('extreme idle latency degrades a fast connection', () {
      expect(
        report(downloadMbps: 80, idlePingMs: 400).tier,
        HealthTier.degraded,
      );
      expect(
        report(downloadMbps: 80, idlePingMs: 399).tier,
        HealthTier.excellent,
      );
    });

    test('severe bufferbloat degrades the connection', () {
      // idle 20 ms inflates to 300 ms under load: >= the 250 ms floor and
      // >= 5x the idle ping.
      final result = report(
        downloadMbps: 60,
        idlePingMs: 20,
        downloadPingMs: 300,
        uploadPingMs: 280,
      );

      expect(result.tier, HealthTier.degraded);
    });

    test('a small latency increase under load is not bufferbloat', () {
      // 60 -> 120 ms is below the absolute floor, so it stays healthy.
      final result = report(
        downloadMbps: 60,
        idlePingMs: 60,
        downloadPingMs: 120,
        uploadPingMs: 90,
      );

      expect(result.tier, HealthTier.excellent);
    });
  });

  group('DiagnosticReport.medianOf', () {
    test('returns null when there is nothing (or only lost probes) to average',
        () {
      expect(DiagnosticReport.medianOf(const []), isNull);
      expect(DiagnosticReport.medianOf(const [null, null]), isNull);
    });

    test('ignores lost probes and picks the middle sample', () {
      // Five surviving probes, sorted: 10, 20, 30, 40, 50 → 30.
      expect(
        DiagnosticReport.medianOf(const [40, 10, null, 30, 20, 50]),
        30,
      );
    });

    test('averages the two middle samples for an even count', () {
      expect(DiagnosticReport.medianOf(const [10, 20, 30, 41]), 25);
    });
  });

  group('DiagnosticReport.lossRatio', () {
    test('is zero when no probe was attempted', () {
      expect(DiagnosticReport.lossRatio(failed: 0, total: 0), 0.0);
    });

    test('is failed / total', () {
      expect(DiagnosticReport.lossRatio(failed: 1, total: 4), 0.25);
    });
  });
}
