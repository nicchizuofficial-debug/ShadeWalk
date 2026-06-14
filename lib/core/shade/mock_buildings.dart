import 'package:latlong2/latlong.dart';

import 'models/building.dart';

/// 擬似建物データ（モック）。
/// 初期段階用。将来は PLATEAU（3D都市モデル）API 等に差し替える。
/// 座標は東京駅周辺のサンプル。
class MockBuildings {
  static List<Building> tokyoStation() {
    // 1辺 ≒ 0.0004度（約40m四方）の四角い建物をいくつか配置。
    Building square(String id, double lat, double lng, double height) {
      const d = 0.0002;
      return Building(
        id: id,
        heightMeters: height,
        footprint: [
          LatLng(lat - d, lng - d),
          LatLng(lat - d, lng + d),
          LatLng(lat + d, lng + d),
          LatLng(lat + d, lng - d),
        ],
      );
    }

    return [
      square('b1', 35.6815, 139.7660, 60), // 高層ビル
      square('b2', 35.6809, 139.7672, 45),
      square('b3', 35.6822, 139.7668, 90), // タワー
      square('b4', 35.6818, 139.7650, 30),
      square('b5', 35.6805, 139.7655, 120),
    ];
  }
}
