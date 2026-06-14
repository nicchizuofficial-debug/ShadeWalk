import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 緯度経度の矩形範囲（地図パッケージ非依存の軽量クラス）。
class GeoBounds {
  const GeoBounds({required this.southWest, required this.northEast});

  final LatLng southWest;
  final LatLng northEast;

  bool contains(LatLng p) =>
      p.latitude >= southWest.latitude &&
      p.latitude <= northEast.latitude &&
      p.longitude >= southWest.longitude &&
      p.longitude <= northEast.longitude;

  /// 中心点から半径 [meters] 四方（概算）の範囲を作る。
  factory GeoBounds.around(LatLng center, double meters) {
    final dLat = meters / 111320.0;
    final dLng = meters /
        (111320.0 * math.cos(center.latitude * math.pi / 180.0)).abs();
    return GeoBounds(
      southWest: LatLng(center.latitude - dLat, center.longitude - dLng),
      northEast: LatLng(center.latitude + dLat, center.longitude + dLng),
    );
  }

  /// 座標群を覆い、各辺に [padMeters] の余白を足した範囲を作る。
  factory GeoBounds.fromPoints(List<LatLng> points, {double padMeters = 150}) {
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLng = double.infinity, maxLng = -double.infinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final midLat = (minLat + maxLat) / 2;
    final dLat = padMeters / 111320.0;
    final dLng =
        padMeters / (111320.0 * math.cos(midLat * math.pi / 180.0)).abs();
    return GeoBounds(
      southWest: LatLng(minLat - dLat, minLng - dLng),
      northEast: LatLng(maxLat + dLat, maxLng + dLng),
    );
  }
}

/// 緯度経度ベースの幾何ユーティリティ。
/// 都市スケール（数百m）では平面近似でも十分な精度が出る。
class GeoUtils {
  GeoUtils._();

  static const double earthRadiusM = 6371000.0;

  static double deg2rad(double d) => d * math.pi / 180.0;
  static double rad2deg(double r) => r * 180.0 / math.pi;

  /// 2地点間の距離 [m]（ハバーサイン公式）。
  static double haversineMeters(LatLng a, LatLng b) {
    final dLat = deg2rad(b.latitude - a.latitude);
    final dLng = deg2rad(b.longitude - a.longitude);
    final lat1 = deg2rad(a.latitude);
    final lat2 = deg2rad(b.latitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// 起点から、指定の方位（北基準・時計回り[rad]）へ distance[m] 進んだ地点。
  static LatLng offset({
    required LatLng origin,
    required double distanceMeters,
    required double bearingFromNorthRad,
  }) {
    final angular = distanceMeters / earthRadiusM;
    final lat1 = deg2rad(origin.latitude);
    final lng1 = deg2rad(origin.longitude);
    final b = bearingFromNorthRad;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(b),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(b) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(rad2deg(lat2), rad2deg(lng2));
  }

  /// 点がポリゴン内部にあるか（レイキャスティング法）。
  static bool pointInPolygon(LatLng p, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    final x = p.longitude;
    final y = p.latitude;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// ポリライン（座標列）を指定間隔[m]で等間隔サンプリングし直す。
  /// overview polyline は頂点が疎なため、日陰スコア評価前に密にする。
  static List<LatLng> resample(List<LatLng> path, double intervalMeters) {
    if (path.length < 2) return List.of(path);
    final out = <LatLng>[path.first];
    double carry = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      final segLen = haversineMeters(a, b);
      if (segLen == 0) continue;
      double dist = intervalMeters - carry;
      while (dist < segLen) {
        final t = dist / segLen;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
        dist += intervalMeters;
      }
      carry = segLen - (dist - intervalMeters);
    }
    out.add(path.last);
    return out;
  }

  /// 点 p から線分 a-b までの最短距離 [m]（局所平面近似）。
  static double distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final latRef = deg2rad(p.latitude);
    double mx(LatLng q) => deg2rad(q.longitude) * math.cos(latRef) * earthRadiusM;
    double my(LatLng q) => deg2rad(q.latitude) * earthRadiusM;

    final px = mx(p), py = my(p);
    final ax = mx(a), ay = my(a);
    final bx = mx(b), by = my(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final ex = px - cx, ey = py - cy;
    return math.sqrt(ex * ex + ey * ey);
  }

  /// 点 p からポリライン（座標列）までの最短距離 [m]。
  static double distanceToPolylineMeters(LatLng p, List<LatLng> path) {
    if (path.isEmpty) return double.infinity;
    if (path.length == 1) return haversineMeters(p, path.first);
    double best = double.infinity;
    for (int i = 0; i < path.length - 1; i++) {
      final d = distanceToSegmentMeters(p, path[i], path[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  /// 凸包（Andrew's monotone chain）。緯度経度を平面とみなして計算する。
  static List<LatLng> convexHull(List<LatLng> points) {
    if (points.length < 3) return List.of(points);
    final pts = List.of(points)
      ..sort((a, b) => a.longitude != b.longitude
          ? a.longitude.compareTo(b.longitude)
          : a.latitude.compareTo(b.latitude));

    double cross(LatLng o, LatLng a, LatLng b) =>
        (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);

    final lower = <LatLng>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <LatLng>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }
}
