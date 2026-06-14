import 'package:latlong2/latlong.dart';

/// 1つの建物が地面に落とす影。
///
/// 影の正確な領域は「フットプリント」「太陽逆方向へ投影したフットプリント」
/// 「各辺を投影方向へ掃引した四辺形」の和集合になる（凹型でも正確）。
/// - [parts]   : 内包判定（スコアリング）用の単純多角形の集合。
/// - [outline] : レンダリング用の外形（凸包。凸建物では parts の和と一致）。
class ShadowPolygon {
  const ShadowPolygon({
    required this.buildingId,
    required this.parts,
    required this.outline,
    required this.intensity,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  /// outline からバウンディングボックスを計算して生成する。
  factory ShadowPolygon.fromOutline({
    required String buildingId,
    required List<List<LatLng>> parts,
    required List<LatLng> outline,
    required double intensity,
  }) {
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLng = double.infinity, maxLng = -double.infinity;
    for (final p in outline) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return ShadowPolygon(
      buildingId: buildingId,
      parts: parts,
      outline: outline,
      intensity: intensity,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  final String buildingId;

  /// 内包判定に使う単純多角形の集合（この内いずれかに入れば影）。
  final List<List<LatLng>> parts;

  /// 描画用の外形ポリゴン。
  final List<LatLng> outline;

  /// 影の濃さ 0.0〜1.0。
  final double intensity;

  /// outline のバウンディングボックス（高速な内包判定の足切り用）。
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  bool bboxContains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLng &&
      p.longitude <= maxLng;
}
