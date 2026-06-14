import 'package:latlong2/latlong.dart';

import '../geo/geo_utils.dart';
import '../sun/sun_position.dart';
import 'models/building.dart';
import 'models/shade_result.dart';
import 'models/shadow_polygon.dart';
import 'shadow_projector.dart';

/// 日陰判定のコアロジック（影ポリゴン・内包判定ベース）。
///
/// 使い方:
///   final field = ShadeCalculator().buildField(time: ..., reference: ..., buildings: ...);
///   final r = field.scoreAt(point);          // 1点の日陰スコア
///   final s = field.scoreRoute(path);        // 経路全体の平均
///
/// 時刻ごとに太陽位置と影ポリゴンを一度だけ計算し、その後は
/// 各地点を「影ポリゴンに含まれるか」で高速に判定する。
class ShadeCalculator {
  const ShadeCalculator({
    this.shadeThreshold = 0.5,
    this.projector = const ShadowProjector(),
  });

  final double shadeThreshold;
  final ShadowProjector projector;

  /// 指定時刻・対象エリアの「日陰の場（ShadeField）」を構築する。
  /// 太陽位置は都市スケールではほぼ一定なので reference 1点で代表させる。
  ShadeField buildField({
    required DateTime time,
    required LatLng reference,
    required List<Building> buildings,
  }) {
    final sun = SunPosition.at(
      time: time,
      latitude: reference.latitude,
      longitude: reference.longitude,
    );
    final shadows = projector.project(buildings: buildings, sun: sun);
    return ShadeField(
      sun: sun,
      shadows: shadows,
      shadeThreshold: shadeThreshold,
    );
  }
}

/// ある時刻・エリアにおける日陰の分布。点・経路のスコアリングを提供。
class ShadeField {
  const ShadeField({
    required this.sun,
    required this.shadows,
    required this.shadeThreshold,
  });

  final SunPosition sun;
  final List<ShadowPolygon> shadows;
  final double shadeThreshold;

  /// 指定地点の日陰スコアを算出する。
  ShadeResult scoreAt(LatLng point) {
    // 夜間は全域日陰。
    if (!sun.isDaylight) {
      return ShadeResult(
        shadeScore: 1.0,
        isShaded: true,
        sunAltitudeRad: sun.altitudeRad,
        sunAzimuthRad: sun.azimuthRad,
      );
    }

    // 点を含む影の中で最も濃い影を採用。
    // 各建物の影は複数パート（凹型対応）の和集合なので、いずれかに入れば影。
    double score = 0.0;
    for (final s in shadows) {
      if (s.intensity <= score) continue; // 既により濃い影に入っていればスキップ
      if (!s.bboxContains(point)) continue; // バウンディングbox外なら高速に除外
      for (final part in s.parts) {
        if (GeoUtils.pointInPolygon(point, part)) {
          score = s.intensity;
          break;
        }
      }
    }

    return ShadeResult(
      shadeScore: score,
      isShaded: score >= shadeThreshold,
      sunAltitudeRad: sun.altitudeRad,
      sunAzimuthRad: sun.azimuthRad,
    );
  }

  /// 経路（座標列）全体の平均日陰スコア。
  double scoreRoute(List<LatLng> path) {
    if (path.isEmpty) return 0.0;
    double total = 0.0;
    for (final p in path) {
      total += scoreAt(p).shadeScore;
    }
    return total / path.length;
  }
}
