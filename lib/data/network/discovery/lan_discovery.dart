import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../domain/entities/device_identity.dart';
import '../../../domain/entities/peer_device.dart';

class LanDiscovery {
  LanDiscovery({required this.identity, required this.serverPort});

  DeviceIdentity identity;
  int serverPort;
  final Map<String, PeerDevice> _peers = {};
  final http.Client _client = http.Client();
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  Timer? _heartbeat;
  bool _checkingPeers = false;

  List<PeerDevice> get peers {
    final result = _peers.values.toList();
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  VoidCallback? onPeersChanged;

  Future<void> start() async {
    await stopActions();
    final service = BonsoirService(
      name: identity.name,
      type: AppConstants.serviceType,
      port: serverPort,
      attributes: {
        'id': identity.id,
        'name': identity.name,
        'platform': Platform.isAndroid ? 'android' : 'linux',
        'proto': AppConstants.protocolVersion,
      },
    );
    final broadcast = BonsoirBroadcast(service: service, printLogs: false);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;

    final discovery = BonsoirDiscovery(
      type: AppConstants.serviceType,
      printLogs: false,
    );
    await discovery.initialize();
    _discovery = discovery;
    _subscription = discovery.eventStream?.listen(_handleDiscoveryEvent);
    await discovery.start();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_checkKnownPeers()),
    );
  }

  Future<PeerDevice> addManualPeer(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw const NetworkFailure('Informe o IP do outro dispositivo.');
    }
    Uri uri;
    try {
      uri = Uri.parse(
        normalized.contains('://') ? normalized : 'http://$normalized',
      );
    } on FormatException {
      throw const NetworkFailure('Endereço inválido. Use IP ou IP:porta.');
    }
    if (uri.host.isEmpty) {
      throw const NetworkFailure('Endereço inválido. Use IP ou IP:porta.');
    }
    final temporary = PeerDevice(
      id: 'manual-${uri.host}-${uri.hasPort ? uri.port : serverPort}',
      name: uri.host,
      host: uri.host,
      port: uri.hasPort ? uri.port : AppConstants.defaultPort,
      platform: 'unknown',
      isManual: true,
    );
    final peer = await _ping(temporary);
    if (peer == null) {
      throw const NetworkFailure(
        'Não foi possível acessar o LocalBridge nesse endereço.',
      );
    }
    _peers[peer.id] = peer;
    onPeersChanged?.call();
    return peer;
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        event.service.resolve(_discovery!.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        unawaited(_addResolvedService(event.service));
      case BonsoirDiscoveryServiceUpdatedEvent():
        unawaited(_addResolvedService(event.service));
      case BonsoirDiscoveryServiceLostEvent():
        final id = event.service.attributes['id'];
        if (id != null && _peers.remove(id) != null) onPeersChanged?.call();
      default:
        break;
    }
  }

  Future<void> _addResolvedService(BonsoirService service) async {
    final id = service.attributes['id'];
    if (id == null || id == identity.id) return;
    final host = _preferredHost(service.hostAddresses);
    if (host == null) return;
    final candidate = PeerDevice(
      id: id,
      name: service.attributes['name'] ?? service.name,
      host: host,
      port: service.port,
      platform: service.attributes['platform'] ?? 'unknown',
    );
    final peer = await _ping(candidate);
    if (peer == null) return;
    _peers[peer.id] = peer;
    onPeersChanged?.call();
  }

  String? _preferredHost(List<String> addresses) {
    for (final address in addresses) {
      final parsed = InternetAddress.tryParse(address);
      if (parsed?.type == InternetAddressType.IPv4 && !parsed!.isLoopback) {
        return address;
      }
    }
    return addresses.cast<String?>().firstWhere(
      (address) => address != null && address.isNotEmpty,
      orElse: () => null,
    );
  }

  Future<PeerDevice?> _ping(PeerDevice candidate) async {
    try {
      final response = await _client
          .get(
            Uri(
              scheme: 'http',
              host: candidate.host,
              port: candidate.port,
              path: ApiRoutes.ping,
            ),
          )
          .timeout(AppConstants.peerTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['protocolVersion'] != AppConstants.protocolVersion) return null;
      return PeerDevice(
        id: body['deviceId'] as String? ?? candidate.id,
        name: body['deviceName'] as String? ?? candidate.name,
        host: candidate.host,
        port: candidate.port,
        platform: body['platform'] as String? ?? candidate.platform,
        isManual: candidate.isManual,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _checkKnownPeers() async {
    if (_checkingPeers) return;
    _checkingPeers = true;
    try {
      final snapshot = _peers.values.toList();
      for (final candidate in snapshot) {
        if (await _ping(candidate) == null) _peers.remove(candidate.id);
      }
      if (snapshot.length != _peers.length) onPeersChanged?.call();
    } finally {
      _checkingPeers = false;
    }
  }

  Future<void> stopActions() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
  }

  Future<void> dispose() async {
    await stopActions();
    _client.close();
  }
}

typedef VoidCallback = void Function();
