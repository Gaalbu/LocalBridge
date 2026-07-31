abstract final class AppConstants {
  static const appName = 'LocalBridge';
  static const protocolVersion = '1';
  static const serviceType = '_localbridge._tcp';
  static const defaultPort = 53317;
  static const maxHandshakeBytes = 256 * 1024;
  static const maxFilesPerTransfer = 100;
  static const peerTimeout = Duration(seconds: 3);
  static const approvalTimeout = Duration(minutes: 2);
  static const sessionLifetime = Duration(minutes: 30);
}
