# ShadeWalk（シェードウォーク）

最短距離ではなく「日陰（または日向）」を優先したルートを案内するナビゲーションアプリ。

## コンセプト
- 夏は **日陰優先**、冬は **日向優先** でルートを提案。
- ターゲット: 熱中症対策、日焼け回避、犬の散歩。

## 技術スタック
- **フレームワーク:** Flutter (Dart)
- **地図:** OpenStreetMap タイル（`flutter_map` + `latlong2`）※キー不要・無料
- **ルート:** 既定は **OSRM 公開API（キー不要・車プロファイル）**で即動作。`ORS_API_KEY` を渡すと **OpenRouteService（foot-walking・歩行に正確）**へ自動切替（無料枠・課金不要）
- **太陽位置計算:** `apsl_sun_calc`（suncalc の Dart/Flutter 移植・Dart3対応）
- **広告:** `google_mobile_ads`（AdMob バナー）
- **課金:** `in_app_purchase`（サブスク / 買い切り）
- **バックエンド:** 原則クライアント完結（必要に応じて Firebase）

## マネタイズ
| 区分 | 機能 |
|------|------|
| 無料 | 現在時刻での日陰ルート検索 + バナー広告 |
| 課金 | 未来時間のルート検索 / 雨天時アーケード・地下道優先 |

## ディレクトリ構造
```
lib/
├── main.dart                       # エントリポイント
├── app.dart                        # MaterialApp / ルーティング
├── core/
│   ├── constants/
│   │   └── app_config.dart         # APIキー・定数
│   ├── geo/                        # 幾何ユーティリティ・GeoJSON・GeoBounds
│   ├── sun/
│   │   └── sun_position.dart       # 太陽位置（apsl_sun_calc ラッパー）
│   ├── shade/
│   │   ├── models/                 # building / shade_result / shadow_polygon
│   │   ├── shadow_projector.dart   # ★影ポリゴン生成（本影＋半影ペナンブラ）
│   │   ├── shade_calculator.dart   # ★コアロジック：日陰スコア算出
│   │   └── mock_buildings.dart     # 擬似建物データ（モック）
│   ├── coverage/                   # ★雨天時の屋根付き経路カバレッジ
│   │   ├── models/covered_way.dart # アーケード/地下道モデル
│   │   ├── mock_covered_ways.dart  # 擬似データ
│   │   └── coverage_scorer.dart    # カバー率採点
│   └── location/
│       └── location_service.dart   # 現在地（geolocator）
├── features/
│   ├── map/
│   │   ├── map_screen.dart         # ★地図表示画面（flutter_map/OSM）
│   │   └── widgets/
│   │       └── mode_toggle.dart    # 日陰/日向モード切替トグル
│   ├── route/                      # ルート検索（OpenRouteService）
│   ├── buildings/                  # 建物データ源（Mock/Asset/PLATEAU）
│   └── paywall/                    # 課金導線
├── monetization/
│   ├── ads/
│   │   └── banner_ad_widget.dart   # AdMobバナー
│   └── iap/
│       └── purchase_service.dart   # 課金管理
└── models/
    └── walk_mode.dart              # 日陰優先 / 日向優先 enum
```

## 建物データ（実データ / PLATEAU 連携）
影計算は `Building`（輪郭＋高さ）にのみ依存し、データ源は
`BuildingRepository` で抽象化されている（[building_repository.dart](lib/features/buildings/building_repository.dart)）。
**既定は `OverpassBuildingRepository`** で、表示中エリアの**実建物（OpenStreetMap）を Overpass API からライブ取得**する（無料・キー不要）。

| 実装 | 用途 |
|------|------|
| `OverpassBuildingRepository`（既定） | OSM の実建物を bbox でライブ取得。高さは `height`→`building:levels`×3m→既定8m |
| `MockBuildingRepository` | 開発・オフライン（東京駅周辺の擬似データ。取得失敗時のフォールバック） |
| `AssetBuildingRepository` | バンドルした GeoJSON（PLATEAU変換等）を読み込む |
| `PlateauBuildingRepository` | bbox 指定で GeoJSON を配信する自前 API から取得 |

> 性能のため取得範囲は `MapScreen._buildingRadiusMeters`（既定400m）・件数は `maxBuildings`（既定400）で制限。

### より高精度に：PLATEAU(CityGML) → GeoJSON 前処理
OSM は高さ情報が欠けている建物も多い。正確な `measuredHeight` を使いたい場合は PLATEAU を使う:
1. [G空間情報センター](https://www.geospatial.jp/ckan/dataset/plateau) から対象都市の建築物モデル（`bldg`）CityGML を取得。
2. `citygml-tools` / `plateau-py` 等で GeoJSON へ変換。各建物に `measuredHeight`（高さ[m]）プロパティを残す。
3. 変換した GeoJSON を `assets/buildings/` に同梱し、`pubspec.yaml` の `flutter: assets:` に登録。
4. `MapScreen` の `_buildingRepo` を
   `AssetBuildingRepository('assets/buildings/tokyo.geojson')` に差し替える。

> GeoJSON の座標順は `[経度, 緯度]`。パーサ側で `LatLng(緯度, 経度)` へ変換済み。

## セットアップ
```bash
flutter pub get
# android/app/src/main/AndroidManifest.xml と ios/Runner/AppDelegate.swift に
# 地図(OSM)はキー不要。ルート検索を使う場合のみ OpenRouteService の無料キーを
# https://openrouteservice.org/dev/ で取得し、下記のように渡す:
#   flutter run --dart-define=ORS_API_KEY=＜キー＞
flutter run
```
