/// Operational health tiers for the connection, derived from measured
/// download bandwidth, latency, and packet loss (see [NetworkThresholds]):
///
/// * Excellent — download > 10 Mbps
/// * Fair      — download between 2 and 10 Mbps
/// * Poor      — download < 2 Mbps (still usable, but the UI downgrades)
/// * Degraded  — heavy packet loss and/or extreme latency, regardless of
///               measured speed (this tier overrides the speed tiers)
/// * Offline   — every probe failed; nothing is getting through
enum HealthTier { excellent, fair, poor, degraded, offline }

/// Immutable result of one full diagnostic cycle: the baseline idle ping,
/// the download/upload bandwidth, the pings measured *while* those
/// transfers were running, and the packet-loss counters.
class DiagnosticReport {
  const DiagnosticReport({
    required this.timestamp,
    required this.succeeded,
    this.idlePingMs,
    this.downloadPingMs,
    this.uploadPingMs,
    this.downloadMbps,
    this.uploadMbps,
    this.pingProbesTotal = 0,
    this.pingProbesFailed = 0,
  });

  /// When the cycle finished.
  final DateTime timestamp;

  /// True when at least one probe (ping or transfer) got a response.
  final bool succeeded;

  /// Median RTT of the unloaded baseline pings, in milliseconds.
  final int? idlePingMs;

  /// Median RTT of pings fired *while* the download was streaming.
  final int? downloadPingMs;

  /// Median RTT of pings fired *while* the upload was streaming.
  final int? uploadPingMs;

  /// Measured download throughput in megabits per second.
  final double? downloadMbps;

  /// Measured upload throughput in megabits per second.
  final double? uploadMbps;

  /// Total ping probes attempted during the cycle.
  final int pingProbesTotal;

  /// Ping probes that timed out or errored during the cycle.
  final int pingProbesFailed;

  /// Fraction (0.0 – 1.0) of ping probes that failed.
  double get packetLossRatio => DiagnosticReport.lossRatio(
        failed: pingProbesFailed,
        total: pingProbesTotal,
      );

  /// The health tier this report falls into.
  HealthTier get tier => NetworkThresholds.classify(this);

  /// `failed / total`, guarding against division by zero.
  static double lossRatio({required int failed, required int total}) =>
      total <= 0 ? 0 : failed / total;

  /// Median of samples that may contain `null` (lost) probes. `null`
  /// entries are ignored; for an even count the two middle values are
  /// averaged (rounded, half away from zero). Returns `null` when every
  /// probe failed, so callers can distinguish "slow" from "no data".
  static int? medianOf(List<int?> samples) {
    final values = samples.whereType<int>().toList()..sort();
    if (values.isEmpty) return null;
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : ((values[middle - 1] + values[middle]) / 2).round();
  }
}

/// Threshold constants plus the pure classification function the
/// diagnostic engine uses to group a [DiagnosticReport] into an
/// operational tier. Kept free of I/O so it can be unit-tested.
class NetworkThresholds {
  const NetworkThresholds._();

  /// Download speeds above this are [HealthTier.excellent] (strictly
  /// greater, so exactly 10 Mbps lands in the Fair band).
  static const double excellentMinMbps = 10;

  /// Download speeds at/above this (and at/below [excellentMinMbps]) are
  /// [HealthTier.fair]; anything lower is [HealthTier.poor].
  static const double fairMinMbps = 2;

  /// Losing at least this fraction of ping probes is "heavy packet loss"
  /// and forces [HealthTier.degraded] no matter how fast the transfer was.
  static const double heavyLossRatio = 0.25;

  /// A baseline ping at or above this many milliseconds is "extreme
  /// latency" and forces [HealthTier.degraded].
  static const int extremeLatencyMs = 400;

  /// Pings during a transfer only count as bufferbloat when they are at
  /// least this slow in absolute terms. The floor prevents false
  /// positives like 5 × 8 ms = 40 ms, which is perfectly healthy.
  static const int loadLatencyFloorMs = 250;

  /// Pings inflated to at least this multiple of the idle ping during a
  /// transfer indicate severe bufferbloat → [HealthTier.degraded].
  static const int loadInflationFactor = 5;

  /// Maps a report to its tier. The order of the checks matters: total
  /// failure wins first, then the quality overrides (loss / extreme
  /// latency / bufferbloat), and only then the plain speed buckets.
  static HealthTier classify(DiagnosticReport report) {
    if (!report.succeeded) return HealthTier.offline;

    // Quality overrides — a fast-but-lossy connection is still degraded.
    if (report.packetLossRatio >= heavyLossRatio) return HealthTier.degraded;

    final idle = report.idlePingMs;
    if (idle != null && idle >= extremeLatencyMs) return HealthTier.degraded;

    // Bufferbloat: latency collapsing under load.
    final loadPing = report.downloadPingMs;
    if (idle != null &&
        loadPing != null &&
        loadPing >= loadLatencyFloorMs &&
        loadPing >= idle * loadInflationFactor) {
      return HealthTier.degraded;
    }

    // Plain bandwidth buckets from the spec.
    final mbps = report.downloadMbps;
    if (mbps == null) return HealthTier.poor; // pings work, transfers fail
    if (mbps > excellentMinMbps) return HealthTier.excellent;
    if (mbps >= fairMinMbps) return HealthTier.fair;
    return HealthTier.poor;
  }
}