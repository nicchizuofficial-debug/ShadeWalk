import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../shade/models/building.dart';

/// GeoJSON（FeatureCollection）から建物リストを生成する。
///
/// 想定フォーマット（PLATEAU の CityGML を前処理して得る GeoJSON）:
/// ```json
/// {
///   "type": "FeatureCollection",
///   "features": [{
///     "type": "Feature",
///     "properties": { "id": "bldg-1", "measuredHeight": 31.5 },
///     "geometry": { "type": "Polygon",
///       "coordinates": [[ [lng,lat], [lng,lat], ... ]] }
///   }]
/// }
/// ```
/// 注意: GeoJSON の座標順は [経度, 緯度]。LatLng は (緯度, 経度) なので反転する。
class GeoJsonParser {
  GeoJsonParser._();

  /// 建物高さとして参照するプロパティ名の候補（先に見つかったものを採用）。
  static const _heightKeys = [
    'measuredHeight',
    'bldg:measuredHeight',
    'height',
  ];

  /// 高さが取得できない場合のフォールバック [m]。
  static const double defaultHeightMeters = 10.0;

  static List<Building> parse(String geoJsonString) {
    final root = json.decode(geoJsonString);
    if (root is! Map || root['type'] != 'FeatureCollection') {
      throw const FormatException('FeatureCollection ではありません');
    }
    final features = (root['features'] as List?) ?? const [];
    final buildings = <Building>[];

    for (var i = 0; i < features.length; i++) {
      final f = features[i] as Map<String, dynamic>;
      final geometry = f['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};

      final height = _readHeight(props);
      final id = (props['id'] ?? props['gml:id'] ?? 'bldg_$i').toString();

      // Polygon / MultiPolygon の外周リングのみを使用する。
      final rings = _outerRings(geometry);
      for (var r = 0; r < rings.length; r++) {
        final ring = rings[r];
        if (ring.length < 3) continue;
        buildings.add(Building(
          id: rings.length == 1 ? id : '${id}_$r',
          footprint: ring,
          heightMeters: height,
        ));
      }
    }
    return buildings;
  }

  static double _readHeight(Map<String, dynamic> props) {
    for (final k in _heightKeys) {
      final v = props[k];
      if (v is num && v > 0) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return defaultHeightMeters;
  }

  /// Polygon / MultiPolygon から外周リング（LatLng列）の集合を取り出す。
  static List<List<LatLng>> _outerRings(Map<String, dynamic> geometry) {
    final type = geometry['type'];
    final coords = geometry['coordinates'] as List?;
    if (coords == null) return const [];

    List<LatLng> ringToLatLng(List ring) => [
          for (final pt in ring)
            LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()),
        ];

    switch (type) {
      case 'Polygon':
        // coordinates = [outerRing, hole1, ...] → 外周のみ。
        return [ringToLatLng(coords.first as List)];
      case 'MultiPolygon':
        // coordinates = [polygon0, polygon1, ...]、各 polygon = [outer, holes...]
        return [
          for (final poly in coords) ringToLatLng((poly as List).first as List),
        ];
      default:
        return const [];
    }
  }
}
