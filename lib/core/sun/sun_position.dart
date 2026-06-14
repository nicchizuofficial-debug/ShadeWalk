import 'package:apsl_sun_calc/apsl_sun_calc.dart';

/// 太陽の位置（高度・方位角）。apsl_sun_calc（suncalc移植）をラップする。
class SunPosition {
  const SunPosition({
    required this.altitudeRad,
    required this.azimuthRad,
  });

  /// 太陽高度 [rad]。地平線=0、天頂=π/2。負なら日没後（夜）。
  final double altitudeRad;

  /// 太陽方位角 [rad]。suncalc準拠で「南を基準・西回りが正」。
  final double azimuthRad;

  bool get isDaylight => altitudeRad > 0;

  /// 指定時刻・地点の太陽位置を計算する。
  factory SunPosition.at({
    required DateTime time,
    required double latitude,
    required double longitude,
  }) {
    // 戻り値は Map<String, num>（キー: 'altitude' / 'azimuth'）。
    final pos = SunCalc.getPosition(time, latitude, longitude);
    return SunPosition(
      altitudeRad: (pos['altitude'] ?? 0).toDouble(),
      azimuthRad: (pos['azimuth'] ?? 0).toDouble(),
    );
  }
}
