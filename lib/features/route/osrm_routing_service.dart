import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'models/walk_route.dart';
import 'routing_service.dart';

/// OSRM 公開デモサーバ（無料・APIキー不要）でルートを取得する。
///
/// 公開デモは `driving`（車）プロファイルのみ提供のため、厳密な歩行ルート
/// ではないが、複数の代替ルートが得られるので日陰スコア比較のデモには十分。
/// より歩行に正確なルートが必要なら ORS（foot-walking, 要無料キー）を使う。
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({
    http.Client? client,
    this.baseUrl = 'https://router.project-osrm.org',
    this.profile = 'driving',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String profile;

  @override
  Future<List<WalkRoute>> fetchWalkingRoutes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final coords =
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}';
    final uri = Uri.parse('$baseUrl/route/v1/$profile/$coords').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'alternatives': '3', // 複数候補を取得（日陰/日向で選び分けるため）
      },
    );

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw RoutingException('OSRM HTTP ${res.statusCode}');
    }
    final routes = parse(res.body);
    if (routes.isEmpty) {
      throw RoutingException('ルートが見つかりませんでした');
    }
    return routes;
  }

  /// OSRM JSON を WalkRoute リストへ変換（テスト可能な純関数）。
  static List<WalkRoute> parse(String body, {String idPrefix = 'route'}) {
    final root = json.decode(body);
    if (root is! Map || root['code'] != 'Ok') return const [];
    final list = (root['routes'] as List?) ?? const [];
    final result = <WalkRoute>[];
    for (var i = 0; i < list.length; i++) {
      final r = list[i] as Map<String, dynamic>;
      final coords =
          (r['geometry']?['coordinates'] as List?) ?? const [];
      final points = [
        for (final c in coords)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (points.length < 2) continue;
      result.add(WalkRoute(
        id: '${idPrefix}_$i',
        polyline: points,
        distanceMeters: ((r['distance'] as num?) ?? 0).round(),
        durationSeconds: ((r['duration'] as num?) ?? 0).round(),
      ));
    }
    return result;
  }

  /// 複数の経由地を通るルートを取得する。日陰/日向バイアス用。
  Future<List<WalkRoute>> fetchWithWaypoints({
    required LatLng origin,
    required List<LatLng> waypoints,
    required LatLng destination,
    required String idPrefix,
  }) async {
    final parts = [
      '${origin.longitude},${origin.latitude}',
      for (final w in waypoints) '${w.longitude},${w.latitude}',
      '${destination.longitude},${destination.latitude}',
    ];
    final uri = Uri.parse('$baseUrl/route/v1/$profile/${parts.join(";")}').replace(
      queryParameters: {'overview': 'full', 'geometries': 'geojson'},
    );
    try {
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      return parse(res.body, idPrefix: idPrefix);
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() => _client.close();
}
