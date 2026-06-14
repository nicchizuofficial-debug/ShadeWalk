/// ある地点の日陰判定結果。
class ShadeResult {
  const ShadeResult({
    required this.shadeScore,
    required this.isShaded,
    required this.sunAltitudeRad,
    required this.sunAzimuthRad,
  });

  /// 日陰スコア 0.0〜1.0（1.0 = 完全に日陰、0.0 = 完全に日向）。
  final double shadeScore;

  /// 日陰とみなせるか（しきい値判定済み）。
  final bool isShaded;

  /// その時刻の太陽高度 [rad]（地平線下なら負）。
  final double sunAltitudeRad;

  /// その時刻の太陽方位角 [rad]（南=0, 西=+π/2 ……suncalc準拠）。
  final double sunAzimuthRad;

  /// 日向スコア（日向優先モード用）。
  double get sunScore => 1.0 - shadeScore;
}
