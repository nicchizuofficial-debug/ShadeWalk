import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/cache/building_cache.dart';
import '../../core/constants/app_config.dart';
import '../../core/coverage/coverage_scorer.dart';
import '../../core/coverage/mock_covered_ways.dart';
import '../../core/coverage/models/covered_way.dart';
import '../../core/coverage/overpass_covered_way_repository.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/location/location_service.dart';
import '../../core/shade/mock_buildings.dart';
import '../../core/shade/models/building.dart';
import '../../core/shade/models/shade_result.dart';
import '../../core/shade/shade_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/walk_mode.dart';
import '../../monetization/ads/banner_ad_widget.dart';
import '../../monetization/iap/purchase_service.dart';
import '../buildings/building_repository.dart';
import '../buildings/overpass_building_repository.dart';
import '../paywall/paywall_sheet.dart';
import '../route/models/walk_route.dart';
import '../route/osrm_routing_service.dart';
import '../route/route_selector.dart';
import '../route/routing_service.dart';
import 'widgets/mode_toggle.dart';

/// 地図表示画面（OpenStreetMap タイル + flutter_map）。
/// 建物・影ポリゴン・日陰判定の可視化、モード切替、日陰ルート検索を行う。
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _initialCenter = LatLng(35.6812, 139.7660); // 東京駅周辺
  static const double _initialZoom = 16;

  // 地図タイルのトーン補正（彩度を少し下げ、わずかに暖色＝アイボリー寄り）。
  static const List<double> _tileTone = [
    0.92126, 0.07152, 0.00722, 0, 6, //
    0.02126, 0.97152, 0.00722, 0, 3, //
    0.02126, 0.07152, 0.90722, 0, -4, //
    0, 0, 0, 1, 0, //
  ];

  final _calculator = const ShadeCalculator();
  // ORSキーがあれば歩行に正確なORS、無ければキー不要のOSRM（車）でルート検索。
  final RoutingService _routing = AppConfig.orsApiKey.isNotEmpty
      ? OrsRoutingService()
      : OsrmRoutingService();
  final _selector = const RouteSelector();
  final _coverage = const CoverageScorer();
  final _location = const LocationService();
  final _mapController = MapController();

  // 屋根付き経路（アーケード・地下道）。Overpass から実データを取得。
  final _coveredWayRepo = OverpassCoveredWayRepository();
  List<CoveredWay> _coveredWays = MockCoveredWays.tokyoStation();

  /// 雨天モード（プレミアム機能）。ONで屋根付き経路を優先する。
  bool _rainMode = false;

  // 出発地。既定は東京駅、現在地が取れたら上書きする。
  LatLng _origin = _initialCenter;
  LatLng? _currentLocation;

  // 建物を取得した「徒歩圏の円」（地図に表示）。
  LatLng _coverageCenter = _initialCenter;
  double _coverageRadius = _buildingRadiusMeters;

  // 建物データ源。既定は OSM(Overpass) の実建物をライブ取得。
  // PLATEAU 公式データを使う場合は AssetBuildingRepository('assets/...') に差し替える。
  final BuildingRepository _buildingRepo = OverpassBuildingRepository();
  final _buildingCache = BuildingCache();
  static const double _buildingRadiusMeters = 1200; // 取得範囲（徒歩圏）
  List<Building> _buildings = const [];
  bool _loadingBuildings = false;

  WalkMode _mode = WalkMode.shade;
  DateTime _time = DateTime.now();

  bool _showBuildings = true;  // 建物表示フラグ
  bool _showHeatmap = true;    // ヒートマップ表示フラグ

  List<Polygon> _polygons = []; // ヒートマップタイル＋影＋建物をまとめて管理
  List<Polyline> _routeLines = [];
  List<Marker> _markers = [];
  ShadeField? _field;
  ShadeResult? _centerResult;

  // ルート検索状態
  LatLng? _destination;
  List<WalkRoute> _routes = [];
  WalkRoute? _bestRoute;
  double _shadeMin = 0;
  double _shadeMax = 0;
  bool _searching = false;
  bool _geocoding = false;
  String? _error;

  final _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _destController.dispose();
    _mapController.dispose();
    _routing.dispose();
    _coveredWayRepo.dispose();
    final repo = _buildingRepo;
    if (repo is OverpassBuildingRepository) {
      repo.dispose();
    }
    super.dispose();
  }

  /// 地図のズームを delta だけ変える（+1 / -1）。
  void _zoomBy(double delta) {
    final cam = _mapController.camera;
    final z = (cam.zoom + delta).clamp(3.0, 19.0);
    _mapController.move(cam.center, z);
  }

  /// 起動時：現在地を出発地に設定 → 建物・屋根付き経路読込 → 影計算。
  Future<void> _bootstrap() async {
    await _useCurrentLocation(animate: false);
    await Future.wait([
      _loadBuildings(),
      _loadCoveredWays(_origin, _buildingRadiusMeters),
    ]);
    _animateTo(_origin);
  }

  /// 現在地周辺の屋根付き経路を Overpass から取得する。
  Future<void> _loadCoveredWays(LatLng center, double radius) async {
    try {
      final ways = await _coveredWayRepo.fetchAround(center, radius);
      if (mounted) setState(() => _coveredWays = ways);
    } catch (_) {
      // 失敗時はモックのまま
    }
  }

  /// 現在地を取得して出発地に設定する。取得できなければ既定地のまま。
  Future<void> _useCurrentLocation({bool animate = true}) async {
    try {
      final here = await _location.currentLatLng();
      if (here != null && mounted) {
        _origin = here;
        _currentLocation = here;
        if (animate) _animateTo(here);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '現在地取得失敗: $e');
    }
  }

  void _animateTo(LatLng target) {
    try {
      _mapController.move(target, _initialZoom);
    } catch (_) {
      // マップ未初期化時は無視（onMapReady で再センタリングされる）。
    }
  }

  /// 出発地周辺の建物を取得する。
  ///
  /// 処理の流れ:
  ///   1. localStorage キャッシュを確認 → ヒットすれば即時表示して終了
  ///   2. [_buildingRadiusMeters] m 円を NE/NW/SE/SW の4象限に分割して並列フェッチ
  ///   3. 結果をマージ（重複 ID を排除）してキャッシュ保存
  Future<void> _loadBuildings() async {
    // coverage 円を設定（表示クリップ用）
    _coverageCenter = _origin;
    _coverageRadius = _buildingRadiusMeters;

    // ① キャッシュ確認 ─ ヒットすれば即時表示して終了
    final cached = _buildingCache.load(
        _origin.latitude, _origin.longitude);
    if (cached != null && cached.isNotEmpty) {
      _buildings = cached;
      _rebuild();
      return;
    }

    // ② 4象限並列フェッチ
    if (!_searching && mounted) setState(() => _loadingBuildings = true);
    try {
      final merged = await _fetchBuildingsTiled(_origin);
      if (!mounted) return;
      if (merged.isNotEmpty) {
        _buildings = merged;
        // ③ キャッシュ保存（次回起動時に即時表示）
        _buildingCache.save(_origin.latitude, _origin.longitude, merged);
      } else if (_buildings.isEmpty) {
        _buildings = MockBuildings.tokyoStation();
      }
    } catch (_) {
      if (!mounted) return;
      if (_buildings.isEmpty) _buildings = MockBuildings.tokyoStation();
    } finally {
      if (mounted) setState(() => _loadingBuildings = false);
    }
    _rebuild();
  }

  /// [_buildingRadiusMeters] m 円を NE/NW/SE/SW の4象限に分割し、
  /// 各象限を並列で Overpass から取得して重複なしに結合する。
  Future<List<Building>> _fetchBuildingsTiled(LatLng center) async {
    final r = _buildingRadiusMeters;
    final north = GeoUtils.offset(
        origin: center, distanceMeters: r, bearingFromNorthRad: 0);
    final east = GeoUtils.offset(
        origin: center, distanceMeters: r, bearingFromNorthRad: math.pi / 2);
    final south = GeoUtils.offset(
        origin: center, distanceMeters: r, bearingFromNorthRad: math.pi);
    final west = GeoUtils.offset(
        origin: center, distanceMeters: r, bearingFromNorthRad: -math.pi / 2);

    final tiles = [
      GeoBounds(southWest: center,
          northEast: LatLng(north.latitude, east.longitude)),  // NE
      GeoBounds(southWest: LatLng(center.latitude, west.longitude),
          northEast: LatLng(north.latitude, center.longitude)), // NW
      GeoBounds(southWest: LatLng(south.latitude, center.longitude),
          northEast: LatLng(center.latitude, east.longitude)),  // SE
      GeoBounds(southWest: LatLng(south.latitude, west.longitude),
          northEast: center),                                   // SW
    ];

    final results = await Future.wait(
      tiles.map((bbox) =>
          _buildingRepo.fetchBuildings(bbox).catchError((_) => <Building>[])),
    );

    // 重複排除（タイル境界の建物が重複する場合がある）
    final seen = <String>{};
    final merged = <Building>[];
    for (final list in results) {
      for (final b in list) {
        if (seen.add(b.id)) merged.add(b);
      }
    }
    return merged;
  }



  /// テキスト入力から目的地をジオコード（Nominatim）して地図を更新する。
  Future<void> _geocodeAndSetDest() async {
    final query = _destController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _geocoding = true; _error = null; });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
        'accept-language': 'ja',
      });
      final res = await http.get(uri,
          headers: {'User-Agent': 'ShadeWalk/1.0 (demo)'});
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception('検索失敗 (HTTP ${res.statusCode})');
      final list = json.decode(res.body) as List;
      if (list.isEmpty) throw Exception('"$query" が見つかりませんでした');
      final item = list[0] as Map;
      final lat = double.parse(item['lat'] as String);
      final lng = double.parse(item['lon'] as String);
      final dest = LatLng(lat, lng);
      _animateTo(dest);
      await _onMapLongPress(dest);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  /// 現在地ボタン：現在地へ移動し、建物・影を再計算。
  Future<void> _onRecenter() async {
    await _useCurrentLocation();
    await _loadBuildings();
  }

  /// 「このエリアで再取得」：今表示している地図の中心を出発地にして
  /// その周辺の建物・影を読み込み直す（仙台など任意の場所を見るとき用）。
  Future<void> _onSearchThisArea() async {
    _origin = _mapController.camera.center;
    _currentLocation = null;
    await Future.wait([
      _loadBuildings(),
      _loadCoveredWays(_origin, _buildingRadiusMeters),
    ]);
  }

  /// 影ポリゴンを再計算し、図形を組み立て直す。ルート評価も最新の場で更新。
  void _rebuild() {
    final field = _calculator.buildField(
      time: _time,
      reference: _origin,
      buildings: _buildings,
    );

    final polygons = <Polygon>[];

    // 影ポリゴン（先に描いて建物の下に）。
    // 半影tierほど intensity が低く、塗りの濃さもそれに比例してグラデーションになる。
    final maxAlpha = _mode == WalkMode.shade ? 0.32 : 0.14;
    for (final s in field.shadows) {
      polygons.add(Polygon(
        points: s.outline,
        color: AppColors.shadow.withValues(alpha: maxAlpha * s.intensity),
        borderStrokeWidth: 0,
      ));
    }

    // 建物輪郭（表示フラグONのときのみ）。coverage 円内の建物のみ表示。
    if (_showBuildings) {
      for (final b in _buildings) {
        final cx = b.footprint.map((p) => p.latitude).reduce((a, v) => a + v)
            / b.footprint.length;
        final cy = b.footprint.map((p) => p.longitude).reduce((a, v) => a + v)
            / b.footprint.length;
        if (GeoUtils.haversineMeters(_coverageCenter, LatLng(cx, cy))
            > _coverageRadius) continue;
        polygons.add(Polygon(
          points: b.footprint,
          color: AppColors.building.withValues(alpha: 0.45),
          borderColor: AppColors.building,
          borderStrokeWidth: 0.8,
        ));
      }
    }

    // 日陰/日向ヒートマップ：隙間なく並ぶ正方形タイルで色分け表示。
    // 影ポリゴン・建物より下に描くため polygons の先頭に挿入する。
    if (_showHeatmap) {
      final covHeat = _coverageRadius.clamp(300.0, 1000.0);
      final stepM = (covHeat / 22).clamp(25.0, 70.0); // タイル1辺[m]
      final latStep = stepM / 111320.0;
      final lngStep = stepM /
          (111320.0 * math.cos(_coverageCenter.latitude * math.pi / 180)).abs();
      final halfLat = latStep / 2;
      final halfLng = lngStep / 2;
      final span = (covHeat / stepM).ceil();
      final tiles = <Polygon>[];
      for (int i = -span; i <= span; i++) {
        for (int j = -span; j <= span; j++) {
          final p = LatLng(
            _coverageCenter.latitude + i * latStep,
            _coverageCenter.longitude + j * lngStep,
          );
          if (GeoUtils.haversineMeters(_coverageCenter, p) > covHeat) continue;
          final r = field.scoreAt(p);
          final score = _mode == WalkMode.shade ? r.shadeScore : r.sunScore;
          if (score <= 0.03) continue;
          tiles.add(Polygon(
            points: [
              LatLng(p.latitude - halfLat, p.longitude - halfLng),
              LatLng(p.latitude - halfLat, p.longitude + halfLng),
              LatLng(p.latitude + halfLat, p.longitude + halfLng),
              LatLng(p.latitude + halfLat, p.longitude - halfLng),
            ],
            color: _scoreColor(score),
            borderStrokeWidth: 0,
          ));
        }
      }
      // 最背面に挿入（影・建物の下）
      polygons.insertAll(0, tiles);
    }

    _field = field;
    _polygons = polygons;
    _centerResult = field.scoreAt(_origin);

    if (_routes.isNotEmpty) {
      _reevaluateRoutes();
    } else {
      _routeLines = _coveredWayLines(); // ルート未検索でも屋根付き経路は表示
      _rebuildMarkers();
      setState(() {});
    }
  }

  /// 雨天モードの切替（プレミアム機能）。
  void _onToggleRain() {
    final isPremium = context.read<PurchaseService>().isPremium;
    if (!isPremium) {
      showPaywall(context);
      return;
    }
    _rainMode = !_rainMode;
    if (_routes.isNotEmpty) {
      _reevaluateRoutes();
    } else {
      _routeLines = _coveredWayLines();
      setState(() {});
    }
  }

  // ヒートマップ配色：薄い色→濃い色へ色相と濃度を補間。
  static const Color _heatShadeLo = Color(0xFFC3B4D2); // 淡いラベンダー
  static const Color _heatSunLo = Color(0xFFEAD3A8); // 淡いゴールド

  Color _scoreColor(double score) {
    final t = score.clamp(0.0, 1.0);
    final c = _mode == WalkMode.shade
        ? Color.lerp(_heatShadeLo, AppColors.shadow, t)!
        : Color.lerp(_heatSunLo, AppColors.gold, t)!;
    return c.withValues(alpha: 0.10 + 0.40 * t);
  }

  void _onHourChanged(double hour) {
    // 未来時間の検索はプレミアム機能。未購入かつ「今日」なら現在時刻より先をロック。
    final isPremium = context.read<PurchaseService>().isPremium;
    if (!isPremium && _isToday(_time) && hour.round() > DateTime.now().hour) {
      showPaywall(context);
      return;
    }
    final d = _time;
    _time = DateTime(d.year, d.month, d.day, hour.round());
    _rebuild();
  }

  bool _isToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  String _dateLabel(DateTime t) =>
      _isToday(t) ? '今日' : '${t.month}/${t.day}';

  /// 日付選択。未来日付はプレミアム機能。
  Future<void> _pickDate() async {
    final isPremium = context.read<PurchaseService>().isPremium;
    if (!isPremium) {
      showPaywall(context);
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _time.isBefore(today) ? today : _time,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
      helpText: '日陰ルートを見る日付',
    );
    if (picked == null || !mounted) return;
    _time = DateTime(picked.year, picked.month, picked.day, _time.hour);
    _rebuild();
  }

  /// 地図長押しで目的地を設定し、ルート検索を実行。
  Future<void> _onMapLongPress(LatLng dest) async {
    setState(() {
      _destination = dest;
      _searching = true;
      _error = null;
    });
    try {
      final routes = await _routing.fetchWalkingRoutes(
        origin: _origin,
        destination: dest,
      );
      _routes = routes;

      // 建物データは coverage 円内のものをそのまま使用（円外に広げない）。
      // 円内の既存データで影計算・ルート評価を行う。
      _reevaluateRoutes();

      // 日陰/日向バイアスのかかった追加ルートを取得して選択肢を増やす。
      final extra = await _fetchBiasedRoutes(dest);
      if (extra.isNotEmpty) {
        _routes = [..._routes, ...extra];
        _reevaluateRoutes();
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// 日陰/日向バイアスのかかった追加ルートを取得する。
  ///
  /// 【垂直方向オフセット法・1点経由】
  /// 出発地→目的地の中間点を基準に垂直方向をスキャンし、
  /// 最も日陰スコアが高い1点・低い1点をそれぞれ経由するルートを生成する。
  ///
  /// ※ 複数waypoint同時指定は「全点を順番に通る」ルートになりOSRMが
  ///    大回りを強いられて距離フィルタで除外されるため、必ず1点のみ使用する。
  Future<List<WalkRoute>> _fetchBiasedRoutes(LatLng dest) async {
    final router = _routing;
    if (router is! OsrmRoutingService) return const [];
    final field = _field;
    if (field == null) return const [];

    final directDist = GeoUtils.haversineMeters(_origin, dest);
    // オフセット量：直線距離の 25%（最小 80m, 最大 400m）
    // ※ 大きすぎると建物データ範囲外に出て scoreAt が 0 になり
    //   「建物なし＝日向」と誤判定するため小さめに抑える。
    final offsetM = (directDist * 0.25).clamp(80.0, 400.0);

    final bearing = _bearingRad(_origin, dest);
    final perpL = bearing - math.pi / 2;
    final perpR = bearing + math.pi / 2;

    // 直線の中点を基準に垂直左右 × 4段階 = 計8点をスキャン
    final midPt = LatLng(
      (_origin.latitude  + dest.latitude)  / 2,
      (_origin.longitude + dest.longitude) / 2,
    );

    // 建物データが読み込まれている範囲（coverageCenter ± coverageRadius）内か確認。
    // 範囲外の点は scoreAt が 0（建物なし）を返し "日向" と誤判定するため除外する。
    bool withinCoverage(LatLng p) {
      final d = GeoUtils.haversineMeters(_coverageCenter, p);
      return d <= _coverageRadius * 0.9; // 10% マージンを持って範囲内に限定
    }

    LatLng? bestShadeWp, bestSunWp;
    double bestShade = -1, bestSun = 2;

    for (final side in [perpL, perpR]) {
      for (final mult in [0.3, 0.6, 1.0, 1.4]) {
        final p = GeoUtils.offset(
          origin: midPt,
          distanceMeters: offsetM * mult,
          bearingFromNorthRad: side,
        );
        // 建物データ範囲外はスキップ（誤った日向/日陰判定を防ぐ）
        if (!withinCoverage(p)) continue;
        final score = field.scoreAt(p).shadeScore;
        if (score > bestShade) { bestShade = score; bestShadeWp = p; }
        if (score < bestSun)   { bestSun   = score; bestSunWp   = p; }
      }
    }

    // 有効なwaypoint候補がない、または同一点なら差別化できないのでスキップ
    if (bestShadeWp == null || bestSunWp == null) return const [];
    if (bestShadeWp == bestSunWp) return const [];

    final result    = <WalkRoute>[];
    final baseDistM = _routes.isNotEmpty
        ? _routes.map((r) => r.distanceMeters).reduce(math.min)
        : 99999;

    // 日陰バイアスルート（shadiest点を1点経由）
    final shadeRoutes = await router.fetchWithWaypoints(
      origin: _origin, waypoints: [bestShadeWp], destination: dest,
      idPrefix: 'shade_via',
    );
    result.addAll(shadeRoutes.where((w) => w.distanceMeters <= baseDistM * 3.0));

    // 日向バイアスルート（sunniest点を1点経由）
    final sunRoutes = await router.fetchWithWaypoints(
      origin: _origin, waypoints: [bestSunWp], destination: dest,
      idPrefix: 'sun_via',
    );
    result.addAll(sunRoutes.where((w) => w.distanceMeters <= baseDistM * 3.0));

    return result;
  }

  /// 2地点間の方位角 [rad]（北基準・時計回り）。
  double _bearingRad(LatLng from, LatLng to) {
    final dLng = GeoUtils.deg2rad(to.longitude - from.longitude);
    final lat1 = GeoUtils.deg2rad(from.latitude);
    final lat2 = GeoUtils.deg2rad(to.latitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return math.atan2(y, x);
  }

  /// 現在の場・モードでルートを評価し直し、最良を強調表示する。
  void _reevaluateRoutes() {
    final field = _field;
    if (field == null || _routes.isEmpty) return;

    // 日陰スコアと屋根付きカバー率の両方を付与。
    var evaluated = _selector.evaluate(routes: _routes, field: field);
    evaluated = [
      for (final r in evaluated)
        r.copyWith(
          coverageScore: _coverage.scoreRoute(r.polyline, _coveredWays),
        ),
    ];

    // 雨天モードならカバー率最優先、通常は日陰/日向スコアで選択。
    final WalkRoute? best = _rainMode
        ? _selectBestByCoverage(evaluated)
        : _selector.selectBest(evaluatedRoutes: evaluated, mode: _mode);
    _routes = evaluated;
    _bestRoute = best;

    // 候補間の日陰スコアの幅（小さいほど日陰/日向で同じ経路になりやすい）。
    final scores = evaluated.map((r) => r.shadeScore);
    _shadeMin = scores.reduce(math.min);
    _shadeMax = scores.reduce(math.max);

    final bestColor = _rainMode
        ? AppColors.rain
        : (_mode == WalkMode.shade ? AppColors.plum : AppColors.gold);

    // 描画順（下→上）:
    //   候補ルート白縁 → 候補ルート色 → ベストルート白縁 → ベストルート色
    //   → 屋根付き経路白縁 → 屋根付き経路色
    // 屋根付き経路を最前面にすることで常に視認できる。
    final others = evaluated.where((r) => r.id != best?.id).toList();
    final lines = <Polyline>[
      // 候補ルート：白縁
      for (final r in others)
        Polyline(
          points: r.polyline,
          strokeWidth: 5.5,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      // 候補ルート：色
      for (final r in others)
        Polyline(
          points: r.polyline,
          strokeWidth: 3.5,
          color: AppColors.mist.withValues(alpha: 0.65),
        ),
      // ベストルート：白縁（太め）
      if (best != null)
        Polyline(
          points: best.polyline,
          strokeWidth: 10,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      // ベストルート：色（前面）
      if (best != null)
        Polyline(
          points: best.polyline,
          strokeWidth: 6,
          color: bestColor,
        ),
      // 屋根付き経路（最前面・常に視認できるよう最後に描画）
      ..._coveredWayLines(),
    ];

    _routeLines = lines;
    _rebuildMarkers();
    setState(() {});
  }

  /// カバー率最大（同率なら短い方）のルートを選ぶ。
  WalkRoute? _selectBestByCoverage(List<WalkRoute> routes) {
    WalkRoute? best;
    double bestValue = double.negativeInfinity;
    for (final r in routes) {
      final value = r.coverageScore - r.distanceMeters / 100000.0;
      if (value > bestValue) {
        bestValue = value;
        best = r;
      }
    }
    return best;
  }

  /// 屋根付き経路の描画用ライン（アーケード=橙, 地下道=茶）。
  List<Polyline> _coveredWayLines() {
    final result = <Polyline>[];
    for (final w in _coveredWays) {
      final baseColor = w.type == CoveredType.arcade
          ? AppColors.arcade
          : AppColors.underground;
      final strokeW = _rainMode ? 7.0 : 4.5;
      final alpha   = _rainMode ? 1.0  : 0.85;
      // 白縁取りで地図タイルから浮き上がらせる
      result.add(Polyline(
        points: w.path,
        strokeWidth: strokeW + 3,
        color: Colors.white.withValues(alpha: alpha * 0.9),
      ));
      result.add(Polyline(
        points: w.path,
        strokeWidth: strokeW,
        color: baseColor.withValues(alpha: alpha),
      ));
    }
    return result;
  }

  void _rebuildMarkers() {
    final markers = <Marker>[
      Marker(
        point: _origin,
        width: 40,
        height: 40,
        child: const Icon(Icons.trip_origin, color: AppColors.rose, size: 26),
      ),
      if (_destination != null)
        Marker(
          point: _destination!,
          width: 40,
          height: 40,
          child: const Icon(Icons.place, color: AppColors.plum, size: 34),
        ),
      if (_currentLocation != null)
        Marker(
          point: _currentLocation!,
          width: 24,
          height: 24,
          child: const Icon(Icons.my_location, color: AppColors.rain, size: 20),
        ),
    ];
    _markers = markers;
  }

  @override
  Widget build(BuildContext context) {
    final r = _centerResult;
    final best = _bestRoute;
    final isPremium = context.watch<PurchaseService>().isPremium;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              onMapReady: () => _animateTo(_origin),
              onLongPress: (_, point) => _onMapLongPress(point),
            ),
            children: [
              TileLayer(
                // CARTO Positron：余白の効いた淡色ミニマル基調（上品）。
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.shadewalk',
                // テーマに合わせて気持ち暖色・低彩度に整える。
                tileBuilder: (context, tileWidget, tile) => ColorFiltered(
                  colorFilter: const ColorFilter.matrix(_tileTone),
                  child: tileWidget,
                ),
              ),
              // 徒歩圏の円（建物を取得している範囲）
              CircleLayer(circles: [
                CircleMarker(
                  point: _coverageCenter,
                  radius: _coverageRadius,
                  useRadiusInMeter: true,
                  color: AppColors.plum.withValues(alpha: 0.04),
                  borderColor: AppColors.plum.withValues(alpha: 0.35),
                  borderStrokeWidth: 1.5,
                ),
              ]),
              PolygonLayer(polygons: _polygons),
              PolylineLayer(polylines: _routeLines),
              MarkerLayer(markers: _markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('© CARTO'),
                ],
              ),
            ],
          ),

          // 右側：現在地・拡大・縮小・表示切替・再取得ボタン
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ZoomButton(
                    icon: Icons.my_location,
                    tooltip: '現在地へ',
                    onTap: _onRecenter,
                  ),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    icon: Icons.add,
                    tooltip: '拡大',
                    onTap: () => _zoomBy(1),
                  ),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    icon: Icons.remove,
                    tooltip: '縮小',
                    onTap: () => _zoomBy(-1),
                  ),
                  const SizedBox(height: 16),
                  // 建物表示トグル
                  _ZoomButton(
                    icon: _showBuildings ? Icons.domain : Icons.domain_disabled,
                    tooltip: _showBuildings ? '建物を非表示' : '建物を表示',
                    color: _showBuildings ? AppColors.plum : Colors.black38,
                    onTap: () => setState(() {
                      _showBuildings = !_showBuildings;
                      _rebuild();
                    }),
                  ),
                  const SizedBox(height: 8),
                  // ヒートマップ表示トグル
                  _ZoomButton(
                    icon: _showHeatmap ? Icons.blur_on : Icons.blur_off,
                    tooltip: _showHeatmap
                        ? 'ヒートマップを非表示\n（日陰/日向スコアの分布）'
                        : 'ヒートマップを表示\n（日陰/日向スコアの分布）',
                    color: _showHeatmap ? AppColors.plum : Colors.black38,
                    onTap: () => setState(() {
                      _showHeatmap = !_showHeatmap;
                      _rebuild();
                    }),
                  ),
                  const SizedBox(height: 16),
                  _ZoomButton(
                    icon: Icons.refresh,
                    tooltip: 'この表示エリアの建物を取得',
                    onTap: _onSearchThisArea,
                  ),
                ],
              ),
            ),
          ),

          // 建物データ読み込み中の表示（ルート検索中は非表示：二重スピナー防止）
          if (_loadingBuildings && !_searching)
            const Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('建物データを取得中…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 上部：ブランドタイトル ＋ モード切替トグル
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const _BrandTitle(),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ModeToggle(
                        mode: _mode,
                        onChanged: (m) {
                          _mode = m;
                          _rebuild();
                        },
                      ),
                      const SizedBox(width: 8),
                      // 雨天モード（屋根付き経路優先・プレミアム）
                      Material(
                        elevation: 2,
                        shape: const CircleBorder(),
                        color: _rainMode ? AppColors.rain : Colors.white,
                        shadowColor: AppColors.plum.withValues(alpha: 0.25),
                        child: IconButton(
                          tooltip: '雨天モード（アーケード・地下道優先）',
                          icon: Icon(
                            Icons.umbrella_outlined,
                            color: _rainMode ? Colors.white : AppColors.mist,
                          ),
                          onPressed: _onToggleRain,
                        ),
                      ),
                    ],
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('ルート検索中…'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('エラー: $_error',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 下部：情報パネル（すりガラス）
          // キーボードが表示されたときも bottom margin でパネルを押し上げる。
          Builder(builder: (ctx) {
            final keyboardInset = MediaQuery.of(ctx).viewInsets.bottom;
            return Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: EdgeInsets.fromLTRB(12, 12, 12, 12 + keyboardInset),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.plum.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: _Frosted(
                  radius: 26,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShadeLegend(mode: _mode, rainMode: _rainMode),
                      const SizedBox(height: 10),
                      // 目的地入力フィールド
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: _destController,
                                decoration: InputDecoration(
                                  hintText: '目的地を入力（例：東京タワー）',
                                  hintStyle: const TextStyle(
                                      fontSize: 13, color: AppColors.mist),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 0),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                        color: AppColors.plum.withValues(alpha: 0.3)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                        color: AppColors.plum.withValues(alpha: 0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(
                                        color: AppColors.plum, width: 1.5),
                                  ),
                                  suffixIcon: _destController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear,
                                              size: 16, color: AppColors.mist),
                                          onPressed: () => setState(
                                              () => _destController.clear()),
                                        )
                                      : null,
                                ),
                                style: const TextStyle(fontSize: 13),
                                textInputAction: TextInputAction.search,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _geocodeAndSetDest(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: _geocoding
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Material(
                                    elevation: 2,
                                    shape: const CircleBorder(),
                                    color: AppColors.plum,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _geocodeAndSetDest,
                                      child: const Icon(Icons.search,
                                          color: Colors.white, size: 20),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (best != null) ...[
                      Text(
                        _rainMode
                            ? '雨天モード：屋根付き優先ルート'
                            : '${_mode.label}：おすすめルート',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('距離 ${(best.distanceMeters / 1000).toStringAsFixed(2)}km'
                          '・徒歩 約${(best.durationSeconds / 60).round()}分'),
                      if (_rainMode)
                        Text('屋根付きカバー率 ${(best.coverageScore * 100).round()}%'
                            '（候補 ${_routes.length}本から選択）')
                      else ...[
                        Text('日陰スコア ${best.shadeScore.toStringAsFixed(2)}'
                            '（候補${_routes.length}本: '
                            '${_shadeMin.toStringAsFixed(2)}〜${_shadeMax.toStringAsFixed(2)}）'),
                        if (_routes.length < 2 ||
                            _shadeMax - _shadeMin <= 0.05)
                          Text(
                            _shadeMax <= 0.02
                                ? '※この時間は日射が弱く、日陰/日向の差が出ません'
                                : '※候補間の日陰差が小さく、日陰/日向で同じ経路になります',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.mist),
                          ),
                      ],
                      const Divider(),
                    ] else
                      const Row(
                        children: [
                          Icon(Icons.touch_app_outlined,
                              size: 18, color: AppColors.mist),
                          SizedBox(width: 8),
                          Text('地図を長押しして目的地を設定',
                              style: TextStyle(color: AppColors.mist)),
                        ],
                      ),
                    if (r != null)
                      Text('出発地: 日陰スコア ${r.shadeScore.toStringAsFixed(2)}'
                          '・太陽高度 ${(r.sunAltitudeRad * 180 / 3.14159).toStringAsFixed(1)}°'),
                    Row(
                      children: [
                        // 日付選択（未来日付はプレミアム）
                        TextButton.icon(
                          onPressed: _pickDate,
                          icon: Icon(
                            _isToday(_time) ? Icons.event : Icons.event_available,
                            size: 16,
                          ),
                          label: Text(_dateLabel(_time)),
                        ),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 23,
                            divisions: 23,
                            value: _time.hour.toDouble(),
                            label: '${_time.hour}:00',
                            onChanged: _onHourChanged,
                          ),
                        ),
                        Text('${_time.hour}:00'),
                        if (!isPremium)
                          Tooltip(
                            message: '未来日時はプレミアム機能',
                            child: IconButton(
                              icon: const Icon(Icons.lock_outline, size: 18),
                              color: AppColors.mist,
                              onPressed: () => showPaywall(context),
                            ),
                          )
                        else
                          Tooltip(
                            message: 'プレミアム体験中（タップで解除）',
                            child: IconButton(
                              icon: const Icon(Icons.workspace_premium, size: 18),
                              color: AppColors.rose,
                              onPressed: () => context
                                  .read<PurchaseService>()
                                  .setDemoPremium(false),
                            ),
                          ),
                      ],
                    ),
                      if (best != null && !isPremium) ...[
                        const SizedBox(height: 8),
                        const Center(child: BannerAdWidget()),
                      ],
                    ],
                  ),         // Column
                    ),       // SingleChildScrollView
                  ),         // ConstrainedBox
                ),           // _Frosted
              ),             // Container
            ),               // SafeArea
          );                 // Align (returned from Builder)
          }),                // Builder
        ],
      ),
    );
  }
}

/// 上品なブランドタイトル（中央上部のすりガラス・ピル）。
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.plum.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _Frosted(
        radius: 30,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wb_twilight, size: 18, color: AppColors.rose),
            const SizedBox(width: 8),
            Text('ShadeWalk', style: AppTheme.logo(size: 18)),
          ],
        ),
      ),
    );
  }
}

/// 地図の拡大・縮小・再取得用の丸ボタン。
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = Colors.black87,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// すりガラス（フロスト）効果のコンテナ。背景の地図をぼかして透過する。
class _Frosted extends StatelessWidget {
  const _Frosted({
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 日陰スコアの凡例（薄い→濃いのグラデーションバー）。
class _ShadeLegend extends StatelessWidget {
  const _ShadeLegend({required this.mode, required this.rainMode});

  final WalkMode mode;
  final bool rainMode;

  @override
  Widget build(BuildContext context) {
    final isShade = mode == WalkMode.shade;
    final lo = isShade
        ? const Color(0xFFC3B4D2)
        : const Color(0xFFEAD3A8);
    final hi = isShade ? AppColors.shadow : AppColors.gold;
    final label = rainMode
        ? '屋根カバー'
        : (isShade ? '日かげ度' : '日なた度');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ① ヒートマップタイルの凡例
        Row(
          children: [
            // 正方形サンプル
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [lo.withValues(alpha: 0.5), hi],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isShade ? '日かげスコア（色が濃いほど影が多い）' : '日なたスコア（色が濃いほど日が当たる）',
              style: const TextStyle(fontSize: 10, color: AppColors.mist),
            ),
            const Spacer(),
            // 弱→強グラデーションバー
            const Text('弱', style: TextStyle(fontSize: 9, color: AppColors.mist)),
            const SizedBox(width: 3),
            Container(
              width: 48, height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [lo.withValues(alpha: 0.4), hi],
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Text('強', style: TextStyle(fontSize: 9, color: AppColors.mist)),
          ],
        ),
        const SizedBox(height: 4),
        // ② 影ポリゴンの凡例
        Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: AppColors.shadow.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '影ポリゴン（建物の影が落ちている範囲）',
              style: TextStyle(fontSize: 10, color: AppColors.mist),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // ③ 屋根付き経路の凡例
        Row(
          children: [
            // アーケード（オレンジ線）
            _LegendLine(color: AppColors.arcade),
            const SizedBox(width: 4),
            const Text('アーケード',
                style: TextStyle(fontSize: 10, color: AppColors.mist)),
            const SizedBox(width: 12),
            // 地下道（茶線）
            _LegendLine(color: AppColors.underground),
            const SizedBox(width: 4),
            const Text('地下道',
                style: TextStyle(fontSize: 10, color: AppColors.mist)),
            const SizedBox(width: 4),
            const Text('（雨天モードで優先）',
                style: TextStyle(fontSize: 9, color: AppColors.mist)),
          ],
        ),
      ],
    );
  }
}

/// 凡例用の短いライン描画ウィジェット。
class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
