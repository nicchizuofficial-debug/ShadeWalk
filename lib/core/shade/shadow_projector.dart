import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../geo/geo_utils.dart';
import '../sun/sun_position.dart';
import 'models/building.dart';
import 'models/shadow_polygon.dart';

/// 建物の輪郭を太陽の逆方向（反太陽方向）へ投影し、地面に落ちる影を生成する。
///
/// 【本影と半影（ペナンブラ）】
/// 太陽は点光源ではなく約0.5°の視半径を持つため、影の縁はくっきりせず
/// 外側ほど薄くなる。これを近似するため、影を「本影(umbra)＋外側へ少し
/// 伸ばした半影(penumbra)」の多段tierで生成し、外側tierほど intensity を
/// 下げる。各地点は内包する最も濃いtierの値を採用する（ShadeField側）。
///
///   - 影の長さ L = 建物高さ / tan(太陽高度)
///   - 影が伸びる方位（北基準・時計回り）= suncalc方位角 φ
class ShadowProjector {
  const ShadowProjector({
    this.maxShadowLengthMeters = 400.0,
    this.penumbraFactor = 0.4,
    this.penumbraTiers = 2,
    this.penumbraMinIntensity = 0.4,
  });

  /// 太陽が低いほど影は無限に伸びるため上限を設ける。
  final double maxShadowLengthMeters;

  /// 半影を本影の何割だけ外側へ伸ばすか（0.4 = 最外周で40%長い影）。
  final double penumbraFactor;

  /// 影の段数（本影を含む）。1なら本影のみ（ペナンブラ無効）。
  final int penumbraTiers;

  /// 最外周（半影の縁）の濃さ。本影=1.0 からここまで線形に減衰。
  final double penumbraMinIntensity;

  /// 指定の太陽位置に対する全建物の影を生成する。
  /// 太陽が地平線下（夜）の場合は空リスト（＝全域日陰は ShadeField 側で扱う）。
  List<ShadowPolygon> project({
    required List<Building> buildings,
    required SunPosition sun,
  }) {
    if (!sun.isDaylight) return const [];

    final shadowBearing = _normalize2pi(sun.azimuthRad);
    final tanAlt = math.tan(sun.altitudeRad);
    if (tanAlt <= 0) return const [];

    final tiers = math.max(1, penumbraTiers);
    final result = <ShadowPolygon>[];

    for (final b in buildings) {
      if (b.footprint.length < 3) continue;
      final baseLength =
          math.min(b.heightMeters / tanAlt, maxShadowLengthMeters);

      // 外側tier（薄い・大きい）から内側tier（濃い・小さい）の順に追加。
      // 描画時に外側が下、本影が上に重なりグラデーションになる。
      for (int i = tiers - 1; i >= 0; i--) {
        final frac = tiers == 1 ? 0.0 : i / (tiers - 1);
        final length = baseLength * (1 + penumbraFactor * frac);
        final intensity = 1.0 - (1.0 - penumbraMinIntensity) * frac;
        final poly = _tier(b, length, shadowBearing, intensity);
        if (poly != null) result.add(poly);
      }
    }
    return result;
  }

  /// 1段分の影ポリゴン（指定長で投影）。
  ShadowPolygon? _tier(
    Building b,
    double length,
    double shadowBearing,
    double intensity,
  ) {
    final footprint = b.footprint;
    final projected = [
      for (final v in footprint)
        GeoUtils.offset(
          origin: v,
          distanceMeters: length,
          bearingFromNorthRad: shadowBearing,
        ),
    ];

    // パート集合: フットプリント + 投影フットプリント + 各辺の掃引四辺形（凹型対応）。
    final parts = <List<LatLng>>[
      footprint,
      projected,
      for (int i = 0; i < footprint.length; i++)
        [
          footprint[i],
          footprint[(i + 1) % footprint.length],
          projected[(i + 1) % footprint.length],
          projected[i],
        ],
    ];

    final outline = GeoUtils.convexHull([...footprint, ...projected]);
    if (outline.length < 3) return null;

    return ShadowPolygon.fromOutline(
      buildingId: b.id,
      parts: parts,
      outline: outline,
      intensity: intensity,
    );
  }

  double _normalize2pi(double rad) {
    var r = rad % (2 * math.pi);
    if (r < 0) r += 2 * math.pi;
    return r;
  }
}
