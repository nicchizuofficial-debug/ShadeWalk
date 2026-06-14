import 'package:latlong2/latlong.dart';

/// 建物データ。将来的には PLATEAU 等の3D都市モデルから取得する想定。
/// 現段階では擬似データ（モック）で代用する。
class Building {
  const Building({
    required this.id,
    required this.footprint,
    required this.heightMeters,
  });

  final String id;

  /// 建物の輪郭（平面ポリゴン）。緯度経度の頂点列。
  final List<LatLng> footprint;

  /// 建物の高さ [m]。
  final double heightMeters;

  /// 輪郭の重心（簡易的な代表点）。影方向の計算に使用。
  LatLng get centroid {
    double lat = 0;
    double lng = 0;
    for (final p in footprint) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / footprint.length, lng / footprint.length);
  }
}
