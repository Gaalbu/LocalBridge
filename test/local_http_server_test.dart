import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_bridge/core/constants/api_routes.dart';
import 'package:local_bridge/data/network/server/local_http_server.dart';
import 'package:local_bridge/domain/entities/device_identity.dart';
import 'package:local_bridge/domain/entities/transfer.dart';

void main() {
  group('LocalHttpServer', () {
    late Directory receiveDirectory;
    late LocalHttpServer server;
    late http.Client client;

    setUp(() async {
      receiveDirectory = await Directory.systemTemp.createTemp('localbridge-');
      server = LocalHttpServer(
        identity: const DeviceIdentity(id: 'receiver-id', name: 'Receiver'),
        receiveDirectory: receiveDirectory,
        preferredPort: 0,
        onApprovalRequested: (request) async =>
            TransferDecision.accept(request.files.map((file) => file.fileId)),
      );
      await server.start();
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.stop();
      if (await receiveDirectory.exists()) {
        await receiveDirectory.delete(recursive: true);
      }
    });

    test('responde ao ping sem expor dados privados', () async {
      final response = await client.get(_uri(server, ApiRoutes.ping));
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['deviceId'], 'receiver-id');
      expect(body['status'], 'alive');
      expect(body, isNot(contains('receiveDirectory')));
    });

    test('faz handshake e grava o upload como stream', () async {
      final bytes = utf8.encode('conteúdo local');
      final handshake = await client.post(
        _uri(server, ApiRoutes.transferRequest),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({
          'senderDeviceId': 'sender-id',
          'senderDeviceName': 'Sender',
          'files': [
            {
              'fileId': 'file-1',
              'fileName': '../documento.txt',
              'fileSize': bytes.length,
              'mimeType': 'text/plain',
              'sha256': null,
            },
          ],
          'totalSize': bytes.length,
        }),
      );
      expect(handshake.statusCode, 200);
      final sessionId =
          (jsonDecode(handshake.body) as Map<String, dynamic>)['sessionId']
              as String;

      final upload = http.StreamedRequest(
        'POST',
        _uri(server, ApiRoutes.upload(sessionId, 'file-1')),
      )..contentLength = bytes.length;
      final responseFuture = client.send(upload);
      upload.sink.add(bytes);
      await upload.sink.close();
      final uploadResponse = await responseFuture;

      expect(uploadResponse.statusCode, 200);
      final saved = File('${receiveDirectory.path}/documento.txt');
      expect(await saved.exists(), isTrue);
      expect(await saved.readAsString(), 'conteúdo local');

      final completion = await client.get(
        _uri(server, ApiRoutes.complete(sessionId)),
      );
      expect(completion.statusCode, 200);
      expect(completion.body, contains('completed'));
    });

    test('recusa metadados inconsistentes antes de escrever', () async {
      final response = await client.post(
        _uri(server, ApiRoutes.transferRequest),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({
          'senderDeviceId': 'sender-id',
          'senderDeviceName': 'Sender',
          'files': [
            {
              'fileId': 'file-1',
              'fileName': 'documento.txt',
              'fileSize': 10,
              'mimeType': 'text/plain',
            },
          ],
          'totalSize': 99,
        }),
      );

      expect(response.statusCode, 422);
      expect(receiveDirectory.listSync(), isEmpty);
    });

    test('recusa tipos JSON inesperados como erro de cliente', () async {
      final response = await client.post(
        _uri(server, ApiRoutes.transferRequest),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({
          'senderDeviceId': 'sender-id',
          'senderDeviceName': 'Sender',
          'files': [
            {
              'fileId': 'file-1',
              'fileName': 'documento.txt',
              'fileSize': 10,
              'mimeType': 'text/plain',
              'sha256': 123,
            },
          ],
          'totalSize': 10,
        }),
      );

      expect(response.statusCode, 422);
      expect(response.body, contains('invalid_json'));
      expect(receiveDirectory.listSync(), isEmpty);
    });
  });
}

Uri _uri(LocalHttpServer server, String path) => Uri(
  scheme: 'http',
  host: InternetAddress.loopbackIPv4.address,
  port: server.port,
  path: path,
);
