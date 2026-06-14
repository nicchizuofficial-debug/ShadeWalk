import 'dart:convert';

import 'package:web/web.dart' as web;
import 'package:latlong2/latlong.dart';

import '../shade/models/building.dart';

/// 建物データを ブラウザの localStorage にキャッシュする。
///
/// キャッシュキー：緯度経度を小数点3桁（≈111m精度）で丸めた文字列。
/// TTL：24時間。期限切れのエントリは自動削除する。
/// 容量：1エリアあたり概算 600〜900KB。localStorage 上限 5MB のうち最大 6 エリア保存可能。
class BuildingCache {
  static const Duration _ttl = Duration(hours: 24);
  static const String _prefix = 'sw_bld_';

  static String _key(double lat, double lng) =>
      '$_prefix${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';

  /// キャッシュから建物リストを読み込む。
  /// キャッシュが存在しないか期限切れの場合は null を返す。
  List<Building>? load(double lat, double lng) {
    try {
      final raw = web.window.localStorage.getItem(_key(lat, lng));
      if (raw == null) return null;
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final ts = obj['ts'] as int;
      if (DateTime.now().millisecondsSinceEpoch - ts > _ttl.inMilliseconds) {
        web.window.localStorage.removeItem(_key(lat, lng));
        return null;
      }
      return _decode(obj['data'] as List);
    } catch (_) {
      return null;
    }
  }

  /// 建物リストをキャッシュに保存する。localStorage が満杯の場合は無視する。
  void save(double lat, double lng, List<Building> buildings) {
    try {
      web.window.localStorage.setItem(
        _key(lat, lng),
        jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'data': _encode(buildings),
        }),
      );
    } catch (_) {
      // localStorage が満杯 or セキュリティ制限の場合は保存をスキップ。
    }
  }

  static List<Map<String, dynamic>> _encode(List<Building> buildings) =>
      buildings
          .map((b) => {
                'i': b.id,
                'h': b.heightMeters,
                'p': b.footprint
                    .map((ll) => [ll.latitude, ll.longitude])
                    .toList(),
              })
          .toList();

  static List<Building> _decode(List<dynamic> data) => data
      .map((m) => Building(
            id: m['i'] as String,
            heightMeters: (m['h'] as num).toDouble(),
            footprint: (m['p'] as List)
                .map((ll) => LatLng(
                      (ll[0] as num).toDouble(),
                      (ll[1] as num).toDouble(),
                    ))
                .toList(),
          ))
      .toList();
}
