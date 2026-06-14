import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_config.dart';
import 'models/walk_route.dart';

/// 徒歩ルート取得の抽象。OSM 系の無料ルーターに差し替えられる。
abstract class RoutingService {
  Future<List<WalkRoute>> fetchWalkingRoutes({
    required LatLng origin,
    required LatLng destination,
  });

  /// リソース解放（HTTPクライアント等）。既定は何もしない。
  void dispose() {}
}

/// OpenRouteService（無料枠・APIキーのみ・課金不要）で
/// 徒歩ルート（複数代替）を取得する。
///
/// - プロファイル: foot-walking
/// - alternative_routes で複数候補を取得 → 日陰スコアで選別
/// - geometry は GeoJSON（[経度,緯度]）で受け取りデコード不要
///
/// APIキーは https://openrouteservice.org/dev/ で無料取得し、
/// `--dart-define=ORS_API_KEY=...` で注入する。
class OrsRoutingService implements RoutingService {
  OrsRoutingService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? AppConfig.orsApiKey;

  final http.Client _client;
  final String _apiKey;

  static const _base = 'https://api.openrouteservice.org';

  @override
  Future<List<WalkRoute>> fetchWalkingRoutes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.parse('$_base/v2/directions/foot-walking/geojson');
    final body = json.encode({
      'coordinates': [
        [origin.longitude, origin.latitude],
        [destination.longitude, destination.latitude],
      ],
      // 代替ルートを最大3本要求（日陰比較のため）。
      'alternative_routes': {
        'target_count': 3,
        'weight_factor': 1.6,
        'share_factor': 0.6,
      },
    });

    final res = await _client.post(
      uri,
      headers: {
        'Authorization': _apiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/geo+json',
      },
      body: body,
    );

    if (res.statusCode != 200) {
      throw RoutingException('ORS HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = json.decode(utf8.decode(res.bodyBytes));
    final features = (decoded['features'] as List?) ?? const [];
    if (features.isEmpty) {
      throw RoutingException('ルートが見つかりませんでした');
    }

    final routes = <WalkRoute>[];
    for (var i = 0; i < features.length; i++) {
      final f = features[i] as Map<String, dynamic>;
      final coords =
          (f['geometry']?['coordinates'] as List?) ?? const [];
      final points = [
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      final summary =
          (f['properties']?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      routes.add(WalkRoute(
        id: 'route_$i',
        polyline: points,
        distanceMeters: ((summary['distance'] as num?) ?? 0).round(),
        durationSeconds: ((summary['duration'] as num?) ?? 0).round(),
      ));
    }
    return routes;
  }

  @override
  void dispose() => _client.close();
}

class RoutingException implements Exception {
  RoutingException(this.message);
  final String message;
  @override
  String toString() => 'RoutingException: $message';
}
