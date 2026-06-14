import 'package:latlong2/latlong.dart';

/// 1本の歩行ルート候補。
class WalkRoute {
  const WalkRoute({
    required this.id,
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.shadeScore = 0.0,
    this.coverageScore = 0.0,
  });

  final String id;

  /// 経路の座標列（デコード済み）。
  final List<LatLng> polyline;

  final int distanceMeters;
  final int durationSeconds;

  /// この経路の平均日陰スコア（0.0〜1.0）。評価後にセットされる。
  final double shadeScore;

  /// 屋根付き経路（アーケード・地下道）のカバー率（0.0〜1.0）。雨天モード用。
  final double coverageScore;

  WalkRoute copyWith({double? shadeScore, double? coverageScore}) => WalkRoute(
        id: id,
        polyline: polyline,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        shadeScore: shadeScore ?? this.shadeScore,
        coverageScore: coverageScore ?? this.coverageScore,
      );
}
