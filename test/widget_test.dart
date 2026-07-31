import 'package:flutter_test/flutter_test.dart';
import 'package:local_bridge/core/utils/file_size_formatter.dart';
import 'package:local_bridge/core/utils/safe_file_name.dart';
import 'package:local_bridge/domain/entities/file_metadata.dart';

void main() {
  test('sanitiza nomes sem permitir travessia de diretório', () {
    expect(safeFileName('../segredo.txt'), 'segredo.txt');
    expect(safeFileName(r'..\foto?.jpg'), 'foto_.jpg');
  });

  test('formata tamanhos de arquivo', () {
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(1024), '1.00 KB');
  });

  test('valida metadados recebidos', () {
    const valid = FileMetadata(
      fileId: "file-1",
      fileName: "foto.jpg",
      fileSize: 42,
      mimeType: "image/jpeg",
    );
    expect(valid.isValid, isTrue);
    expect(FileMetadata.fromJson(valid.toJson()).toJson(), valid.toJson());
  });
}
