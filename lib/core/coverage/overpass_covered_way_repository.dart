import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'mock_covered_ways.dart';
import 'models/covered_way.dart';

/// OpenStreetMap の屋根付き経路データを Overpass API から取得する。
///
/// 取得対象タグ:
///   covered=yes   → アーケード商店街・屋根付き歩道
///   tunnel=yes    → 地下道・地下街
///   indoor=yes    → 屋内通路
///
/// すべて highway タグを持つ way のみ対象（建物の壁を除外）。
/// 取得失敗時は MockCoveredWays にフォールバックする。
class OverpassCoveredWayRepository {
  OverpassCoveredWayRepository({
    http.Client? client,
    List<String>? endpoints,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        endpoints = endpoints ??
            const [
              'https://overpass-api.de/api/interpreter',
              'https://overpass.kumi.systems/api/interpreter',
              'https://overpass.private.coffee/api/interpreter',
            ];

  final http.Client _client;
  final List<String> endpoints;
  final Duration timeout;

  Future<List<CoveredWay>> fetchAround(
      LatLng center, double radiusMeters) async {
    final r = radiusMeters.round();
    final lat = center.latitude;
    final lng = center.longitude;
    // highway を持つ covered/tunnel/indoor の way を取得
    final query = '[out:json][timeout:12];'
        '('
        'way["covered"="yes"]["highway"](around:$r,$lat,$lng);'
        'way["tunnel"="yes"]["highway"](around:$r,$lat,$lng);'
        'way["indoor"="yes"]["highway"](around:$r,$lat,$lng);'
        ');out geom;';
    final data = 'data=${Uri.encodeComponent(query)}';

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final res =
            await _client.get(Uri.parse('$endpoint?$data')).timeout(timeout);
        if (res.statusCode != 200) {
          lastError = Exception('Overpass HTTP ${res.statusCode}');
          continue;
        }
        final ways = parse(res.body);
        // 実データが1件以上あればそれを使う。空ならモックにフォールバック。
        return ways.isNotEmpty ? ways : MockCoveredWays.tokyoStation();
      } catch (e) {
        lastError = e;
      }
    }
    // 全ミラー失敗 → モック
    return MockCoveredWays.tokyoStation();
  }

  /// Overpass JSON を CoveredWay リストへ変換（テスト可能な純関数）。
  static List<CoveredWay> parse(String body) {
    final root = json.decode(body);
    final elements =
        (root is Map ? root['elements'] as List? : null) ?? const [];
    final result = <CoveredWay>[];

    for (final el in elements) {
      if (el is! Map || el['type'] != 'way') continue;
      final geom = el['geometry'] as List?;
      if (geom == null || geom.length < 2) continue;

      final path = <LatLng>[
        for (final g in geom)
          if (g is Map && g['lat'] != null && g['lon'] != null)
            LatLng((g['lat'] as num).toDouble(),
                (g['lon'] as num).toDouble()),
      ];
      if (path.length < 2) continue;

      final tags =
          (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};

      // tunnel=yes または layer が負数 → 地下道
      final layerVal =
          int.tryParse(tags['layer']?.toString() ?? '');
      final isTunnel = tags['tunnel'] == 'yes' ||
          (layerVal != null && layerVal < 0);

      result.add(CoveredWay(
        id: 'osm_${el['id']}',
        path: path,
        type: isTunnel ? CoveredType.underground : CoveredType.arcade,
      ));
    }
    return result;
  }

  void dispose() => _client.close();
}
