import 'dart:convert';
import 'dart:typed_data';

/// Lifecycle of the whole mesh session (advertising + discovery).
enum MeshPhase { idle, starting, running, permissionDenied, error }

/// Where a single nearby device is in the pairing sequence.
///
///   discovered -> connecting -> verifying -> connected
enum PeerStatus { discovered, connecting, verifying, connected }

/// Immutable snapshot of one neighbouring device. The UI is a pure function
/// of a list of these, so every change produces a new instance.
class MeshPeer {
  final String endpointId;
  final String name;
  final PeerStatus status;

  /// Short code both devices display during the handshake.
  final String? authToken;

  /// True when the other device initiated the connection.
  final bool incoming;

  /// True once *this* user pressed Accept (we are now waiting on the peer).
  final bool localAccepted;

  const MeshPeer({
    required this.endpointId,
    required this.name,
    this.status = PeerStatus.discovered,
    this.authToken,
    this.incoming = false,
    this.localAccepted = false,
  });

  MeshPeer copyWith({
    String? name,
    PeerStatus? status,
    String? authToken,
    bool? incoming,
    bool? localAccepted,
    bool clearAuth = false,
  }) {
    return MeshPeer(
      endpointId: endpointId,
      name: name ?? this.name,
      status: status ?? this.status,
      authToken: clearAuth ? null : (authToken ?? this.authToken),
      incoming: incoming ?? this.incoming,
      localAccepted: localAccepted ?? this.localAccepted,
    );
  }
}

/// One entry in the chat transcript: either a real chat message that travels
/// over the mesh, or a local-only system notice.
class MeshMessage {
  /// Unique per message; used to drop duplicates in the mesh.
  final String id;

  /// Random per-install id of the device that wrote the message.
  final String originId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// Remaining hops. Decremented every time a device relays the message.
  final int ttl;
  final bool isSystem;

  const MeshMessage({
    required this.id,
    required this.originId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    required this.ttl,
    this.isSystem = false,
  });

  factory MeshMessage.system(String text) {
    final now = DateTime.now();
    return MeshMessage(
      id: 'sys-${now.microsecondsSinceEpoch}',
      originId: '',
      senderName: '',
      text: text,
      sentAt: now,
      ttl: 0,
      isSystem: true,
    );
  }

  MeshMessage relayed() => MeshMessage(
        id: id,
        originId: originId,
        senderName: senderName,
        text: text,
        sentAt: sentAt,
        ttl: ttl - 1,
      );

  /// Wire format: UTF-8 JSON, well under the 32 KB bytes-payload limit.
  Uint8List encode() {
    final json = jsonEncode({
      'id': id,
      'o': originId,
      'n': senderName,
      't': text,
      'ts': sentAt.millisecondsSinceEpoch,
      'ttl': ttl,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Returns null for anything that is not a well-formed chat envelope.
  static MeshMessage? tryDecode(Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes));
      if (map is! Map) return null;
      final id = map['id'];
      final origin = map['o'];
      final name = map['n'];
      final text = map['t'];
      final ts = map['ts'];
      final ttl = map['ttl'];
      if (id is! String ||
          origin is! String ||
          name is! String ||
          text is! String ||
          ts is! int ||
          ttl is! int) {
        return null;
      }
      return MeshMessage(
        id: id,
        originId: origin,
        senderName: name,
        text: text,
        sentAt: DateTime.fromMillisecondsSinceEpoch(ts),
        ttl: ttl,
      );
    } catch (_) {
      return null;
    }
  }
}