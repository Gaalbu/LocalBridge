import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../core/constants/api_routes.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../domain/entities/device_identity.dart';
import '../../../domain/entities/file_metadata.dart';
import '../../../domain/entities/peer_device.dart';

typedef TransferProgressCallback = void Function(int sent, int total);

class TransferClient {
  TransferClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> sendFiles({
    required DeviceIdentity identity,
    required PeerDevice peer,
    required List<XFile> files,
    required TransferProgressCallback onProgress,
  }) async {
    final outgoing = <_OutgoingFile>[];
    for (final file in files) {
      final diskFile = File(file.path);
      if (!await diskFile.exists()) {
        throw TransferFailure('Arquivo não encontrado: ${file.name}');
      }
      final length = await diskFile.length();
      outgoing.add(
        _OutgoingFile(
          xFile: file,
          metadata: FileMetadata(
            fileId: const Uuid().v4(),
            fileName: path.basename(file.name),
            fileSize: length,
            mimeType: lookupMimeType(file.path) ?? 'application/octet-stream',
          ),
        ),
      );
    }
    final total = outgoing.fold<int>(
      0,
      (sum, item) => sum + item.metadata.fileSize,
    );
    final handshake = await _client
        .post(
          _uri(peer, ApiRoutes.transferRequest),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          body: jsonEncode({
            'senderDeviceId': identity.id,
            'senderDeviceName': identity.name,
            'files': outgoing.map((item) => item.metadata.toJson()).toList(),
            'totalSize': total,
          }),
        )
        .timeout(AppConstants.approvalTimeout + const Duration(seconds: 5));
    if (handshake.statusCode == 403) {
      throw const TransferFailure('A transferência foi recusada.');
    }
    if (handshake.statusCode != 200) {
      throw TransferFailure(
        'O dispositivo recusou a solicitação (${handshake.statusCode}).',
      );
    }
    final response = jsonDecode(handshake.body) as Map<String, dynamic>;
    final sessionId = response['sessionId'] as String?;
    final accepted = (response['acceptedFiles'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    if (sessionId == null || accepted.isEmpty) {
      throw const TransferFailure('Nenhum arquivo foi aceito.');
    }

    var completedBytes = 0;
    for (final item in outgoing) {
      if (!accepted.contains(item.metadata.fileId)) continue;
      final request =
          http.StreamedRequest(
              'POST',
              _uri(peer, ApiRoutes.upload(sessionId, item.metadata.fileId)),
            )
            ..headers[HttpHeaders.contentTypeHeader] =
                'application/octet-stream'
            ..headers['X-File-Id'] = item.metadata.fileId
            ..headers['X-File-Name'] = Uri.encodeComponent(
              item.metadata.fileName,
            )
            ..contentLength = item.metadata.fileSize;

      final responseFuture = _client
          .send(request)
          .timeout(const Duration(hours: 6));
      var currentBytes = 0;
      final source = File(item.xFile.path).openRead().map((chunk) {
        currentBytes += chunk.length;
        onProgress(completedBytes + currentBytes, total);
        return chunk;
      });
      await request.sink.addStream(source);
      await request.sink.close();
      final uploadResponse = await responseFuture;
      final responseBody = await uploadResponse.stream.bytesToString();
      if (uploadResponse.statusCode != 200) {
        throw TransferFailure(
          'Falha ao enviar ${item.metadata.fileName} '
          '(${uploadResponse.statusCode}): $responseBody',
        );
      }
      completedBytes += item.metadata.fileSize;
      onProgress(completedBytes, total);
    }

    final completion = await _client
        .get(_uri(peer, ApiRoutes.complete(sessionId)))
        .timeout(AppConstants.peerTimeout);
    if (completion.statusCode != 200) {
      throw const TransferFailure('O destino não confirmou todos os arquivos.');
    }
  }

  Uri _uri(PeerDevice peer, String route) =>
      Uri(scheme: 'http', host: peer.host, port: peer.port, path: route);

  void close() => _client.close();
}

class _OutgoingFile {
  const _OutgoingFile({required this.xFile, required this.metadata});

  final XFile xFile;
  final FileMetadata metadata;
}
