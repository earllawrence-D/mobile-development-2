import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'diagnostic_report.dart';

/// Phases of one diagnostic cycle. Surfaced to the dashboard so it can
/// render a live step checklist while the background tool is running.
enum DiagnosticPhase { idle, idlePing, download, upload, analyzing }

/// Result of one transfer test: throughput (`null` = failed) plus the ping
/// samples taken concurrently while the transfer was streaming.
typedef TransferResult = ({double? mbps, List<int?> loadPings});

/// Global, app-wide network diagnostic tool (provided once in main.dart).
///
/// Runs the required multi-step measurement sequence on a timer (and on
/// demand via [runNow]). All work happens through dart:io HTTP sockets,
/// which execute off the UI isolate, so the UI stays responsive while a
/// cycle is in flight.
///
/// The multi-step sequence per cycle:
///
/// 1. **Idle ping** — five sequential unloaded probes establish the
///    baseline round-trip time (median) and the packet-loss baseline.
/// 2. **Download bandwidth** — a ~3 MB payload is streamed *while* four
///    concurrent pings are fired; the stream captures throughput and the
///    pings capture latency degradation under load (bufferbloat).
/// 3. **Upload bandwidth** — a ~1 MB payload is POSTed upstream *while*
///    the same style of concurrent pings runs, producing upload
///    throughput together with the upload-side ping samples.
///
/// The resulting [DiagnosticReport] is classified into a [HealthTier]
/// (see [NetworkThresholds.classify]) and broadcast through Provider, so
/// any widget in the app can adapt from high-resolution multimedia to
/// lightweight placeholders based on real-time connection health.
class NetworkDiagnostics extends ChangeNotifier {
  NetworkDiagnostics({Duration interval = defaultInterval})
      : _interval = interval {
    _ensureTimer();
    // Kick off the first cycle immediately so the dashboard has data as
    // soon as the app opens; the timer keeps re-testing regularly after.
    unawaited(_runCycle());
  }

  /// How often a fresh cycle runs by default (changeable at runtime via
  /// [setInterval]; [Duration.zero] pauses automatic testing).
  static const Duration defaultInterval = Duration(seconds: 60);

  // ---- Measurement tuning -----------------------------------------------

  /// Cloudflare's public, keyless speed-test endpoints. A single host is
  /// used deliberately so ping-vs-load-latency comparisons stay apples to
  /// apples (same CDN edge server).
  static final Uri _pingUrl =
      Uri.https('speed.cloudflare.com', '/__down', {'bytes': '0'});
  static Uri _downloadUrlFor(int bytes) =>
      Uri.https('speed.cloudflare.com', '/__down', {'bytes': '$bytes'});
  static final Uri _uploadUrl = Uri.https('speed.cloudflare.com', '/__up');

  /// Unloaded baseline probes fired in step 1.
  static const int pingProbeCount = 5;

  /// Pings fired *during* each transfer (steps 2 and 3).
  static const int _loadPingCount = 4;

  static const int _downloadBytes = 3 * 1000 * 1000;
  static const int _uploadBytes = 1 * 1000 * 1000;

  /// Per-request socket/HTTP timeout; a probe that exceeds this counts as
  /// lost rather than hanging the whole cycle.
  static const Duration _probeTimeout = Duration(seconds: 5);

  /// Wall-clock cap for one transfer; throttled links still get a
  /// throughput estimate from the partial bytes received so far.
  static const Duration _transferCap = Duration(seconds: 12);

  /// Incompressible upload payload (random bytes, so transparent proxies
  /// cannot shrink it). Generated once, lazily, on first upload.
  static final Uint8List _uploadPayload = _generateUploadPayload();

  static Uint8List _generateUploadPayload() {
    final random = Random();
    final payload = Uint8List(_uploadBytes);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = random.nextInt(256);
    }
    return payload;
  }

  // ---- Observable state ---------------------------------------------------

  /// Newest-first history of completed cycles (capped at [_historyCap]).
  static const int _historyCap = 24;

  Timer? _timer;
  Duration? _interval;
  bool _running = false;
  bool _disposed = false;
  DiagnosticPhase _phase = DiagnosticPhase.idle;
  DiagnosticReport? _lastReport;
  String? _lastError;
  final List<DiagnosticReport> _history = [];

  DiagnosticReport? get lastReport => _lastReport;

  HealthTier? get tier =>
      _lastReport == null ? null : NetworkThresholds.classify(_lastReport!);

  List<DiagnosticReport> get history => List.unmodifiable(_history);

  DiagnosticPhase get phase => _phase;

  bool get isRunning => _running;

  /// Current auto re-test interval; [Duration.zero] means paused.
  Duration get interval => _interval ?? Duration.zero;

  String? get lastError => _lastError;

  /// Re-schedules the automatic cycle timer. Pass `null` (or
  /// [Duration.zero]) to pause automatic testing; [runNow] still works.
  void setInterval(Duration? interval) {
    _timer?.cancel();
    _timer = null;
    _interval =
        (interval == null || interval == Duration.zero) ? null : interval;
    if (_interval != null) {
      _timer = Timer.periodic(_interval!, (_) => _tick());
    }
    _notify();
  }

  /// Runs one full diagnostic cycle immediately. No-op while a cycle is
  /// already in flight, so timer ticks and user taps can never overlap.
  Future<void> runNow() => _runCycle();

  void _tick() => unawaited(_runCycle());

  Future<void> _runCycle() async {
    if (_running || _disposed) return;
    _running = true;
    _lastError = null;
    _phase = DiagnosticPhase.idlePing;
    _notify();

    DiagnosticReport report;
    try {
      report = await _executeCycle();
    } catch (error) {
      // Nothing at all came back — treat the connection as offline.
      report = DiagnosticReport(timestamp: DateTime.now(), succeeded: false);
      _lastError = 'Diagnostic cycle failed: $error';
    }

    _lastReport = report;
    _history.insert(0, report);
    if (_history.length > _historyCap) _history.removeLast();
    _running = false;
    _phase = DiagnosticPhase.idle;
    _notify();
  }

  Future<DiagnosticReport> _executeCycle() async {
    final client = HttpClient()
      ..connectionTimeout = _probeTimeout
      ..idleTimeout = const Duration(seconds: 15);

    try {
      // -- Step 1: baseline idle ping (sequential, so the link is idle) --
      final idleSamples = <int?>[];
      for (var i = 0; i < pingProbeCount; i++) {
        idleSamples.add(await _pingOnce(client));
      }

      // -- Step 2: download bandwidth with concurrent pings --
      _phase = DiagnosticPhase.download;
      _notify();
      final download = await _measureDownloadWithLoadPings(client);

      // -- Step 3: upload bandwidth with concurrent upload pings --
      _phase = DiagnosticPhase.upload;
      _notify();
      final upload = await _measureUploadWithLoadPings(client);

      _phase = DiagnosticPhase.analyzing;
      _notify();

      final allPings = [
        ...idleSamples,
        ...download.loadPings,
        ...upload.loadPings,
      ];

      final report = DiagnosticReport(
        timestamp: DateTime.now(),
        succeeded: idleSamples.any((s) => s != null) ||
            download.mbps != null ||
            upload.mbps != null,
        idlePingMs: DiagnosticReport.medianOf(idleSamples),
        downloadPingMs: DiagnosticReport.medianOf(download.loadPings),
        uploadPingMs: DiagnosticReport.medianOf(upload.loadPings),
        downloadMbps: download.mbps,
        uploadMbps: upload.mbps,
        pingProbesTotal: allPings.length,
        pingProbesFailed: allPings.where((s) => s == null).length,
      );

      if (!report.succeeded) {
        // Explain *why* nothing came back (DNS, no route, blocked socket, a
        // missing INTERNET permission…) instead of just "all probes failed";
        // that message is what makes the offline verdict actionable.
        _lastError = await _explainOffline(client);
      }
      return report;
    } finally {
      // force:true also kills any socket a timeout abandoned mid-stream.
      client.close(force: true);
    }
  }

  /// Measures download throughput while a concurrent ping sequence runs.
  Future<TransferResult> _measureDownloadWithLoadPings(HttpClient client) async {
    // Start the transfer first; Dart futures run concurrently, so the
    // ping sequence below shares the link with the streaming download.
    final transferFuture = _downloadThroughput(client);
    final loadPings = await _runLoadPings(client, _loadPingCount);
    final mbps = await transferFuture;
    return (mbps: mbps, loadPings: loadPings);
  }

  /// Measures upload throughput while a concurrent ping sequence runs.
  Future<TransferResult> _measureUploadWithLoadPings(HttpClient client) async {
    final transferFuture = _uploadThroughput(client);
    final loadPings = await _runLoadPings(client, _loadPingCount);
    final mbps = await transferFuture;
    return (mbps: mbps, loadPings: loadPings);
  }

  Future<List<int?>> _runLoadPings(HttpClient client, int count) async {
    final samples = <int?>[];
    for (var i = 0; i < count; i++) {
      samples.add(await _pingOnce(client));
    }
    return samples;
  }

  /// One HTTP-based ping. Returns the round-trip time in milliseconds, or
  /// `null` when the probe timed out / failed (i.e. "packet lost").
  Future<int?> _pingOnce(HttpClient client) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.getUrl(_pingUrl).timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>().timeout(_probeTimeout);
      if (response.statusCode != HttpStatus.ok) return null;
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Explains an "every probe failed" cycle by re-running a single probe and
  /// *keeping* the exception this time ([_pingOnce] returns `null` and throws
  /// the reason away). The message is shown verbatim in the dashboard's red
  /// error note, which turns an unexplained "Offline" into an actionable
  /// cause: DNS failure, no route, a firewall, or a release APK missing
  /// `android.permission.INTERNET`.
  Future<String> _explainOffline(HttpClient client) async {
    try {
      await _probeRaw(client, _pingUrl);
      // The host answered on the retry, so the link is flaky, not dead.
      return 'Offline for this cycle — none of the probes succeeded, but '
          '${_pingUrl.host} answered a retry, so the link is unstable '
          'rather than fully down.';
    } catch (error) {
      return 'Offline — no probe reached ${_pingUrl.host}. '
          'Cause: ${_shortenFailure(error.toString())}';
    }
  }

  /// One probe that deliberately lets its exception escape, so the caller
  /// can report the underlying socket/TLS error.
  Future<void> _probeRaw(HttpClient client, Uri url) async {
    final request = await client.getUrl(url).timeout(_probeTimeout);
    final response = await request.close().timeout(_probeTimeout);
    await response.drain<void>().timeout(_probeTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} from $url');
    }
  }

  /// Collapses an exception (often multi-line, with a stack trace) into one
  /// short line that fits in the dashboard's error note.
  static String _shortenFailure(String raw) {
    final firstLine = raw.split('\n').first.trim();
    return firstLine.length <= 140
        ? firstLine
        : '${firstLine.substring(0, 137)}...';
  }

  /// Streams the download payload and converts bytes/second → Mbps. If
  /// the wall-clock cap hits first, the partial bytes received still
  /// yield a valid (lower-bound) throughput estimate.
  Future<double?> _downloadThroughput(HttpClient client) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(_downloadUrlFor(_downloadBytes))
          .timeout(_probeTimeout);
      final response = await request.close().timeout(_probeTimeout);
      if (response.statusCode != HttpStatus.ok) return null;

      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (stopwatch.elapsed >= _transferCap) break; // cancels the socket
      }
      final seconds = stopwatch.elapsedMicroseconds / 1e6;
      if (received == 0 || seconds <= 0) return null;
      return (received * 8) / seconds / 1000000;
    } catch (_) {
      return null;
    }
  }

  /// POSTs the upload payload in chunks (so a hopelessly slow link can be
  /// abandoned mid-flight) and converts bytes/second → Mbps.
  Future<double?> _uploadThroughput(HttpClient client) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.postUrl(_uploadUrl).timeout(_probeTimeout);
      request.headers.contentType = ContentType.binary;
      request.contentLength = _uploadBytes;

      const chunkSize = 64 * 1024;
      for (var offset = 0; offset < _uploadBytes; offset += chunkSize) {
        final end = min(offset + chunkSize, _uploadBytes);
        request.add(Uint8List.sublistView(_uploadPayload, offset, end));
        if (stopwatch.elapsed >= _transferCap) {
          request.abort();
          return null;
        }
      }
      final response = await request.close().timeout(_transferCap);
      await response.drain<void>().timeout(_probeTimeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final seconds = stopwatch.elapsedMicroseconds / 1e6;
      if (seconds <= 0) return null;
      return (_uploadBytes * 8) / seconds / 1000000;
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _ensureTimer() {
    if (_interval != null && _interval! > Duration.zero) {
      _timer = Timer.periodic(_interval!, (_) => _tick());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}