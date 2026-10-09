import 'dart:typed_data';

class LeaveAttachment {
  const LeaveAttachment({
    required this.fileName,
    required this.bytes,
    required this.sizeBytes,
  });

  final String fileName;
  final Uint8List bytes;
  final int sizeBytes;

  String get extensionLower {
    final idx = fileName.lastIndexOf('.');
    if (idx < 0 || idx == fileName.length - 1) {
      return '';
    }
    return fileName.substring(idx + 1).toLowerCase();
  }
}
