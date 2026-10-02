import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/mesh_chat_controller.dart';
import '../models/mesh_models.dart';

/// Entry point for the "Local Mesh Chat" activity.
///
/// The [MeshChatController] is created here (not globally) so that leaving
/// the screen stops advertising/scanning and closes every connection.
class LocalMeshChatScreen extends StatelessWidget {
  const LocalMeshChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Google's Nearby Connections API (and this plugin) is Android-only.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: const Text('Local Mesh Chat')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Local Mesh Chat uses Google Nearby Connections, which is only '
              'available on Android devices with Google Play services. '
              'Run the app on two Android phones to try it.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (ctx) =>
          MeshChatController(userName: ctx.read<AppState>().profileName),
      child: const _MeshChatView(),
    );
  }
}

class _MeshChatView extends StatefulWidget {
  const _MeshChatView();

  @override
  State<_MeshChatView> createState() => _MeshChatViewState();
}

class _MeshChatViewState extends State<_MeshChatView> {
  @override
  void initState() {
    super.initState();
    // Begin broadcasting + scanning as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MeshChatController>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshChatController>();
    final online =
        mesh.phase == MeshPhase.running || mesh.phase == MeshPhase.starting;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Local Mesh Chat'),
          actions: [
            IconButton(
              tooltip: online ? 'Go offline' : 'Go online',
              icon: Icon(online ? Icons.sensors : Icons.sensors_off),
              onPressed: () => online ? mesh.stop() : mesh.start(),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.radar),
                text: 'Nearby (${mesh.peers.length})',
              ),
              Tab(
                icon: const Icon(Icons.forum_outlined),
                text: 'Chat (${mesh.connectedCount} linked)',
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _StatusBanner(mesh: mesh),
              const Expanded(
                child: TabBarView(children: [_PeersTab(), _ChatTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status banner
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final MeshChatController mesh;
  const _StatusBanner({required this.mesh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget banner({
      required IconData icon,
      required String text,
      Color? color,
      List<Widget> actions = const [],
    }) {
      return Container(
        width: double.infinity,
        color: color ?? scheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            ...actions,
          ],
        ),
      );
    }

    switch (mesh.phase) {
      case MeshPhase.idle:
        return banner(
          icon: Icons.sensors_off,
          text: 'Offline. Other devices cannot see you.',
          actions: [
            TextButton(onPressed: mesh.start, child: const Text('Go online')),
          ],
        );
      case MeshPhase.starting:
        return const LinearProgressIndicator();
      case MeshPhase.permissionDenied:
        return banner(
          icon: Icons.lock_outline,
          color: scheme.errorContainer,
          text:
              'Bluetooth, Wi-Fi and location permissions are needed to find nearby devices.',
          actions: [
            TextButton(
              onPressed:
                  mesh.permanentlyDenied ? mesh.openSettings : mesh.start,
              child: Text(mesh.permanentlyDenied ? 'Settings' : 'Retry'),
            ),
          ],
        );
      case MeshPhase.error:
        return banner(
          icon: Icons.error_outline,
          color: scheme.errorContainer,
          text: mesh.error ?? 'Something went wrong.',
          actions: [
            TextButton(onPressed: mesh.start, child: const Text('Retry')),
          ],
        );
      case MeshPhase.running:
        if (!mesh.locationServiceOn) {
          return banner(
            icon: Icons.location_off_outlined,
            color: scheme.tertiaryContainer,
            text: 'Turn on device Location; many phones need it for discovery.',
          );
        }
        return banner(
          icon: Icons.podcasts,
          text: 'Visible as "${mesh.userName}" and scanning',
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Nearby tab
// ---------------------------------------------------------------------------

class _PeersTab extends StatelessWidget {
  const _PeersTab();

  @override
  Widget build(BuildContext context) {
    final peers = context.watch<MeshChatController>().peers;

    if (peers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No devices found yet.\nOpen Local Mesh Chat on another phone '
            'within Bluetooth / Wi-Fi range.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: peers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _PeerCard(peer: peers[i]),
    );
  }
}

class _PeerCard extends StatelessWidget {
  final MeshPeer peer;
  const _PeerCard({required this.peer});

  @override
  Widget build(BuildContext context) {
    final mesh = context.read<MeshChatController>();
    final theme = Theme.of(context);

    final Widget trailing;
    final String subtitle;
    final IconData icon;

    switch (peer.status) {
      case PeerStatus.discovered:
        icon = Icons.smartphone;
        subtitle = 'Nearby';
        trailing = FilledButton.tonal(
          onPressed: () => mesh.connect(peer.endpointId),
          child: const Text('Connect'),
        );
      case PeerStatus.connecting:
        icon = Icons.sync;
        subtitle = 'Requesting connection...';
        trailing = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case PeerStatus.verifying:
        icon = Icons.verified_user_outlined;
        subtitle = peer.incoming ? 'Wants to connect' : 'Confirm the code';
        trailing = const SizedBox.shrink();
      case PeerStatus.connected:
        icon = Icons.check_circle;
        subtitle = 'Connected (encrypted)';
        trailing = IconButton(
          tooltip: 'Disconnect',
          icon: const Icon(Icons.link_off),
          onPressed: () => mesh.disconnect(peer.endpointId),
        );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: peer.status == PeerStatus.connected
                      ? Colors.green.withValues(alpha: 0.15)
                      : theme.colorScheme.primaryContainer,
                  child: Icon(
                    icon,
                    color: peer.status == PeerStatus.connected
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
            if (peer.status == PeerStatus.verifying) ...[
              const Divider(height: 24),
              Text(
                'Check that this code is identical on ${peer.name}\'s screen:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  peer.authToken ?? '----',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (peer.localAccepted)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Waiting for ${peer.name} to accept...'),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => mesh.rejectPeer(peer.endpointId),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => mesh.acceptPeer(peer.endpointId),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat tab
// ---------------------------------------------------------------------------

class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshChatController>();
    // Newest at the bottom: the list is reversed, so feed it newest-first.
    final messages = mesh.messages.reversed.toList();

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('No messages yet.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: messages[i],
                    isMine: messages[i].originId == mesh.deviceId,
                  ),
                ),
        ),
        _Composer(enabled: mesh.canSend),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MeshMessage message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style:
              theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    final scheme = theme.colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color:
              isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Text(
                message.senderName,
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            Text(message.text),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _time(message.sentAt),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Only the text being typed lives in local State; everything else comes
/// from the controller.
class _Composer extends StatefulWidget {
  final bool enabled;
  const _Composer({required this.enabled});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    context.read<MeshChatController>().sendMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              maxLength: MeshChatController.maxTextLength,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                counterText: '',
                hintText: widget.enabled
                    ? 'Message nearby devices...'
                    : 'Connect to a device first',
              ),
            ),
          ),
          IconButton.filled(
            onPressed: widget.enabled ? _send : null,
            icon: const Icon(Icons.send),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}