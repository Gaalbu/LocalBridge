import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/safe_file_name.dart';
import '../../../domain/entities/device_identity.dart';
import '../../../domain/entities/file_metadata.dart';
import '../../../domain/entities/transfer.dart';

typedef TransferApprovalCallback =
    Future<TransferDecision> Function(IncomingTransferRequest request);

class LocalHttpServer {
  LocalHttpServer({
    required this.identity,
    required this.receiveDirectory,
    required this.onApprovalRequested,
    this.preferredPort = AppConstants.defaultPort,
  });

  DeviceIdentity identity;
  Directory receiveDirectory;
  final TransferApprovalCallback onApprovalRequested;
  final int preferredPort;
  final Map<String, _AcceptedSession> _sessions = {};
  HttpServer? _server;

  int get port => _server?.port ?? preferredPort;

  Future<int> start() async {
    if (_server != null) return port;
    await receiveDirectory.create(recursive: true);
    final router = Router()
      ..get(ApiRoutes.ping, _ping)
      ..post(ApiRoutes.transferRequest, _requestTransfer)
      ..post('/api/v1/transfer/<sessionId>/file/<fileId>', _uploadFile)
      ..get('/api/v1/transfer/<sessionId>/complete', _complete);
    final handler = const Pipeline()
        .addMiddleware(_errorMiddleware())
        .addHandler(router.call);
    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        preferredPort,
        shared: false,
      );
    } on SocketException {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
    }
    return port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _sessions.clear();
  }

  Response _ping(Request request) => _json({
    'deviceId': identity.id,
    'deviceName': identity.name,
    'platform': Platform.isAndroid ? 'android' : 'linux',
    'protocolVersion': AppConstants.protocolVersion,
    'status': 'alive',
  });

  Future<Response> _requestTransfer(Request request) async {
    _removeExpiredSessions();
    final body = await _readLimitedJson(request);
    final senderId = body['senderDeviceId'] as String? ?? '';
    final senderName = body['senderDeviceName'] as String? ?? '';
    final rawFiles = body['files'];
    if (senderId.isEmpty ||
        senderId.length > 80 ||
        senderName.trim().isEmpty ||
        senderName.length > 80 ||
        rawFiles is! List ||
        rawFiles.isEmpty ||
        rawFiles.length > AppConstants.maxFilesPerTransfer) {
      return _json({'error': 'invalid_metadata'}, status: 422);
    }
    final files = <FileMetadata>[];
    for (final item in rawFiles) {
      if (item is! Map) {
        return _json({'error': 'invalid_file_metadata'}, status: 422);
      }
      final file = FileMetadata.fromJson(Map<String, dynamic>.from(item));
      if (!file.isValid) {
        return _json({'error': 'invalid_file_metadata'}, status: 422);
      }
      files.add(file);
    }
    final ids = files.map((file) => file.fileId).toSet();
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.fileSize);
    if (ids.length != files.length || body['totalSize'] != totalSize) {
      return _json({'error': 'inconsistent_metadata'}, status: 422);
    }

    final incoming = IncomingTransferRequest(
      requestId: const Uuid().v4(),
      senderDeviceId: senderId,
      senderDeviceName: senderName,
      files: files,
      totalSize: totalSize,
    );
    final decision = await onApprovalRequested(incoming).timeout(
      AppConstants.approvalTimeout,
      onTimeout: () => const TransferDecision.reject('approval_timeout'),
    );
    if (!decision.accepted) {
      return _json({
        'sessionId': null,
        'status': 'rejected',
        'reason': decision.reason,
      }, status: 403);
    }
    final accepted = files
        .where((file) => decision.acceptedFileIds.contains(file.fileId))
        .toList();
    if (accepted.isEmpty) {
      return _json({
        'sessionId': null,
        'status': 'rejected',
        'reason': 'no_files',
      }, status: 403);
    }
    final sessionId = const Uuid().v4();
    _sessions[sessionId] = _AcceptedSession(
      id: sessionId,
      files: {for (final file in accepted) file.fileId: file},
    );
    final rejected = files
        .where((file) => !decision.acceptedFileIds.contains(file.fileId))
        .map((file) => file.fileId)
        .toList();
    return _json({
      'sessionId': sessionId,
      'status': rejected.isEmpty ? 'accepted' : 'partially_accepted',
      'acceptedFiles': accepted.map((file) => file.fileId).toList(),
      'rejectedFiles': rejected,
    });
  }

  Future<Response> _uploadFile(
    Request request,
    String sessionId,
    String fileId,
  ) async {
    _removeExpiredSessions();
    final session = _sessions[sessionId];
    final metadata = session?.files[fileId];
    if (session == null || metadata == null) {
      return _json({'error': 'unknown_session_or_file'}, status: 404);
    }
    if (session.received.contains(fileId)) {
      return _json({'error': 'file_already_received'}, status: 409);
    }
    final declaredLength = int.tryParse(
      request.headers[HttpHeaders.contentLengthHeader] ?? '',
    );
    if (declaredLength != null && declaredLength != metadata.fileSize) {
      return _json({'error': 'size_mismatch'}, status: 413);
    }

    await receiveDirectory.create(recursive: true);
    final target = await _availableTarget(
      receiveDirectory,
      safeFileName(metadata.fileName),
    );
    final partial = File('${target.path}.$sessionId.part');
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in request.read()) {
        received += chunk.length;
        if (received > metadata.fileSize) {
          throw const _PayloadTooLarge();
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (received != metadata.fileSize) {
        await partial.delete();
        return _json({'error': 'size_mismatch'}, status: 413);
      }
      if (metadata.sha256 != null) {
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString().toLowerCase() != metadata.sha256!.toLowerCase()) {
          await partial.delete();
          return _json({'error': 'checksum_mismatch'}, status: 422);
        }
      }
      await partial.rename(target.path);
      session.received.add(fileId);
      return _json({
        'fileId': fileId,
        'status': 'received',
        'bytesReceived': received,
        'checksumValid': true,
      });
    } on Object {
      await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Response _complete(Request request, String sessionId) {
    _removeExpiredSessions();
    final session = _sessions[sessionId];
    if (session == null) {
      return _json({'error': 'unknown_session'}, status: 404);
    }
    final complete = session.received.length == session.files.length;
    return _json({
      'sessionId': sessionId,
      'status': complete ? 'completed' : 'in_progress',
      'filesReceived': session.received.length,
      'filesFailed': session.files.length - session.received.length,
    }, status: complete ? 200 : 409);
  }

  Middleware _errorMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        try {
          return await inner(request);
        } on FormatException {
          return _json({'error': 'invalid_json'}, status: 422);
        } on _PayloadTooLarge {
          return _json({'error': 'size_mismatch'}, status: 413);
        } on FileSystemException {
          return _json({'error': 'write_failed'}, status: 500);
        } on Object {
          return _json({'error': 'internal_error'}, status: 500);
        }
      };
    };
  }

  Future<Map<String, dynamic>> _readLimitedJson(Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      if (bytes.length + chunk.length > AppConstants.maxHandshakeBytes) {
        throw const FormatException('Handshake muito grande.');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Objeto JSON esperado.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<File> _availableTarget(Directory directory, String fileName) async {
    final extension = path.extension(fileName);
    final stem = path.basenameWithoutExtension(fileName);
    var candidate = File(path.join(directory.path, fileName));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(path.join(directory.path, '$stem ($suffix)$extension'));
      suffix++;
    }
    return candidate;
  }

  void _removeExpiredSessions() {
    final cutoff = DateTime.now().subtract(AppConstants.sessionLifetime);
    _sessions.removeWhere((_, session) => session.createdAt.isBefore(cutoff));
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'},
  );
}

class _AcceptedSession {
  _AcceptedSession({required this.id, required this.files});

  final String id;
  final Map<String, FileMetadata> files;
  final Set<String> received = {};
  final DateTime createdAt = DateTime.now();
}

class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
}
