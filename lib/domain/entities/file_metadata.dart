class FileMetadata {
  const FileMetadata({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.sha256,
  });

  final String fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String? sha256;

  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    final fileId = json['fileId'];
    final fileName = json['fileName'];
    final fileSize = json['fileSize'];
    final mimeType = json['mimeType'];
    final sha256 = json['sha256'];
    if (fileId is! String ||
        fileName is! String ||
        fileSize is! num ||
        mimeType is! String ||
        (sha256 != null && sha256 is! String)) {
      throw const FormatException('Metadados de arquivo inválidos.');
    }
    return FileMetadata(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize.toInt(),
      mimeType: mimeType,
      sha256: sha256 as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'fileName': fileName,
    'fileSize': fileSize,
    'mimeType': mimeType,
    'sha256': sha256,
  };

  bool get isValid =>
      fileId.isNotEmpty &&
      fileId.length <= 80 &&
      fileName.trim().isNotEmpty &&
      fileName.length <= 255 &&
      fileSize >= 0 &&
      (sha256 == null || RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256!));
}
