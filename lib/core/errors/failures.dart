sealed class LocalBridgeFailure implements Exception {
  const LocalBridgeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NetworkFailure extends LocalBridgeFailure {
  const NetworkFailure(super.message);
}

final class TransferFailure extends LocalBridgeFailure {
  const TransferFailure(super.message);
}

final class ValidationFailure extends LocalBridgeFailure {
  const ValidationFailure(super.message);
}
