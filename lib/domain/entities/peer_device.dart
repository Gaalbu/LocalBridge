class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.platform,
    this.isManual = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String platform;
  final bool isManual;

  String get address => '$host:$port';
}
