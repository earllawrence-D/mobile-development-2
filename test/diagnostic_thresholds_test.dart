import 'package:flutter_test/flutter_test.dart';

import 'package:lab_compiler_app/models/diagnostic_report.dart';

/// Pure classification tests for the Network Diagnostic Dashboard —
/// no network access required.
void main() {
  DiagnosticReport report({
    required bool succeeded,
    double? download,
    double? upload,
    int? idlePing,
    int? downloadPing,
    int? uploadPing,
    int pingTotal = 6,
    int pingFailed = 0,
  }) =>
      DiagnosticReport(
        timestamp: DateTime(2026, 1, 1),
        succeeded: succeeded,
        downloadMbps: download,
        uploadMbps: upload,
        idlePingMs: idlePing,
        downloadPingMs: downloadPing,
        uploadPingMs: uploadPing,
        pingProbesTotal: pingTotal,
        pingProbesFailed: pingFailed,
      );

  group('NetworkThresholds.classify', () {
    test('excellent when download > 10 Mbps', () {
      final r = report(succeeded: true, download: 25, idlePing: 20);
      expect(r.tier, HealthTier.excellent);
    });

    test('fair at exactly 10 Mbps (excellent requires > 10)', () {
      final r = report(succeeded: true, download: 10, idlePing: 20);
      expect(r.tier, HealthTier.fair);
    });

    test('fair in the 2–10 Mbps band', () {
      final r = report(succeeded: true, download: 5, idlePing: 30);
      expect(r.tier, HealthTier.fair);
    });

    test('poor below 2 Mbps', () {
      final r = report(succeeded: true, download: 1.9, idlePing: 30);
      expect(r.tier, HealthTier.poor);
    });

    test('heavy packet loss degrades the tier even at high speed', () {
      final r = report(
        succeeded: true,
        download: 50,
        idlePing: 20,
        pingFailed: 2,
        pingTotal: 6,
      );
      expect(r.packetLossRatio, closeTo(0.333, 0.01));
      expect(r.tier, HealthTier.degraded);
    });

    test('extreme idle latency degrades the tier', () {
      final r = report(succeeded: true, download: 50, idlePing: 450);
      expect(r.tier, HealthTier.degraded);
    });

    test('bufferbloat (latency collapse under load) degrades the tier', () {
      final r = report(
        succeeded: true,
        download: 50,
        idlePing: 40,
        downloadPing: 300,
      );
      expect(r.tier, HealthTier.degraded);
    });

    test('healthy load-ping inflation does NOT degrade', () {
      // 160 ms is 5× the 32 ms idle, but it is below the 250 ms absolute
      // floor, so it is not treated as bufferbloat.
      final r = report(
        succeeded: true,
        download: 50,
        idlePing: 32,
        downloadPing: 160,
      );
      expect(r.tier, HealthTier.excellent);
    });

    test('offline when every probe failed', () {
      final r = report(succeeded: false);
      expect(r.tier, HealthTier.offline);
    });

    test('poor when pings work but the transfer failed', () {
      final r = report(succeeded: true, download: null, idlePing: 25);
      expect(r.tier, HealthTier.poor);
    });
  });

  group('DiagnosticReport helpers', () {
    test('medianOf odd count', () {
      expect(DiagnosticReport.medianOf([3, 1, 2]), 2);
    });

    test('medianOf even count averages the middle pair', () {
      // (2 + 3) / 2 = 2.5 → rounded to 3 (half away from zero).
      expect(DiagnosticReport.medianOf([4, 1, 3, 2]), 3);
    });

    test('medianOf ignores null (lost) probes', () {
      expect(DiagnosticReport.medianOf([null, 20, 22]), 21);
    });

    test('medianOf returns null when all probes failed', () {
      expect(DiagnosticReport.medianOf([null, null]), null);
    });

    test('lossRatio handles zero probes', () {
      expect(DiagnosticReport.lossRatio(failed: 0, total: 0), 0);
    });

    test('lossRatio computes the failed fraction', () {
      expect(
        DiagnosticReport.lossRatio(failed: 3, total: 4),
        closeTo(0.75, 1e-9),
      );
    });
  });
}