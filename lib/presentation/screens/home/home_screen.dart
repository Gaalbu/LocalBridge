import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../application/bridge_controller.dart';
import '../../../application/providers.dart';
import '../../../core/utils/file_size_formatter.dart';
import '../../../domain/entities/peer_device.dart';
import '../../../domain/entities/transfer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  String? _visibleIncomingId;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _shareSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(_queueSharedMedia);
      ReceiveSharingIntent.instance.getInitialMedia().then(_queueSharedMedia);
    }
  }

  Future<void> _queueSharedMedia(List<SharedMediaFile> media) async {
    if (media.isEmpty || !mounted) return;
    final controller = ref.read(bridgeControllerProvider);
    final files = media.map((item) => XFile(item.path));
    final added = await controller.queueFiles(files);
    await ReceiveSharingIntent.instance.reset();
    if (mounted && added > 0) {
      _showMessage('$added arquivo(s) pronto(s). Toque em um dispositivo.');
    }
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(bridgeControllerProvider);
    _scheduleIncomingDialog(controller);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded),
            SizedBox(width: 8),
            Text('LocalBridge'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Conectar por IP',
            onPressed: controller.ready
                ? () => _showManualIp(controller)
                : null,
            icon: const Icon(Icons.add_link),
          ),
          IconButton(
            tooltip: 'Configurações',
            onPressed: controller.identity == null
                ? null
                : () => _showSettings(controller),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) async {
          setState(() => _dragging = false);
          final added = await controller.queueFiles(details.files);
          if (mounted && added > 0) {
            _showMessage(
              '$added arquivo(s) pronto(s). Clique em um dispositivo.',
            );
          }
        },
        child: ColoredBox(
          color: _dragging
              ? Theme.of(context).colorScheme.primaryContainer.withAlpha(120)
              : Colors.transparent,
          child: _body(controller),
        ),
      ),
    );
  }

  Widget _body(BridgeController controller) {
    if (controller.initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.startupError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                controller.startupError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.retryStartup,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refreshDiscovery,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _ReadyCard(controller: controller),
          if (controller.pendingFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PendingFilesCard(controller: controller),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dispositivos próximos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: controller.refreshDiscovery,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.peers.isEmpty)
            _EmptyPeers(onManualIp: () => _showManualIp(controller))
          else
            ...controller.peers.map(
              (peer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PeerCard(
                  peer: peer,
                  hasQueuedFiles: controller.pendingFiles.isNotEmpty,
                  onTap: () => _send(controller, peer),
                ),
              ),
            ),
          if (controller.transfers.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Transferências recentes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ...controller.transfers.map(_TransferTile.new),
          ],
        ],
      ),
    );
  }

  Future<void> _send(BridgeController controller, PeerDevice peer) async {
    final message = await controller.sendToPeer(peer);
    if (mounted) _showMessage(message);
  }

  void _scheduleIncomingDialog(BridgeController controller) {
    if (controller.incomingRequests.isEmpty) return;
    final request = controller.incomingRequests.first;
    if (_visibleIncomingId == request.requestId) return;
    _visibleIncomingId = request.requestId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _IncomingDialog(request: request),
      );
      if (accepted == true) {
        controller.acceptIncoming(request.requestId);
      } else {
        controller.rejectIncoming(request.requestId);
      }
      _visibleIncomingId = null;
    });
  }

  Future<void> _showManualIp(BridgeController controller) async {
    final textController = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar por IP'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'IP ou IP:porta',
            hintText: '192.168.1.42:53317',
            helperText: 'Use quando a descoberta automática estiver bloqueada.',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (address == null || address.trim().isEmpty) return;
    try {
      final peer = await controller.addManualPeer(address);
      if (mounted) _showMessage('${peer.name} conectado.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _showSettings(BridgeController controller) async {
    final nameController = TextEditingController(
      text: controller.identity!.name,
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configurações'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nome deste dispositivo',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Salvar recebidos em',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(controller.receiveDirectory?.path ?? ''),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await controller.chooseReceiveDirectory();
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('Escolher pasta'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await controller.renameDevice(nameController.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } on Object catch (error) {
                  if (mounted) _showMessage(error.toString());
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              child: const Icon(Icons.wifi_tethering_rounded),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pronto para receber',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${controller.identity?.name} • porta ${controller.serverPort}',
                  ),
                  const SizedBox(height: 3),
                  const Text('Sem internet, nuvem, conta ou anúncios.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingFilesCard extends StatelessWidget {
  const _PendingFilesCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final names = controller.pendingFiles
        .take(3)
        .map((file) => file.name)
        .join(', ');
    final remaining = controller.pendingFiles.length - 3;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.file_present_rounded),
        title: Text('${controller.pendingFiles.length} arquivo(s) pronto(s)'),
        subtitle: Text('$names${remaining > 0 ? ' e mais $remaining' : ''}'),
        trailing: IconButton(
          tooltip: 'Limpar seleção',
          onPressed: controller.clearPendingFiles,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({required this.onManualIp});

  final VoidCallback onManualIp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.devices_other_rounded, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Abra a LocalBridge no outro dispositivo conectado ao mesmo Wi-Fi.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onManualIp,
              icon: const Icon(Icons.add_link),
              label: const Text('Conectar por IP'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.peer,
    required this.hasQueuedFiles,
    required this.onTap,
  });

  final PeerDevice peer;
  final bool hasQueuedFiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final android = peer.platform == 'android';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          child: Icon(android ? Icons.smartphone : Icons.computer),
        ),
        title: Text(peer.name),
        subtitle: Text('${peer.address}${peer.isManual ? ' • manual' : ''}'),
        trailing: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text(hasQueuedFiles ? 'Enviar' : 'Escolher'),
        ),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile(this.transfer);

  final OutgoingTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (transfer.status) {
      TransferStatus.waitingApproval => (
        Icons.hourglass_top,
        'Aguardando aceite',
      ),
      TransferStatus.sending => (Icons.upload_rounded, 'Enviando'),
      TransferStatus.completed => (Icons.check_circle, 'Concluído'),
      TransferStatus.rejected => (Icons.block, 'Recusado'),
      TransferStatus.failed => (Icons.error_outline, 'Falhou'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text('${transfer.fileCount} arquivo(s) • ${transfer.peer.name}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            transfer.error ?? '$label • ${formatFileSize(transfer.totalBytes)}',
          ),
          if (transfer.status == TransferStatus.sending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: transfer.progress.clamp(0, 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomingDialog extends StatelessWidget {
  const _IncomingDialog({required this.request});

  final IncomingTransferRequest request;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receber arquivos?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.senderDeviceName} quer enviar '
              '${request.files.length} arquivo(s) (${formatFileSize(request.totalSize)}).',
            ),
            const SizedBox(height: 14),
            ...request.files
                .take(5)
                .map(
                  (file) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${file.fileName} (${formatFileSize(file.fileSize)})',
                    ),
                  ),
                ),
            if (request.files.length > 5)
              Text('… e mais ${request.files.length - 5} arquivo(s)'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Recusar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Aceitar'),
        ),
      ],
    );
  }
}
