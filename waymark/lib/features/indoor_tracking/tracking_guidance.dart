import 'indoor_position.dart';
import '../../services/published_read_failure.dart';

TrackingGuidance qrTrackingGuidance(String code) {
  final kind =
      PublishedReadCode.values
          .where((k) => 'published_${k.name}' == code)
          .firstOrNull ??
      (code == 'mapVersionMismatch'
          ? PublishedReadCode.versionMismatch
          : code == 'nodeMissing'
          ? PublishedReadCode.anchorMissing
          : null);
  if (kind == null) return trackingGuidance('qrCorrectionRejected');
  return TrackingGuidance(
    PublishedReadException(kind).message,
    TrackingRecovery.anchor,
    'Xác nhận lại vị trí / QR',
  );
}

enum TrackingRecovery { anchor, sensors, stride, direction, none, manual }

class TrackingGuidance {
  const TrackingGuidance(this.message, this.action, this.button);
  final String message, button;
  final TrackingRecovery action;
}

String trackingStatusLabel(TrackingStatus status) => switch (status) {
  TrackingStatus.needsAnchor => 'Cần xác nhận vị trí',
  TrackingStatus.anchored => 'Đã xác nhận vị trí',
  TrackingStatus.calibrating => 'Đang chuẩn bị',
  TrackingStatus.tracking => 'Đang ước lượng theo bước',
  TrackingStatus.uncertain => 'Chưa chắc chắn',
  TrackingStatus.relocalizing => 'Đang đối chiếu QR',
  TrackingStatus.paused => 'Cảm biến đang tạm dừng',
  TrackingStatus.permissionDenied => 'Chưa có quyền bước chân',
  TrackingStatus.sensorUnavailable => 'Thiếu cảm biến bước',
  TrackingStatus.finished => 'Đã kết thúc Live',
  TrackingStatus.failed => 'Cảm biến gặp lỗi',
};

String confidenceLabel(PositionConfidence? confidence) => switch (confidence) {
  PositionConfidence.confirmedAtScan => 'QR xác nhận tại thời điểm quét',
  PositionConfidence.manualConfirmation => 'Do bạn xác nhận thủ công',
  PositionConfidence.estimated => 'Vị trí ước lượng',
  PositionConfidence.uncertain => 'Vị trí chưa chắc chắn',
  null => 'Chưa có vị trí',
};

TrackingGuidance trackingGuidance(String code) => switch (code) {
  'needsAnchor' => const TrackingGuidance(
    'Bạn cần xác nhận vị trí ban đầu.',
    TrackingRecovery.anchor,
    'Xác nhận vị trí',
  ),
  'anchorAged' => const TrackingGuidance(
    'Đã đến giới hạn 40 bước ước lượng. Hãy xác nhận lại vị trí; chọn hướng không đặt lại giới hạn này.',
    TrackingRecovery.anchor,
    'Xác nhận lại vị trí',
  ),
  'sensorOverflow' => const TrackingGuidance(
    'Mất sự kiện cảm biến. Đang giữ vị trí; hãy xác nhận lại mốc.',
    TrackingRecovery.anchor,
    'Xác nhận lại vị trí',
  ),
  'candidateNodeConfirm' || 'junctionConfirmation' => const TrackingGuidance(
    'Bạn có thể đang gần một điểm giao. Hãy chọn hành lang đang đi hoặc xác nhận lại vị trí nếu không chắc.',
    TrackingRecovery.direction,
    'Chọn hành lang tiếp theo',
  ),
  'selectEdgeAndAlign' || 'alignAfterStart' => const TrackingGuidance(
    'Hãy chọn hành lang sắp đi và hướng đỉnh điện thoại theo chiều đó.',
    TrackingRecovery.direction,
    'Chuẩn bị hướng đi',
  ),
  'staleOrientation' ||
  'headingRequired' ||
  'headingConflict' => const TrackingGuidance(
    'Chưa xác định được hướng điện thoại đáng tin cậy. Giữ máy gần nằm ngang và hiệu chuẩn lại.',
    TrackingRecovery.direction,
    'Hiệu chuẩn hướng',
  ),
  'strideRequired' => const TrackingGuidance(
    'Hãy nhập và xác nhận chiều dài mỗi bước trước khi đi.',
    TrackingRecovery.stride,
    'Hiệu chuẩn bước',
  ),
  'activityPermissionDenied' => const TrackingGuidance(
    'Chưa có quyền nhận diện hoạt động. Cấp quyền trong bước cảm biến hoặc dùng điều hướng thủ công.',
    TrackingRecovery.sensors,
    'Kiểm tra cảm biến',
  ),
  'stepDetectorUnavailable' ||
  'sensorFailure' ||
  'unsupportedGeometry' => const TrackingGuidance(
    'Cảm biến hoặc hình học hành lang chưa phù hợp. Bạn vẫn có thể dùng điều hướng thủ công / QR.',
    TrackingRecovery.manual,
    'Về manual / QR',
  ),
  'pausedNeedsConfirmation' ||
  'qrCancelledResumeExplicitly' => const TrackingGuidance(
    'Cảm biến đang tạm dừng. Nếu đã di chuyển, hãy xác nhận lại vị trí; nếu chưa, tiếp tục rồi hướng lại máy.',
    TrackingRecovery.sensors,
    'Chuẩn bị tiếp tục',
  ),
  'confirmNewFloor' => const TrackingGuidance(
    'Chưa xác nhận tầng mới. Quét QR hoặc chọn đúng điểm và tầng đang đứng.',
    TrackingRecovery.anchor,
    'Xác nhận tầng mới',
  ),
  'qrCorrectionRejected' => const TrackingGuidance(
    'QR không được chấp nhận hoặc mất mạng. Đang giữ vị trí cũ; thử quét lại hoặc xác nhận thủ công.',
    TrackingRecovery.anchor,
    'Xác nhận lại vị trí',
  ),
  'scanQr' => const TrackingGuidance(
    'Cảm biến đã dừng để đối chiếu QR. QR không xác định hướng đi.',
    TrackingRecovery.none,
    '',
  ),
  'estimated' ||
  'reverse' ||
  'manualDirectionExperiment' => const TrackingGuidance(
    'Vị trí cập nhật khi nhận bước. Đứng yên thì chấm không tự tiến; không dùng ước lượng để xác nhận đã đến đích.',
    TrackingRecovery.none,
    '',
  ),
  'againstOneWay' => const TrackingGuidance(
    'Ước lượng đang ngược chiều hành lang một chiều. Hãy đối chiếu lại vị trí và hướng.',
    TrackingRecovery.anchor,
    'Xác nhận lại vị trí',
  ),
  'mapVersionChanged' => const TrackingGuidance(
    'Phiên bản bản đồ đã đổi. Hãy về điều hướng thủ công và mở lại phiên với snapshot phù hợp.',
    TrackingRecovery.manual,
    'Về manual / QR',
  ),
  'finished' => const TrackingGuidance(
    'Đã ngừng thu cảm biến cho phiên này.',
    TrackingRecovery.none,
    '',
  ),
  _ => const TrackingGuidance(
    'Chưa đủ thông tin để tiếp tục. Xác nhận lại vị trí hoặc quét QR.',
    TrackingRecovery.anchor,
    'Xác nhận vị trí',
  ),
};

String trackingReasonLabel(String code) => trackingGuidance(code).message;
