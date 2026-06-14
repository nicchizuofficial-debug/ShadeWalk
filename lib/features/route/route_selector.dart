import '../../core/geo/geo_utils.dart';
import '../../core/shade/shade_calculator.dart';
import '../../models/walk_mode.dart';
import 'models/walk_route.dart';

/// 候補ルート群を日陰スコアで評価し、モードに応じた最良ルートを選ぶ。
class RouteSelector {
  const RouteSelector({
    this.sampleIntervalMeters = 20.0,
    this.comfortTieEpsilon = 0.05,
  });

  /// 経路を何mごとにサンプリングして日陰スコアを計算するか。
  final double sampleIntervalMeters;

  /// 快適度（日陰/日向度）がこの差以内なら「ほぼ同じ」とみなし、短い方を選ぶ。
  /// この差を超える違いがあれば、モードに応じて日陰/日向を優先する。
  final double comfortTieEpsilon;

  /// 全候補に日陰スコアを付与して返す。
  List<WalkRoute> evaluate({
    required List<WalkRoute> routes,
    required ShadeField field,
  }) {
    return [
      for (final r in routes)
        r.copyWith(
          shadeScore: field.scoreRoute(
            GeoUtils.resample(r.polyline, sampleIntervalMeters),
          ),
        ),
    ];
  }

  /// モードに応じた最良ルートを選ぶ。
  /// 日陰優先なら shadeScore、日向優先なら (1 - shadeScore) を「主基準」に最大化。
  /// 快適度の差が小さい（<= comfortTieEpsilon）場合のみ、短い経路を選ぶ。
  /// これにより、意味のある日陰差があれば日陰/日向ルートがちゃんと分かれる。
  WalkRoute? selectBest({
    required List<WalkRoute> evaluatedRoutes,
    required WalkMode mode,
  }) {
    if (evaluatedRoutes.isEmpty) return null;
    double comfort(WalkRoute r) =>
        mode == WalkMode.shade ? r.shadeScore : 1.0 - r.shadeScore;

    final sorted = [...evaluatedRoutes]..sort((a, b) {
        final ca = comfort(a);
        final cb = comfort(b);
        if ((cb - ca).abs() > comfortTieEpsilon) {
          return cb.compareTo(ca); // 快適度が高い方を優先
        }
        return a.distanceMeters.compareTo(b.distanceMeters); // 同程度なら短い方
      });
    return sorted.first;
  }
}
