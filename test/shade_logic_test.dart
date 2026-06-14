import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:shade_walk/core/coverage/coverage_scorer.dart';
import 'package:shade_walk/core/coverage/mock_covered_ways.dart';
import 'package:shade_walk/core/geo/geo_utils.dart';
import 'package:shade_walk/core/shade/mock_buildings.dart';
import 'package:shade_walk/core/shade/shade_calculator.dart';
import 'package:shade_walk/features/buildings/overpass_building_repository.dart';
import 'package:shade_walk/features/route/osrm_routing_service.dart';

void main() {
  group('GeoUtils', () {
    test('offset で進んだ距離が概ね正しい', () {
      const origin = LatLng(35.681, 139.766);
      final moved = GeoUtils.offset(
        origin: origin,
        distanceMeters: 100,
        bearingFromNorthRad: 0, // 真北
      );
      final d = GeoUtils.haversineMeters(origin, moved);
      expect(d, closeTo(100, 1.0));
      expect(moved.latitude, greaterThan(origin.latitude)); // 北へ進む
    });

    test('pointInPolygon が内外を判定する', () {
      const square = [
        LatLng(0, 0),
        LatLng(0, 1),
        LatLng(1, 1),
        LatLng(1, 0),
      ];
      expect(GeoUtils.pointInPolygon(const LatLng(0.5, 0.5), square), isTrue);
      expect(GeoUtils.pointInPolygon(const LatLng(2, 2), square), isFalse);
    });

    test('resample で点が密になり端点が保持される', () {
      const path = [LatLng(35.0, 139.0), LatLng(35.0, 139.01)];
      final dense = GeoUtils.resample(path, 50);
      expect(dense.length, greaterThan(path.length));
      expect(dense.first, path.first);
      expect(dense.last, path.last);
    });

    test('GeoBounds.contains が内外を判定する', () {
      final b = GeoBounds.around(const LatLng(35.0, 139.0), 1000);
      expect(b.contains(const LatLng(35.0, 139.0)), isTrue);
      expect(b.contains(const LatLng(36.0, 140.0)), isFalse);
    });
  });

  group('ShadeField', () {
    const calc = ShadeCalculator();
    final buildings = MockBuildings.tokyoStation();
    const ref = LatLng(35.6812, 139.7660);

    test('夜間（太陽が地平線下）は全域日陰スコア1.0', () {
      // 日本の真夜中（UTC前日16時=JST翌1時）。太陽は地平線下。
      final field = calc.buildField(
        time: DateTime.utc(2026, 6, 7, 16),
        reference: ref,
        buildings: buildings,
      );
      final r = field.scoreAt(ref);
      expect(r.sunAltitudeRad, lessThan(0));
      expect(r.shadeScore, 1.0);
      expect(r.isShaded, isTrue);
    });

    test('日中は影が生成され、スコアは0..1に収まる', () {
      final field = calc.buildField(
        time: DateTime.utc(2026, 6, 7, 3), // JST正午
        reference: ref,
        buildings: buildings,
      );
      expect(field.sun.isDaylight, isTrue);
      expect(field.shadows, isNotEmpty);

      final score = field.scoreRoute(const [
        LatLng(35.6812, 139.7660),
        LatLng(35.6818, 139.7665),
      ]);
      expect(score, inInclusiveRange(0.0, 1.0));
    });

    test('ペナンブラ：本影(1.0)と半影(<1.0)の両方が生成される', () {
      final field = calc.buildField(
        time: DateTime.utc(2026, 6, 7, 3),
        reference: ref,
        buildings: buildings,
      );
      final intensities = field.shadows.map((s) => s.intensity).toSet();
      expect(intensities.any((v) => v == 1.0), isTrue); // 本影
      expect(intensities.any((v) => v < 1.0), isTrue); // 半影
    });
  });

  group('CoverageScorer', () {
    const scorer = CoverageScorer();
    final ways = MockCoveredWays.tokyoStation();

    test('アーケードに沿う経路はカバー率が高い', () {
      // arcade_1 と同じライン上を歩く経路。
      final onArcade = [
        const LatLng(35.6808, 139.7645),
        const LatLng(35.6808, 139.7675),
      ];
      expect(scorer.scoreRoute(onArcade, ways), greaterThan(0.8));
    });

    test('屋根付き経路から離れた経路はカバー率が低い', () {
      final away = [
        const LatLng(35.6760, 139.7600),
        const LatLng(35.6765, 139.7605),
      ];
      expect(scorer.scoreRoute(away, ways), lessThan(0.2));
    });
  });

  group('OverpassBuildingRepository.parse', () {
    test('building ウェイを高さ付きで変換し、閉じ点重複を除去する', () {
      const body = '''
      {"elements":[
        {"type":"way","id":1,"tags":{"building":"yes","height":"31.5"},
         "geometry":[{"lat":35.0,"lon":139.0},{"lat":35.0,"lon":139.001},
                     {"lat":35.001,"lon":139.001},{"lat":35.0,"lon":139.0}]},
        {"type":"way","id":2,"tags":{"building":"yes","building:levels":"4"},
         "geometry":[{"lat":35.0,"lon":139.0},{"lat":35.0,"lon":139.001},
                     {"lat":35.001,"lon":139.001}]},
        {"type":"way","id":3,"tags":{"building":"yes"},
         "geometry":[{"lat":35.0,"lon":139.0},{"lat":35.0,"lon":139.001},
                     {"lat":35.001,"lon":139.001}]}
      ]}''';
      final buildings = OverpassBuildingRepository.parse(body);
      expect(buildings.length, 3);
      // height タグ優先
      expect(buildings[0].heightMeters, 31.5);
      // 閉じ点（先頭と重複する末尾）が除去され4→3頂点
      expect(buildings[0].footprint.length, 3);
      // building:levels=4 → 4×3m=12m
      expect(buildings[1].heightMeters, 12.0);
      // タグ無し → 既定値8m
      expect(buildings[2].heightMeters, 8.0);
    });

    test('件数上限を尊重する', () {
      final sb = StringBuffer('{"elements":[');
      for (var i = 0; i < 10; i++) {
        if (i > 0) sb.write(',');
        sb.write('{"type":"way","id":$i,"tags":{"building":"yes"},'
            '"geometry":[{"lat":35.0,"lon":139.0},{"lat":35.0,"lon":139.001},'
            '{"lat":35.001,"lon":139.001}]}');
      }
      sb.write(']}');
      final buildings =
          OverpassBuildingRepository.parse(sb.toString(), maxBuildings: 5);
      expect(buildings.length, 5);
    });
  });

  group('OsrmRoutingService.parse', () {
    test('OSRMのGeoJSONルートをWalkRouteへ変換する', () {
      const body = '''
      {"code":"Ok","routes":[
        {"distance":1234.5,"duration":600.0,
         "geometry":{"type":"LineString",
           "coordinates":[[139.0,35.0],[139.001,35.001],[139.002,35.002]]}},
        {"distance":1500.0,"duration":700.0,
         "geometry":{"type":"LineString",
           "coordinates":[[139.0,35.0],[139.003,35.0],[139.002,35.002]]}}
      ]}''';
      final routes = OsrmRoutingService.parse(body);
      expect(routes.length, 2);
      expect(routes.first.distanceMeters, 1235); // 四捨五入
      expect(routes.first.durationSeconds, 600);
      expect(routes.first.polyline.length, 3);
      // [lng,lat] → LatLng(lat,lng) の順変換を確認
      expect(routes.first.polyline.first.latitude, 35.0);
      expect(routes.first.polyline.first.longitude, 139.0);
    });

    test('code が Ok でなければ空', () {
      expect(OsrmRoutingService.parse('{"code":"NoRoute","routes":[]}'), isEmpty);
    });
  });
}
