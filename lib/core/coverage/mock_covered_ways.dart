import 'package:latlong2/latlong.dart';

import 'models/covered_way.dart';

/// 擬似的な屋根付き経路データ（モック）。東京駅周辺のサンプル。
/// 将来は OSM（covered/tunnel タグ）や自治体データに差し替える。
class MockCoveredWays {
  static List<CoveredWay> tokyoStation() {
    return const [
      // アーケード商店街（東西に伸びる）
      CoveredWay(
        id: 'arcade_1',
        type: CoveredType.arcade,
        path: [
          LatLng(35.6808, 139.7640),
          LatLng(35.6808, 139.7660),
          LatLng(35.6808, 139.7680),
        ],
      ),
      // 地下道（南北に伸びる）
      CoveredWay(
        id: 'under_1',
        type: CoveredType.underground,
        path: [
          LatLng(35.6795, 139.7665),
          LatLng(35.6812, 139.7665),
          LatLng(35.6828, 139.7665),
        ],
      ),
    ];
  }
}
