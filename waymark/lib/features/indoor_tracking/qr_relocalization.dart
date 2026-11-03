import '../navigation/local_map_navigation.dart';
import 'indoor_position.dart';
import 'tracking_graph.dart';
import '../../services/published_read_failure.dart';

class QrLocalizationFailure implements Exception {
  const QrLocalizationFailure(this.code);
  final String code;
}

/// Reuses the existing server resolver closure (including revoke/version
/// validation). Payloads and raw exception text never enter diagnostics.
class QrRelocalization {
  QrRelocalization(this.map, this.graph);
  final LocalMapNavigation map;
  final TrackingGraph graph;
  bool get available => map.resolvePublishedQr != null && !graph.localPilot;

  Future<VerifiedTrackingAnchor> resolve(String payload) async {
    if (!available) {
      throw const QrLocalizationFailure('publishedResolverRequired');
    }
    try {
      void checkPin() {
        if (map.publication?.mapId != graph.key.mapId ||
            map.publication?.version != graph.key.version) {
          throw const QrLocalizationFailure('mapVersionMismatch');
        }
      }

      checkPin();
      final location = await map.resolvePublishedQr!(payload);
      checkPin();
      final node = location.node;
      if (node == null) throw const QrLocalizationFailure('nodeMissing');
      final id = map.stableIdentity(node.id, node.floorId);
      final anchor = VerifiedTrackingAnchor(
        graph.key,
        id.nodeId.toLowerCase(),
        id.floorKey.toLowerCase(),
        PositionSource.qr,
      );
      anchor.position(graph); // Membership check before any position update.
      return anchor;
    } on QrLocalizationFailure {
      rethrow;
    } catch (error) {
      throw QrLocalizationFailure(publishedReadFailure(error).code);
    }
  }
}
