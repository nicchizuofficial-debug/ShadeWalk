import 'package:latlong2/latlong.dart';

/// 屋根のある経路の種類。
enum CoveredType {
  /// アーケード商店街など。
  arcade,

  /// 地下道・地下街。
  underground;

  String get label => switch (this) {
        CoveredType.arcade => 'アーケード',
        CoveredType.underground => '地下道',
      };
}

/// 雨に濡れずに歩ける経路（アーケード・地下道など）。
/// 将来は OSM の covered=*, tunnel=*, highway=footway 等から抽出する想定。
class CoveredWay {
  const CoveredWay({
    required this.id,
    required this.path,
    required this.type,
  });

  final String id;

  /// 経路の座標列。
  final List<LatLng> path;

  final CoveredType type;
}
