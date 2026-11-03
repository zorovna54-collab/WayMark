import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:http/http.dart' as http;

import '../features/admin/draft_map.dart' show newDraftGuid;

import '../models/route_models.dart';
import '../features/navigation/local_map_navigation.dart';
import 'auth_session.dart';
import 'published_map_api_service.dart';

class NavigationHistoryService {
  NavigationHistoryService({http.Client? client, String? baseUrl})
    : maps = PublishedMapApiService(client: client, baseUrl: baseUrl);
  final PublishedMapApiService maps;
  static final changes = ValueNotifier<int>(0);
  static void changed() => changes.value++;
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (token == null) {
      throw const FormatException(
        'Đăng nhập để xem lịch sử của bạn. Guest vẫn dẫn đường bình thường.',
      );
    }
    final result = await maps.json(
      'me/navigation-history$path',
      method: method,
      body: body,
      private: true,
    );
    if (!AuthSession.isCurrent(token, revision)) {
      throw const FormatException('Phiên đăng nhập đã thay đổi.');
    }
    if (method != 'GET') changed();
    return result;
  }

  Future<List<Map<String, dynamic>>> list() async =>
      (await request('') as List).cast<Map<String, dynamic>>();
  Future<void> delete(String id) async {
    final token = AuthSession.accessToken;
    final revision = AuthSession.revision;
    if (token == null) {
      throw const FormatException('Đăng nhập lại để xóa lịch sử.');
    }
    await maps.request(
      'me/navigation-history/$id',
      method: 'DELETE',
      private: true,
    );
    if (!AuthSession.isCurrent(token, revision)) {
      throw const FormatException('Phiên đăng nhập đã thay đổi.');
    }
    changed();
  }
}

/// Created only after a valid QR resolves to a retrievable published snapshot.
/// Same instance follows Search/Preview/Navigation; serialized writes retain ID on retry.
void recordPublishedScan(
  PublishedMapSession session, {
  NavigationHistoryService? service,
}) {
  final map = session.map;
  if (map.historySession != null) return;
  final history = NavigationHistorySession.scanned(
    service ?? NavigationHistoryService(),
    map,
  );
  map.historySession = history;
  unawaited(history.scanned());
}

class NavigationHistorySession {
  NavigationHistorySession.scanned(this.service, this.map)
    : _token = AuthSession.accessToken,
      _revision = AuthSession.revision;
  NavigationHistorySession(this.service, this.map, this.route)
    : _token = AuthSession.accessToken,
      _revision = AuthSession.revision;
  final NavigationHistoryService service;
  final LocalMapNavigation? map;
  WayMarkRoute? route;
  final String? _token;
  final int _revision;
  final id = newDraftGuid();
  final message = ValueNotifier<String>('');
  Future<void> _tail = Future.value();
  bool _created = false, _begun = false;
  String? _selected, _terminal;
  bool get ended => _terminal != null;
  bool get eligible =>
      _token != null &&
      map?.publication != null &&
      map?.publicationQrPayload != null;
  bool get _sameUser => AuthSession.isCurrent(_token, _revision);
  Future<void> _queue(Future<void> Function() action) {
    final op = _tail.then((_) async {
      if (!eligible) {
        message.value = _token == null
            ? 'Guest: không lưu lịch sử tài khoản.'
            : 'Bản local/legacy: không ghi lịch sử Published.';
        return;
      }
      if (!_sameUser) return;
      try {
        await action();
      } catch (_) {
        message.value = 'Chưa đồng bộ lịch sử. Kiểm tra mạng hoặc schema History; tuyến vẫn dùng được. Có thể Thử lại.';
      }
    });
    _tail = op;
    return op;
  }

  Future<void> _ensureScan() async {
    if (_created) return;
    await service.request(
      '',
      method: 'POST',
      body: {
        'sessionId': id,
        'qrToken': publicQrToken(map!.publicationQrPayload!),
      },
    );
    _created = true;
    message.value = 'Đã lưu lần quét QR • chưa chọn điểm đến.';
  }

  Future<void> scanned() => _queue(_ensureScan);
  Future<void> _select(WayMarkRoute next) async {
    await _ensureScan();
    if (!_sameUser) return;
    final target = map!.stableIdentity(
      next.nodes.last.id,
      next.nodes.last.floor.id,
    );
    final key = '${target.floorKey}/${target.nodeId}';
    if (_selected == key) return;
    await service.request(
      '/$id/destination',
      method: 'PUT',
      body: {
        'destinationFloorKey': target.floorKey,
        'destinationNodeId': target.nodeId,
      },
    );
    _selected = key;
    route = next;
    message.value = 'Đã lưu điểm đến; chưa bắt đầu dẫn đường.';
  }

  Future<void> select(WayMarkRoute next) => _queue(() async {
    if (_terminal == null && !_begun) await _select(next);
  });
  Future<void> start([WayMarkRoute? next]) => _queue(() async {
    if (_terminal != null || _begun) return;
    final selected = next ?? route;
    if (selected == null) return;
    route = selected;
    await _select(selected);
    if (!_sameUser) return;
    await service.request('/$id/start', method: 'PUT');
    _begun = true;
    message.value = 'Đã lưu: đang dẫn đường • xác nhận vị trí thủ công/QR.';
  });
  Future<void> finish(String status) => _queue(() async {
    if (_terminal != null) return;
    await _ensureScan();
    if (!_sameUser) return;
    if (status == 'Completed' && !_begun && route != null) {
      await _select(route!);
      if (!_sameUser) return;
      await service.request('/$id/start', method: 'PUT');
      _begun = true;
    }
    if (status == 'Completed' && !_begun) {
      throw const FormatException('Chưa xác nhận bắt đầu dẫn đường.');
    }
    await service.request('/$id', method: 'PUT', body: {'status': status});
    _terminal = status;
    message.value = status == 'Completed'
        ? 'Đã lưu hoàn tất theo xác nhận của bạn.'
        : 'Đã lưu hủy phiên.';
  });
}
