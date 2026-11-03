import 'dart:async';

import 'package:http/http.dart' as http;

import 'map_draft_api_service.dart';

enum PublishedReadCode {
  invalidEndpoint,
  invalidQr,
  network,
  timeout,
  qrRevoked,
  qrUnavailable,
  mapMismatch,
  versionMismatch,
  anchorMissing,
  snapshotInvalid,
  imageUnavailable,
  unavailable,
}

class PublishedReadException extends FormatException {
  const PublishedReadException(this.kind);
  final PublishedReadCode kind;
  String get code => 'published_${kind.name}';
  @override
  String get message => switch (kind) {
    PublishedReadCode.invalidEndpoint => 'Endpoint không hợp lệ. Nhập http(s)://host/api, không kèm tài khoản, token hoặc query.',
    PublishedReadCode.invalidQr =>
      'Mã QR không đúng định dạng WayMark. Hãy quét lại hoặc nhập mã hợp lệ.',
    PublishedReadCode.network => 'Chưa thể xác minh mã QR do không kết nối được máy chủ. Kiểm tra mạng và endpoint; bạn vẫn có thể dùng chỉ đường thủ công.',
    PublishedReadCode.timeout => 'Máy chủ phản hồi quá lâu, chưa xác minh được QR. Thử lại khi kết nối ổn định; vị trí và tuyến hiện tại được giữ.',
    PublishedReadCode.qrRevoked => 'Mã QR đã bị thu hồi. Không cập nhật vị trí; dùng QR khác hoặc chỉ đường thủ công.',
    PublishedReadCode.qrUnavailable => 'QR chưa xuất bản, không còn khả dụng hoặc không tìm thấy. Hãy đối chiếu mã với người quản lý bản đồ.',
    PublishedReadCode.mapMismatch => 'QR thuộc bản đồ khác. Tuyến hiện tại được giữ; mở hành trình mới nếu muốn đổi bản đồ.',
    PublishedReadCode.versionMismatch => 'Bản đồ đã thay đổi phiên bản hoặc QR thuộc phiên bản khác. Vui lòng mở lại hành trình phù hợp.',
    PublishedReadCode.anchorMissing => 'Không tìm thấy điểm hoặc tầng của QR trong snapshot đang dùng. Không cập nhật vị trí.',
    PublishedReadCode.snapshotInvalid => 'Bản đồ chưa có đủ dữ liệu hợp lệ để mở hành trình. Kiểm tra snapshot, ảnh tầng và các liên kết; không tự sửa dữ liệu.',
    PublishedReadCode.imageUnavailable => 'Không tìm thấy hoặc không hiển thị được ảnh tầng cần dùng. Thử tải lại bản đồ; nếu vẫn lỗi, liên hệ người quản lý bản đồ.',
    PublishedReadCode.unavailable => 'Chưa tải được bản đồ công khai. Thử lại hoặc dùng hành trình đã tải; chưa xác minh QR mới.',
  };
  @override
  String toString() => message;
}

String? publishedEndpoint(String raw) {
  final value = raw.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.port <= 0 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.endsWith('/api') ||
      RegExp(r'[\x00-\x20]').hasMatch(value)) {
    return null;
  }
  return value;
}

PublishedReadException publishedReadFailure(Object error) {
  if (error is PublishedReadException) return error;
  if (error is TimeoutException) {
    return const PublishedReadException(PublishedReadCode.timeout);
  }
  if (error is http.ClientException) {
    return const PublishedReadException(PublishedReadCode.network);
  }
  if (error is MapDraftApiException) {
    if (error.code == 'timeout') {
      return const PublishedReadException(PublishedReadCode.timeout);
    }
    if (error.code == 'network') {
      return const PublishedReadException(PublishedReadCode.network);
    }
    if (error.code == 'qr_revoked') {
      return const PublishedReadException(PublishedReadCode.qrRevoked);
    }
    if (error.code == 'qr_node_missing') {
      return const PublishedReadException(PublishedReadCode.anchorMissing);
    }
    if ([404, 409, 410].contains(error.status)) {
      return const PublishedReadException(PublishedReadCode.qrUnavailable);
    }
  }
  if (error is FormatException || error is TypeError) {
    return const PublishedReadException(PublishedReadCode.snapshotInvalid);
  }
  return const PublishedReadException(PublishedReadCode.unavailable);
}
