import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/geo/geo_utils.dart';
import '../../core/shade/models/building.dart';
import 'building_repository.dart';

/// OpenStreetMap の建物データ（実データ）を Overpass API からライブ取得する。
/// 無料・APIキー不要。指定範囲の `building` ウェイを取得し、
/// 高さは `height` タグ → `building:levels`×3m → 既定値 の順で決定する。
///
/// 公式サーバ（overpass-api.de）は混雑で 504 を返すことがあるため、
/// 複数のミラーを順に試すフォールバックを持つ。
class OverpassBuildingRepository extends BuildingRepository {
  OverpassBuildingRepository({
    http.Client? client,
    List<String>? endpoints,
    this.maxBuildings = 6000,
    this.defaultHeightMeters = 8.0,
    this.metersPerLevel = 3.0,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        endpoints = endpoints ??
            const [
              'https://overpass-api.de/api/interpreter',
              'https://overpass.kumi.systems/api/interpreter',
              'https://overpass.private.coffee/api/interpreter',
            ];

  final http.Client _client;
  final List<String> endpoints;
  final int maxBuildings;
  final double defaultHeightMeters;
  final double metersPerLevel;
  final Duration timeout;

  @override
  Future<List<Building>> fetchBuildings(GeoBounds bounds) async {
    final s = bounds.southWest.latitude;
    final w = bounds.southWest.longitude;
    final n = bounds.northEast.latitude;
    final e = bounds.northEast.longitude;
    final query =
        '[out:json][timeout:15];(way["building"]($s,$w,$n,$e););out geom;';
    return _run(query);
  }

  /// 円（around）で取得。徒歩圏の真円フィルタ。
  @override
  Future<List<Building>> fetchAround(LatLng center, double radiusMeters) {
    final r = radiusMeters.round();
    final lat = center.latitude;
    final lng = center.longitude;
    final query = '[out:json][timeout:15];'
        '(way["building"](around:$r,$lat,$lng););out geom;';
    return _run(query);
  }

  Future<List<Building>> _run(String query) async {
    final data = 'data=${Uri.encodeComponent(query)}';

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final res = await _client
            .get(Uri.parse('$endpoint?$data'))
            .timeout(timeout);
        if (res.statusCode != 200) {
          lastError = Exception('Overpass HTTP ${res.statusCode}');
          continue; // 次のミラーへ
        }
        return parse(
          res.body,
          maxBuildings: maxBuildings,
          defaultHeightMeters: defaultHeightMeters,
          metersPerLevel: metersPerLevel,
        );
      } catch (e) {
        lastError = e; // タイムアウト等 → 次のミラーへ
      }
    }
    throw Exception('Overpass 全ミラー失敗: $lastError');
  }

  /// Overpass JSON 文字列を Building リストへ変換する（テスト可能な純関数）。
  static List<Building> parse(
    String body, {
    int maxBuildings = 2500,
    double defaultHeightMeters = 8.0,
    double metersPerLevel = 3.0,
  }) {
    final root = json.decode(body);
    final elements = (root is Map ? root['elements'] as List? : null) ?? const [];
    final result = <Building>[];

    for (final el in elements) {
      if (el is! Map) continue;
      if (el['type'] != 'way') continue;
      final geom = el['geometry'] as List?;
      if (geom == null || geom.length < 3) continue;

      final footprint = <LatLng>[
        for (final g in geom)
          if (g is Map && g['lat'] != null && g['lon'] != null)
            LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
      ];
      if (footprint.length >= 2 &&
          footprint.first.latitude == footprint.last.latitude &&
          footprint.first.longitude == footprint.last.longitude) {
        footprint.removeLast();
      }
      if (footprint.length < 3) continue;

      final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      result.add(Building(
        id: 'osm_${el['id']}',
        footprint: footprint,
        heightMeters: _height(tags, defaultHeightMeters, metersPerLevel),
      ));
      if (result.length >= maxBuildings) break;
    }
    return result;
  }

  static double _height(
    Map<String, dynamic> tags,
    double fallback,
    double metersPerLevel,
  ) {
    final h = tags['height'];
    if (h != null) {
      final v = double.tryParse(h.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && v > 0) return v;
    }
    final lv = tags['building:levels'];
    if (lv != null) {
      final v = double.tryParse(lv.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && v > 0) return v * metersPerLevel;
    }
    return fallback;
  }

  void dispose() => _client.close();
}
