import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// 現在地の取得と位置パーミッションを扱う。
class LocationService {
  const LocationService();

  /// 位置パーミッションを確認・要求する。利用可能なら true。
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false; // 端末の位置情報サービスが OFF
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// 現在地を1点取得する。パーミッションが無ければ null。
  Future<LatLng?> currentLatLng() async {
    if (!await ensurePermission()) return null;
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// 現在地の変化を購読する（追従表示などに使用）。
  Stream<LatLng> watchLatLng({int distanceFilterMeters = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }
}
