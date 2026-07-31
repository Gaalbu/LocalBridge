import 'file_metadata.dart';
import 'peer_device.dart';

enum TransferStatus { waitingApproval, sending, completed, rejected, failed }

class IncomingTransferRequest {
  const IncomingTransferRequest({
    required this.requestId,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.files,
    required this.totalSize,
  });

  final String requestId;
  final String senderDeviceId;
  final String senderDeviceName;
  final List<FileMetadata> files;
  final int totalSize;
}

class TransferDecision {
  const TransferDecision._({
    required this.accepted,
    required this.acceptedFileIds,
    this.reason,
  });

  const TransferDecision.reject([String reason = 'user_declined'])
    : this._(accepted: false, acceptedFileIds: const {}, reason: reason);

  factory TransferDecision.accept(Iterable<String> fileIds) =>
      TransferDecision._(accepted: true, acceptedFileIds: fileIds.toSet());

  final bool accepted;
  final Set<String> acceptedFileIds;
  final String? reason;
}

class OutgoingTransfer {
  const OutgoingTransfer({
    required this.id,
    required this.peer,
    required this.fileCount,
    required this.totalBytes,
    required this.sentBytes,
    required this.status,
    this.error,
  });

  final String id;
  final PeerDevice peer;
  final int fileCount;
  final int totalBytes;
  final int sentBytes;
  final TransferStatus status;
  final String? error;

  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;

  OutgoingTransfer copyWith({
    int? sentBytes,
    TransferStatus? status,
    String? error,
  }) {
    return OutgoingTransfer(
      id: id,
      peer: peer,
      fileCount: fileCount,
      totalBytes: totalBytes,
      sentBytes: sentBytes ?? this.sentBytes,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}
