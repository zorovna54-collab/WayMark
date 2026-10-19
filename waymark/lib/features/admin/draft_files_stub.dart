import 'dart:typed_data';

Future<({Uint8List bytes, String name, String mime})?> pickDraftFile(
  String accept,
  int maxBytes,
) async =>
    throw UnsupportedError('Chọn file bản nháp hiện hỗ trợ trên Flutter Web.');
void downloadDraftFile(Uint8List bytes, String name, String mime) =>
    throw UnsupportedError('Xuất file bản nháp hiện hỗ trợ trên Flutter Web.');
