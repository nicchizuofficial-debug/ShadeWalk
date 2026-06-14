import '../geo/geo_utils.dart';
import 'models/covered_way.dart';
import 'package:latlong2/latlong.dart';

/// 経路が屋根付き経路（アーケード・地下道）にどれだけ沿っているかを採点する。
/// 雨天時はこのスコアが高いルートを優先する。
class CoverageScorer {
  const CoverageScorer({
    this.coveredThresholdMeters = 15.0,
    this.sampleIntervalMeters = 20.0,
  });

  /// この距離以内に屋根付き経路があれば「カバーされている」とみなす。
  final double coveredThresholdMeters;

  /// 経路を何mごとにサンプリングして判定するか。
  final double sampleIntervalMeters;

  /// 経路のカバー率 0.0〜1.0（サンプル点のうち屋根付き経路の近くにある割合）。
  double scoreRoute(List<LatLng> path, List<CoveredWay> ways) {
    if (ways.isEmpty) return 0.0;
    final pts = GeoUtils.resample(path, sampleIntervalMeters);
    if (pts.isEmpty) return 0.0;

    int covered = 0;
    for (final p in pts) {
      for (final w in ways) {
        if (GeoUtils.distanceToPolylineMeters(p, w.path) <=
            coveredThresholdMeters) {
          covered++;
          break;
        }
      }
    }
    return covered / pts.length;
  }
}
