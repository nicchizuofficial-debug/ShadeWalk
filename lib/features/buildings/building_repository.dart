import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/geo/geo_utils.dart';
import '../../core/geo/geojson_parser.dart';
import '../../core/shade/mock_buildings.dart';
import '../../core/shade/models/building.dart';

/// 建物データの取得源を抽象化する。
/// 影計算は Building（輪郭＋高さ）にのみ依存するので、
/// データ源（モック / バンドルGeoJSON / PLATEAU API）を差し替えられる。
abstract class BuildingRepository {
  const BuildingRepository();

  /// 指定範囲（矩形）の建物を取得する。範囲フィルタは実装側の最善努力で行う。
  Future<List<Building>> fetchBuildings(GeoBounds bounds);

  /// 中心から半径 [radiusMeters] の「円内」の建物を取得する（徒歩圏など）。
  /// 既定は外接矩形で取得 → 円内に絞り込み。Overpass は around で真円取得に上書き。
  Future<List<Building>> fetchAround(LatLng center, double radiusMeters) async {
    final all = await fetchBuildings(GeoBounds.around(center, radiusMeters));
    return [
      for (final b in all)
        if (GeoUtils.haversineMeters(center, b.centroid) <= radiusMeters) b,
    ];
  }
}

/// 擬似建物（開発・オフライン用）。
class MockBuildingRepository extends BuildingRepository {
  const MockBuildingRepository();

  @override
  Future<List<Building>> fetchBuildings(GeoBounds bounds) async {
    return MockBuildings.tokyoStation();
  }
}

/// バンドルした GeoJSON アセットから読み込む。
/// PLATEAU の CityGML を前処理した GeoJSON を assets/ に同梱する想定。
class AssetBuildingRepository extends BuildingRepository {
  const AssetBuildingRepository(this.assetPath);

  final String assetPath;

  @override
  Future<List<Building>> fetchBuildings(GeoBounds bounds) async {
    final raw = await rootBundle.loadString(assetPath);
    final all = GeoJsonParser.parse(raw);
    return _withinBounds(all, bounds);
  }
}

/// PLATEAU 由来の GeoJSON を配信するエンドポイントから取得する。
/// 例: 自前で CityGML→GeoJSON 変換した建物タイルを返す API。
class PlateauBuildingRepository extends BuildingRepository {
  PlateauBuildingRepository({
    required this.endpoint,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// {minLng},{minLat},{maxLng},{maxLat} を bbox クエリで受ける想定。
  final Uri endpoint;
  final http.Client _client;

  @override
  Future<List<Building>> fetchBuildings(GeoBounds bounds) async {
    final uri = endpoint.replace(queryParameters: {
      ...endpoint.queryParameters,
      'bbox': '${bounds.southWest.longitude},${bounds.southWest.latitude},'
          '${bounds.northEast.longitude},${bounds.northEast.latitude}',
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('PLATEAU fetch failed: HTTP ${res.statusCode}');
    }
    final all = GeoJsonParser.parse(res.body);
    return _withinBounds(all, bounds);
  }

  void dispose() => _client.close();
}

/// 建物の重心が範囲内にあるものだけ残す（軽量フィルタ）。
List<Building> _withinBounds(List<Building> buildings, GeoBounds bounds) {
  return [
    for (final b in buildings)
      if (bounds.contains(b.centroid)) b,
  ];
}
