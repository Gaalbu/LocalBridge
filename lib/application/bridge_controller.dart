import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../data/network/client/transfer_client.dart';
import '../data/network/discovery/lan_discovery.dart';
import '../data/network/server/local_http_server.dart';
import '../data/settings/settings_repository.dart';
import '../domain/entities/device_identity.dart';
import '../domain/entities/peer_device.dart';
import '../domain/entities/transfer.dart';
import 'transfer/incoming_transfer_manager.dart';

class BridgeController extends ChangeNotifier {
  BridgeController({SettingsRepository? settings})
    : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;
  final IncomingTransferManager incomingTransfers = IncomingTransferManager();
  final TransferClient _transferClient = TransferClient();
  final List<XFile> _pendingFiles = [];
  final List<OutgoingTransfer> _transfers = [];
  LocalHttpServer? _server;
  LanDiscovery? _discovery;
  DeviceIdentity? _identity;
  Directory? _receiveDirectory;
  bool _initializing = true;
  bool _initialized = false;
  bool _disposed = false;
  String? _startupError;

  bool get initializing => _initializing;
  bool get ready => _initialized && _startupError == null;
  String? get startupError => _startupError;
  DeviceIdentity? get identity => _identity;
  Directory? get receiveDirectory => _receiveDirectory;
  int? get serverPort => _server?.port;
  List<PeerDevice> get peers => _discovery?.peers ?? const [];
  List<XFile> get pendingFiles => List.unmodifiable(_pendingFiles);
  List<OutgoingTransfer> get transfers => List.unmodifiable(_transfers);
  List<IncomingTransferRequest> get incomingRequests =>
      incomingTransfers.pendingRequests;

  Future<void> initialize() async {
    if (_initialized || !_initializing || _disposed) return;
    incomingTransfers.addListener(_notifyIfMounted);
    try {
      _identity = await _settings.loadIdentity();
      _receiveDirectory = await _settings.loadReceiveDirectory();
      await _startNetwork();
      _initialized = true;
    } on Object catch (error) {
      _startupError = _friendlyError(error);
    } finally {
      _initializing = false;
      _notifyIfMounted();
    }
  }

  Future<void> retryStartup() async {
    _startupError = null;
    _initializing = true;
    _initialized = false;
    _notifyIfMounted();
    await _stopNetwork();
    _identity = await _settings.loadIdentity();
    _receiveDirectory = await _settings.loadReceiveDirectory();
    try {
      await _startNetwork();
      _initialized = true;
    } on Object catch (error) {
      _startupError = _friendlyError(error);
    } finally {
      _initializing = false;
      _notifyIfMounted();
    }
  }

  Future<void> _startNetwork() async {
    final identity = _identity!;
    final directory = _receiveDirectory!;
    final server = LocalHttpServer(
      identity: identity,
      receiveDirectory: directory,
      onApprovalRequested: incomingTransfers.enqueue,
    );
    await server.start();
    _server = server;
    final discovery = LanDiscovery(identity: identity, serverPort: server.port)
      ..onPeersChanged = _notifyIfMounted;
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> refreshDiscovery() async {
    final discovery = _discovery;
    if (discovery == null) return;
    try {
      await discovery.start();
    } on Object catch (error) {
      _startupError = _friendlyError(error);
    }
    _notifyIfMounted();
  }

  Future<PeerDevice> addManualPeer(String address) async {
    final discovery = _discovery;
    if (discovery == null) throw StateError('Rede ainda não iniciada.');
    return discovery.addManualPeer(address);
  }

  Future<void> renameDevice(String name) async {
    await _settings.saveDeviceName(name);
    _identity = await _settings.loadIdentity();
    await _stopNetwork();
    await _startNetwork();
    _notifyIfMounted();
  }

  Future<bool> chooseReceiveDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha onde salvar os arquivos recebidos',
    );
    if (selected == null) return false;
    await _settings.saveReceiveDirectory(selected);
    _receiveDirectory = Directory(selected);
    if (_server != null) _server!.receiveDirectory = _receiveDirectory!;
    _notifyIfMounted();
    return true;
  }

  Future<int> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      dialogTitle: 'Arquivos para enviar',
    );
    if (result == null) return 0;
    return queueFiles(
      result.files
          .where((file) => file.path != null)
          .map((file) => XFile(file.path!, name: file.name)),
    );
  }

  Future<int> queueFiles(Iterable<XFile> files) async {
    var added = 0;
    final known = _pendingFiles.map((file) => file.path).toSet();
    for (final file in files) {
      final diskFile = File(file.path);
      if (known.contains(file.path) || !await diskFile.exists()) continue;
      _pendingFiles.add(file);
      known.add(file.path);
      added++;
    }
    if (added > 0) _notifyIfMounted();
    return added;
  }

  void clearPendingFiles() {
    _pendingFiles.clear();
    _notifyIfMounted();
  }

  Future<String> sendToPeer(PeerDevice peer) async {
    if (_pendingFiles.isEmpty) await pickFiles();
    if (_pendingFiles.isEmpty) return 'Envio cancelado.';
    final files = List<XFile>.from(_pendingFiles);
    final total = await _totalSize(files);
    final transferId = const Uuid().v4();
    var transfer = OutgoingTransfer(
      id: transferId,
      peer: peer,
      fileCount: files.length,
      totalBytes: total,
      sentBytes: 0,
      status: TransferStatus.waitingApproval,
    );
    _transfers.insert(0, transfer);
    if (_transfers.length > 20) _transfers.removeLast();
    _notifyIfMounted();
    try {
      await _transferClient.sendFiles(
        identity: _identity!,
        peer: peer,
        files: files,
        onProgress: (sent, _) {
          transfer = transfer.copyWith(
            sentBytes: sent,
            status: TransferStatus.sending,
          );
          _replaceTransfer(transfer);
        },
      );
      transfer = transfer.copyWith(
        sentBytes: total,
        status: TransferStatus.completed,
      );
      _pendingFiles.removeWhere(
        (pending) => files.any((sent) => sent.path == pending.path),
      );
      _replaceTransfer(transfer);
      return '${files.length} arquivo(s) enviado(s) para ${peer.name}.';
    } on Object catch (error) {
      final message = _friendlyError(error);
      final rejected = message.toLowerCase().contains('recus');
      transfer = transfer.copyWith(
        status: rejected ? TransferStatus.rejected : TransferStatus.failed,
        error: message,
      );
      _replaceTransfer(transfer);
      return message;
    }
  }

  Future<int> _totalSize(List<XFile> files) async {
    var result = 0;
    for (final file in files) {
      result += await File(file.path).length();
    }
    return result;
  }

  String fileTypeFor(XFile file) =>
      lookupMimeType(file.path) ?? 'application/octet-stream';

  void acceptIncoming(String requestId) => incomingTransfers.accept(requestId);

  void rejectIncoming(String requestId) => incomingTransfers.reject(requestId);

  void _replaceTransfer(OutgoingTransfer updated) {
    final index = _transfers.indexWhere((item) => item.id == updated.id);
    if (index >= 0) _transfers[index] = updated;
    _notifyIfMounted();
  }

  Future<void> _stopNetwork() async {
    final discovery = _discovery;
    _discovery = null;
    await discovery?.dispose();
    final server = _server;
    _server = null;
    await server?.stop();
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^\w+Exception: '),
      '',
    );
    if (message.contains('SocketException')) {
      return 'Falha de rede. Confirme que os dispositivos estão no mesmo Wi-Fi.';
    }
    return message;
  }

  void _notifyIfMounted() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    incomingTransfers.removeListener(_notifyIfMounted);
    incomingTransfers.dispose();
    _transferClient.close();
    unawaited(_stopNetwork());
    super.dispose();
  }
}
