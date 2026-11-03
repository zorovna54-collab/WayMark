import 'package:flutter/services.dart';

const draftFilesChannel = MethodChannel('waymark/draft_files');

Future<({Uint8List bytes, String name, String mime})?> pickDraftFile(
  String accept,
  int maxBytes,
) async {
  final value = await draftFilesChannel.invokeMapMethod<String, dynamic>(
    'pick',
    {'image': accept.contains('.png'), 'maxBytes': maxBytes},
  );
  if (value == null) return null;
  final bytes = value['bytes'];
  if (bytes is! Uint8List || bytes.isEmpty || bytes.length > maxBytes) {
    throw const FormatException('File rỗng hoặc vượt giới hạn dung lượng.');
  }
  return (
    bytes: Uint8List.fromList(bytes),
    name: value['name'] as String,
    mime: value['mime'] as String,
  );
}

Future<void> downloadDraftFile(
  Uint8List bytes,
  String name,
  String mime,
) async {
  final saved = await draftFilesChannel.invokeMethod<bool>('save', {
    'bytes': bytes,
    'name': name,
    'mime': mime,
  });
  if (saved != true) {
    throw const FormatException(
      'Đã hủy lưu file. Bản nháp vẫn giữ nguyên; chưa lưu ra thiết bị.',
    );
  }
}
