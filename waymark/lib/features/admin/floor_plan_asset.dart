import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show MemoryImage;

/// Local draft input only. Not a publication or a server filesystem path.
class FloorPlanAsset {
  FloorPlanAsset._(this.bytes, this.name, this.mime, this.width, this.height);
  final Uint8List bytes;
  // The Web image decoder's JS interop expects a native Uint8List, not Dart's
  // _UnmodifiableUint8ListView. Keep the draft bytes immutable; copy once at
  // the rendering boundary and reuse the provider across editor rebuilds.
  late final MemoryImage imageProvider = MemoryImage(Uint8List.fromList(bytes));
  final String name, mime;
  final int width, height;
  static const maxBytes = 10 * 1024 * 1024;

  static Future<FloorPlanAsset> validate(
    Uint8List bytes,
    String name,
    String mime,
  ) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
        'Ảnh phải có dung lượng từ 1 byte đến 10 MB.',
      );
    }
    final png =
        bytes.length >= 8 &&
        List.generate(8, (i) => bytes[i]).join(',') ==
            '137,80,78,71,13,10,26,10';
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final safeName = name.replaceAll('\\', '/').split('/').last.trim();
    if (safeName.length > 255 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(safeName)) {
      throw const FormatException('Tên ảnh không hợp lệ.');
    }
    final lower = safeName.toLowerCase();
    // Some OS file providers supply no MIME. Extension + magic + actual decode
    // still have to agree; a supplied incorrect MIME is never accepted.
    if (mime.isEmpty) mime = png ? 'image/png' : 'image/jpeg';
    if (!(png && lower.endsWith('.png') && mime == 'image/png') &&
        !(jpeg &&
            (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) &&
            mime == 'image/jpeg')) {
      throw const FormatException(
        'Chỉ nhận PNG/JPG có phần mở rộng, MIME và nội dung khớp nhau.',
      );
    }
    // Read encoded dimensions before allocating pixels, including on Web.
    final dimensions = _encodedSize(bytes, png);
    _checkSize(dimensions.$1, dimensions.$2);
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      // ImageDescriptor.encoded.width/height throw UnsupportedError on Web.
      // Decode a real frame instead: also rejects files with only a valid header.
      codec = await ui.instantiateImageCodec(bytes);
      decoded = (await codec.getNextFrame()).image;
      _checkSize(decoded.width, decoded.height);
      return FloorPlanAsset._(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        safeName.isEmpty ? (png ? 'floor.png' : 'floor.jpg') : safeName,
        mime,
        decoded.width,
        decoded.height,
      );
    } catch (_) {
      throw const FormatException(
        'Ảnh hỏng, không giải mã được hoặc vượt giới hạn kích thước.',
      );
    } finally {
      decoded?.dispose();
      codec?.dispose();
    }
  }

  static void _checkSize(int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        width > 8192 ||
        height > 8192 ||
        width * height > 32000000) {
      throw const FormatException(
        'Ảnh tối đa 8192 px mỗi chiều và 32 triệu pixel.',
      );
    }
  }

  static (int, int) _encodedSize(Uint8List bytes, bool png) {
    if (png &&
        bytes.length >= 33 &&
        String.fromCharCodes(bytes.sublist(12, 16)) == 'IHDR') {
      final data = ByteData.sublistView(bytes);
      return (data.getUint32(16), data.getUint32(20));
    }
    if (!png) {
      var offset = 2;
      while (offset + 3 < bytes.length) {
        if (bytes[offset++] != 0xff) break;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset++;
        }
        if (offset >= bytes.length) break;
        final marker = bytes[offset++];
        if (marker == 0xd9 || marker == 0xda) break;
        if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd8) continue;
        if (offset + 1 >= bytes.length) break;
        final length = (bytes[offset] << 8) | bytes[offset + 1];
        if (length < 2 || offset + length > bytes.length) break;
        if (const [
              0xc0,
              0xc1,
              0xc2,
              0xc3,
              0xc5,
              0xc6,
              0xc7,
              0xc9,
              0xca,
              0xcb,
              0xcd,
              0xce,
              0xcf,
            ].contains(marker) &&
            length >= 8) {
          return (
            (bytes[offset + 5] << 8) | bytes[offset + 6],
            (bytes[offset + 3] << 8) | bytes[offset + 4],
          );
        }
        offset += length;
      }
    }
    throw const FormatException('Không đọc được kích thước ảnh PNG/JPG.');
  }
}
